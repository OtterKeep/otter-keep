import Foundation
import CoreServices

/// Real-time filesystem event stream watcher with event debouncing and exclusion filtering.
public final class FSEventWatcher: @unchecked Sendable {
    private let watchedPath: String
    private let excludePatterns: [String]
    private let debouncingSeconds: Int
    private let onChangeDetected: @Sendable (Date) -> Void

    private var eventStream: FSEventStreamRef?
    private let lock = NSLock()
    private var debounceTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.otterkeep.fseventwatcher", qos: .utility)
    private var isRunning = false

    /// Initializes a filesystem event watcher.
    /// - Parameters:
    ///   - watchedPath: Root directory path to monitor.
    ///   - excludePatterns: Substring or glob-like patterns to ignore.
    ///   - debouncingSeconds: Number of seconds of silence to wait before dispatching trigger.
    ///   - onChangeDetected: Closure called when changes settle.
    public init(
        watchedPath: String,
        excludePatterns: [String] = [],
        debouncingSeconds: Int = 30,
        onChangeDetected: @escaping @Sendable (Date) -> Void
    ) {
        self.watchedPath = (watchedPath as NSString).standardizingPath
        self.excludePatterns = excludePatterns
        self.debouncingSeconds = max(1, debouncingSeconds)
        self.onChangeDetected = onChangeDetected
    }

    /// Starts monitoring the filesystem for changes.
    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
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
            let watcher = Unmanaged<FSEventWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            watcher.handleEvents(paths: paths, count: numEvents)
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency in seconds
            flags
        ) else {
            return
        }

        self.eventStream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) {
            isRunning = true
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.eventStream = nil
        }
    }

    /// Stops monitoring and cancels any pending debounce timers.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning, let stream = eventStream else { return }

        debounceTimer?.cancel()
        debounceTimer = nil

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.eventStream = nil
        self.isRunning = false
    }

    deinit {
        stop()
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

        for pattern in excludePatterns {
            if path.contains(pattern) {
                return true
            }
        }

        return false
    }
}
