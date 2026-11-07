import Foundation
import CoreServices

/// Real-time filesystem event stream watcher with event debouncing and exclusion filtering.
public final class FSEventWatcher: @unchecked Sendable {
    /// Heap box handed to the FSEvent stream callback.
    ///
    /// The stream owns the box for its whole lifetime, while the box only holds a weak reference
    /// to the watcher. This keeps the callback free of dangling pointers without creating a
    /// retain cycle between the watcher and its own stream.
    private final class CallbackContext: @unchecked Sendable {
        weak var watcher: FSEventWatcher?

        init(watcher: FSEventWatcher) {
            self.watcher = watcher
        }
    }

    private let watchedPath: String
    private let exclusionRules: [ExclusionRule]
    private let debouncingSeconds: Int
    private let onChangeDetected: @Sendable (Date) -> Void

    private var eventStream: FSEventStreamRef?
    private var callbackContext: CallbackContext?
    private let lock = NSLock()
    private var debounceTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.otterkeep.fseventwatcher", qos: .utility)
    private var isRunning = false

    /// Initializes a filesystem event watcher.
    /// - Parameters:
    ///   - watchedPath: Root directory path to monitor.
    ///   - excludePatterns: Glob-like patterns to ignore (same semantics as the backup scanner).
    ///   - debouncingSeconds: Number of seconds of silence to wait before dispatching trigger.
    ///   - onChangeDetected: Closure called when changes settle.
    public init(
        watchedPath: String,
        excludePatterns: [String] = [],
        debouncingSeconds: Int = 30,
        onChangeDetected: @escaping @Sendable (Date) -> Void
    ) {
        self.watchedPath = (watchedPath as NSString).standardizingPath
        self.exclusionRules = excludePatterns.map { ExclusionRule(pattern: $0) }
        self.debouncingSeconds = max(1, debouncingSeconds)
        self.onChangeDetected = onChangeDetected
    }

    /// Starts monitoring the filesystem for changes.
    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        // The stream owns a context box that holds only a weak reference to this watcher, so the
        // callback can never observe a deallocated instance and no retain cycle is created.
        let context = CallbackContext(watcher: self)
        let contextPointer = Unmanaged.passRetained(context).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: contextPointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [watchedPath] as CFArray
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        let callback: FSEventStreamCallback = { (
            streamRef: ConstFSEventStreamRef,
            clientCallBackInfo: UnsafeMutableRawPointer?,
            numEvents: Int,
            eventPaths: UnsafeMutableRawPointer,
            eventFlags: UnsafePointer<FSEventStreamEventFlags>,
            eventIds: UnsafePointer<FSEventStreamEventId>
        ) in
            guard let clientInfo = clientCallBackInfo else { return }
            let context = Unmanaged<CallbackContext>.fromOpaque(clientInfo).takeUnretainedValue()
            guard let watcher = context.watcher else { return }
            guard let paths = FSEventWatcher.decodeEventPaths(eventPaths) else { return }
            watcher.handleEvents(paths: paths, count: numEvents)
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &streamContext,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency in seconds
            flags
        ) else {
            Unmanaged<CallbackContext>.fromOpaque(contextPointer).release()
            return
        }

        self.eventStream = stream
        self.callbackContext = context
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) {
            isRunning = true
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.eventStream = nil
            self.callbackContext = nil
            Unmanaged<CallbackContext>.fromOpaque(contextPointer).release()
        }
    }

    /// Stops monitoring and cancels any pending debounce timers.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    deinit {
        lock.lock()
        stopLocked()
        lock.unlock()
    }

    /// Tears down the event stream. Caller must hold `lock`.
    private func stopLocked() {
        guard isRunning, let stream = eventStream else { return }

        debounceTimer?.cancel()
        debounceTimer = nil

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.eventStream = nil
        self.isRunning = false

        // Balance the retain taken in `start()`. The box is released only after the stream has
        // been invalidated, so no callback can be in flight while it is being freed.
        if let context = callbackContext {
            self.callbackContext = nil
            Unmanaged<CallbackContext>.passUnretained(context).release()
        }
    }

    /// Decodes the `eventPaths` payload of an FSEvent stream callback.
    ///
    /// With `kFSEventStreamCreateFlagUseCFTypes` the payload is a `CFArray` of `CFString`s, but
    /// the bridge is not guaranteed for every event batch, so both representations are handled.
    /// - Parameter eventPaths: Raw pointer supplied by the event stream.
    /// - Returns: The decoded paths, or `nil` when the payload cannot be interpreted.
    private static func decodeEventPaths(_ eventPaths: UnsafeMutableRawPointer) -> [String]? {
        let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
        if let paths = array as? [String] {
            return paths
        }
        if let urls = array as? [NSURL] {
            return urls.compactMap { $0.path }
        }
        return nil
    }

    // MARK: - Internal Event Processing

    private func handleEvents(paths: [String], count: Int) {
        var hasRelevantChange = false

        for path in paths {
            if isExcluded(path: path) {
                continue
            }
            hasRelevantChange = true
            break
        }

        guard hasRelevantChange else { return }

        // Schedule or reset debouncing timer
        queue.async { [weak self] in
            self?.resetDebounceTimer()
        }
    }

    private func resetDebounceTimer() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else { return }

        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(debouncingSeconds))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.debounceTimer?.cancel()
            self.debounceTimer = nil
            let active = self.isRunning
            self.lock.unlock()

            if active {
                self.onChangeDetected(Date())
            }
        }
        timer.resume()
        self.debounceTimer = timer
    }

    private func isExcluded(path: String) -> Bool {
        // Internal OtterKeep artifacts
        if path.contains(".otterkeep") || path.contains(".otterkeep_canary") {
            return true
        }

        // Temporary or ephemeral files
        let lower = path.lowercased()
        if lower.hasSuffix(".tmp") || lower.hasSuffix(".crdownload") || lower.hasSuffix(".part") || lower.contains("/.trashes") || lower.contains("/.ds_store") {
            return true
        }

        // User-configured patterns, evaluated with the same glob semantics as the backup scanner.
        return exclusionRules.contains { $0.matches(absolutePath: path) }
    }
}
