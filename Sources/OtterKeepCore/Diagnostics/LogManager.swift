import Foundation
import os

/// Individual diagnostic log record with timestamp, severity level, category, and message text.
public struct LogEntry: Identifiable, Sendable, Codable, Equatable {
    /// Unique identifier of the log entry.
    public let id: UUID
    /// Timestamp when the entry was created.
    public let timestamp: Date
    /// Severity level.
    public let level: LogLevel
    /// Subsystem category (e.g. "Backup", "Scheduler", "Storage", "UI").
    public let category: String
    /// Detailed log message.
    public let message: String

    /// Severity levels for logging.
    public enum LogLevel: String, Sendable, Codable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    /// Initializes a `LogEntry`.
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel = .info,
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

/// Thread-safe centralized logger maintaining in-memory ring buffers, privacy sanitization,
/// macOS Unified Logging mirroring, debounced JSON persistence, and timestamped .log file debugging sessions.
public final class LogManager: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = LogManager()

    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private let maxEntries = 3000
    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.otterkeep.logpersist", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    /// Persistent directory path for logs (`~/Library/Logs/OtterKeep/`).
    public var logDirectory: URL {
        DebugFileLogger.shared.logsDirectory
    }

    /// Full path to the persisted `logs.json` file (`~/Library/Logs/OtterKeep/logs.json`).
    public var logFileURL: URL {
        logDirectory.appendingPathComponent("logs.json")
    }

    /// Legacy logs file URL (`~/.otterkeep/logs.json`) for backward-compatibility migration.
    public var legacyLogFileURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".otterkeep", isDirectory: true)
            .appendingPathComponent("logs.json")
    }

    /// Standard directory for structured timestamped `.log` files (`~/Library/Logs/OtterKeep/`).
    public var debugLogsDirectory: URL {
        DebugFileLogger.shared.logsDirectory
    }

    /// Currently active `.log` file URL if debug file logging is active.
    public var currentDebugLogFileURL: URL? {
        DebugFileLogger.shared.currentLogFileURL
    }

    /// Whether debug file logging is currently active.
    public var isDebugFileLoggingEnabled: Bool {
        DebugFileLogger.shared.isEnabled
    }

    private init() {
        loadPersistedLogs()
        // If persisted settings have debug file logging enabled, auto-start session
        if LocalizationManager.shared.settings.debugFileLoggingEnabled {
            _ = DebugFileLogger.shared.startSession()
        }
    }

    private func createDirectoryIfNeeded() {
        let dir = logDirectory
        if !fileManager.fileExists(atPath: dir.path(percentEncoded: false)) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func loadPersistedLogs() {
        createDirectoryIfNeeded()
        let file = logFileURL

        // Migration from legacy ~/.otterkeep/logs.json if needed
        if !fileManager.fileExists(atPath: file.path(percentEncoded: false)),
           fileManager.fileExists(atPath: legacyLogFileURL.path(percentEncoded: false)) {
            try? fileManager.moveItem(at: legacyLogFileURL, to: file)
        }

        guard fileManager.fileExists(atPath: file.path(percentEncoded: false)),
              let data = try? Data(contentsOf: file) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([LogEntry].self, from: data) {
            lock.lock()
            self.entries = loaded
            lock.unlock()
        }
    }

    /// Starts a new timestamped debug logging session writing human-readable, non-overwriting `.log` files.
    /// - Parameter persistSetting: Whether to persist this choice into AppSettings.
    /// - Returns: URL of the newly created `.log` file.
    @discardableResult
    public func enableDebugFileLogging(persistSetting: Bool = true) -> URL {
        let fileURL = DebugFileLogger.shared.startSession()
        if persistSetting {
            var settings = LocalizationManager.shared.settings
            settings.debugFileLoggingEnabled = true
            LocalizationManager.shared.settings = settings
        }
        log("Diagnostic debug file logging enabled. Target: \(fileURL.lastPathComponent)", level: .info, category: "Diagnostics")
        return fileURL
    }

    /// Disables active debug file logging session and closes the file handle.
    /// - Parameter persistSetting: Whether to persist this choice into AppSettings.
    public func disableDebugFileLogging(persistSetting: Bool = true) {
        log("Diagnostic debug file logging disabled.", level: .info, category: "Diagnostics")
        DebugFileLogger.shared.stopSession()
        if persistSetting {
            var settings = LocalizationManager.shared.settings
            settings.debugFileLoggingEnabled = false
            LocalizationManager.shared.settings = settings
        }
    }

    /// Lists all existing timestamped `.log` files, ordered newest first.
    /// - Returns: Array of `.log` file URLs.
    public func listDebugLogFiles() -> [URL] {
        DebugFileLogger.shared.listLogFiles()
    }

    /// Appends a new message to the diagnostic log, sanitizing sensitive PII/usernames/paths,
    /// mirroring to macOS Unified Logging, appending to active debug .log file, and queueing disk persistence.
    /// - Parameters:
    ///   - message: Raw log message text (will be sanitized for privacy).
    ///   - level: Severity level (default: `.info`).
    ///   - category: Category string (default: `"General"`).
    public func log(_ message: String, level: LogEntry.LogLevel = .info, category: String = "General") {
        let sanitized = LogPrivacySanitizer.sanitize(message)
        let entry = LogEntry(level: level, category: category, message: sanitized)

        // Include entry in in-memory ring buffer if not debug, OR if verbose/debug logging is enabled
        let shouldRetainInMemory = (level != .debug) || DebugFileLogger.shared.isEnabled || LocalizationManager.shared.settings.debugFileLoggingEnabled
        if shouldRetainInMemory {
            lock.lock()
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
            let currentSnapshot = entries
            lock.unlock()

            // Debounced disk write for JSON ring buffer
            scheduleSave(currentSnapshot)
        }

        // Write to active timestamped .log file if enabled (receives all levels, including .debug)
        if DebugFileLogger.shared.isEnabled {
            DebugFileLogger.shared.appendLog(
                sanitizedMessage: sanitized,
                level: level.rawValue,
                category: category,
                timestamp: entry.timestamp
            )
        }

        // Mirror to macOS Unified Logging
        let osLogger = Logger(subsystem: "com.otterkeep", category: category)
        switch level {
        case .debug: osLogger.debug("\(sanitized)")
        case .info: osLogger.info("\(sanitized)")
        case .warning: osLogger.warning("\(sanitized)")
        case .error: osLogger.error("\(sanitized)")
        }
    }

    private func scheduleSave(_ currentEntries: [LogEntry]) {
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            self.saveWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.writeLogsToDisk(currentEntries)
            }
            self.saveWorkItem = workItem
            self.saveQueue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
    }

    private func writeLogsToDisk(_ logs: [LogEntry]) {
        createDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(logs) {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    /// Flushes any pending in-memory log entries directly to disk and synchronizes active debug `.log` file immediately.
    public func flush() {
        lock.lock()
        let current = entries
        lock.unlock()
        writeLogsToDisk(current)
        DebugFileLogger.shared.flush()
    }

    /// Returns a snapshot copy of all recorded log entries.
    /// - Returns: Array of `LogEntry` records.
    public func getEntries() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// Serializes current log records into formatted JSON data.
    /// - Returns: Encoded JSON Data.
    public func exportLogsAsJSON() throws -> Data {
        let currentEntries = getEntries()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(currentEntries)
    }

    /// Formats all log entries into a plain text diagnostic report string.
    /// - Returns: Multi-line plain text log report.
    public func exportLogsAsPlainText() -> String {
        let currentEntries = getEntries()
        let formatter = ISO8601DateFormatter()
        return currentEntries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] [\(entry.category)]: \(entry.message)"
        }.joined(separator: "\n")
    }

    /// Clears all in-memory and on-disk diagnostic log entries.
    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        try? fileManager.removeItem(at: logFileURL)
        try? fileManager.removeItem(at: legacyLogFileURL)
    }
}
