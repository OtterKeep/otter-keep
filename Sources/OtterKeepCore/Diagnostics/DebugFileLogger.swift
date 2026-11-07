import Foundation

/// High-performance, append-only debug logger writing structured, human-readable `.log` files with unique timestamps.
///
/// Features:
/// - Never overwrites existing log files (always creates a new timestamped file).
/// - Thread-safe asynchronous writes using a serial background queue.
/// - Formatted header with system environment metadata and privacy notice.
/// - Real-time flushing capabilities for fatal or critical errors.
public final class DebugFileLogger: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = DebugFileLogger()

    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let writeQueue = DispatchQueue(label: "com.otterkeep.debugfilelogger", qos: .utility)

    private var activeFileURL: URL?
    private var fileHandle: FileHandle?
    private var isLoggingActive: Bool = false

    /// Standard logs directory located at `~/Library/Logs/OtterKeep/` conforming to Apple's native logging location.
    public var logsDirectory: URL {
        let baseDir: URL
        if let pw = getpwuid(getuid()) {
            let realHome = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
            baseDir = realHome.appendingPathComponent("Library/Logs", isDirectory: true)
        } else {
            baseDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Logs", isDirectory: true)
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
        }
        return baseDir.appendingPathComponent("OtterKeep", isDirectory: true)
    }

    /// Legacy logs directory located at `~/.otterkeep/logs/` (for backward-compatibility migration).
    public var legacyLogsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".otterkeep", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    /// Currently active `.log` file URL, if a session is active.
    public var currentLogFileURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return activeFileURL
    }

    /// Whether debug file logging is currently active.
    public var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isLoggingActive
    }

    private let lineDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZ"
        return df
    }()

    private init() {
        createLogsDirectoryIfNeeded()
    }

    deinit {
        stopSession()
    }

    private func createLogsDirectoryIfNeeded() {
        let dir = logsDirectory
        if !fileManager.fileExists(atPath: dir.path(percentEncoded: false)) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Migrate any legacy logs from ~/.otterkeep/logs/
        let legacyDir = legacyLogsDirectory
        if fileManager.fileExists(atPath: legacyDir.path(percentEncoded: false)) {
            if let files = try? fileManager.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension.lowercased() == "log" {
                    let dest = dir.appendingPathComponent(file.lastPathComponent)
                    if !fileManager.fileExists(atPath: dest.path(percentEncoded: false)) {
                        try? fileManager.moveItem(at: file, to: dest)
                    }
                }
            }
            try? fileManager.removeItem(at: legacyDir)
        }
    }

    /// Starts a new diagnostic logging session with a unique, timestamped `.log` file.
    /// Never overwrites existing files.
    /// - Returns: The URL of the newly created `.log` file.
    @discardableResult
    public func startSession() -> URL {
        lock.lock()
        if isLoggingActive, let currentURL = activeFileURL {
            lock.unlock()
            return currentURL
        }

        createLogsDirectoryIfNeeded()

        // Generate unique timestamped filename
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestampStr = timeFormatter.string(from: Date())

        var baseFileName = "otterkeep-\(timestampStr).log"
        var candidateURL = logsDirectory.appendingPathComponent(baseFileName)
        var counter = 1

        // Collision avoidance: ensure file does not exist
        while fileManager.fileExists(atPath: candidateURL.path(percentEncoded: false)) {
            baseFileName = "otterkeep-\(timestampStr)_\(counter).log"
            candidateURL = logsDirectory.appendingPathComponent(baseFileName)
            counter += 1
        }

        // Create empty file
        fileManager.createFile(atPath: candidateURL.path(percentEncoded: false), contents: nil)

        let handle = try? FileHandle(forWritingTo: candidateURL)
        self.fileHandle = handle
        self.activeFileURL = candidateURL
        self.isLoggingActive = true
        lock.unlock()

        // Write header
        writeSessionHeader(to: handle, fileURL: candidateURL)

        return candidateURL
    }

    /// Stops the current diagnostic logging session, closing the file handle.
    public func stopSession() {
        lock.lock()
        guard isLoggingActive else {
            lock.unlock()
            return
        }

        isLoggingActive = false
        let handle = fileHandle
        fileHandle = nil
        activeFileURL = nil
        lock.unlock()

        writeQueue.sync {
            try? handle?.synchronize()
            try? handle?.close()
        }
    }

    private func writeSessionHeader(to handle: FileHandle?, fileURL: URL) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.string(from: Date())
        let sessionId = UUID().uuidString

        #if arch(arm64)
        let arch = "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        let arch = "x86_64 (Intel)"
        #else
        let arch = "unknown"
        #endif

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let header = """
        # ==============================================================================
        # OtterKeep Diagnostic Debug Log
        # Session Started: \(timestamp)
        # Engine Version: \(CoreEngine.version) (Build \(CoreEngine.buildNumber)) | Architecture: \(arch)
        # Components: \(CoreEngine.componentVersionsFormatted)
        # macOS Version: \(osVersion)
        # Session ID: \(sessionId)
        # Privacy Sanitization: ACTIVE (Usernames, paths, and PII are redacted)
        # Log File: \(fileURL.lastPathComponent)
        # ==============================================================================

        """


        writeQueue.async {
            if let data = header.data(using: .utf8) {
                try? handle?.write(contentsOf: data)
                try? handle?.synchronize()
            }
        }
    }

    /// Appends a sanitized log record to the active `.log` file.
    /// - Parameters:
    ///   - sanitizedMessage: Pre-sanitized message text.
    ///   - level: Severity level label.
    ///   - category: Logging subsystem category.
    ///   - timestamp: Timestamp of the event.
    public func appendLog(
        sanitizedMessage: String,
        level: String,
        category: String,
        timestamp: Date = Date()
    ) {
        lock.lock()
        guard isLoggingActive, let handle = fileHandle else {
            lock.unlock()
            return
        }
        let timeStr = lineDateFormatter.string(from: timestamp)
        lock.unlock()

        let line = "[\(timeStr)] [\(level)] [\(category)]: \(sanitizedMessage)\n"

        writeQueue.async {
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
    }

    /// Forces any pending buffered log lines to be committed to disk immediately.
    public func flush() {
        lock.lock()
        let handle = fileHandle
        lock.unlock()

        writeQueue.sync {
            try? handle?.synchronize()
        }
    }

    /// Lists all persisted `.log` files in `~/.otterkeep/logs/`, sorted newest first.
    /// - Returns: Array of `.log` file URLs.
    public func listLogFiles() -> [URL] {
        createLogsDirectoryIfNeeded()
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return fileURLs
            .filter { $0.pathExtension.lowercased() == "log" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
    }
}
