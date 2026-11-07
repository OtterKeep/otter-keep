import Foundation
import Darwin
import os
import OtterKeepStorage
import OtterKeepDatabase

/// Result metrics of an on-demand or scheduled data scrubbing run.
public struct ScrubRunProgress: Sendable, Equatable {
    public var currentSnapshot: String
    public var currentFile: String
    public var checkedFiles: Int
    public var totalFiles: Int
    public var corruptedFilesCount: Int
    public var isComplete: Bool

    public init(
        currentSnapshot: String = "",
        currentFile: String = "",
        checkedFiles: Int = 0,
        totalFiles: Int = 0,
        corruptedFilesCount: Int = 0,
        isComplete: Bool = false
    ) {
        self.currentSnapshot = currentSnapshot
        self.currentFile = currentFile
        self.checkedFiles = checkedFiles
        self.totalFiles = totalFiles
        self.corruptedFilesCount = corruptedFilesCount
        self.isComplete = isComplete
    }
}

/// Actor executing background bit-rot detection and cryptographic data scrubbing across historical snapshots.
public actor DataScrubberEngine {
    private let storage: FileSystemProvider
    private let database: DatabaseEngine
    private let logger = Logger(subsystem: "com.otterkeep", category: "DataScrubber")

    public init(
        storage: FileSystemProvider = DefaultFileSystemProvider(),
        database: DatabaseEngine = DatabaseEngine()
    ) {
        self.storage = storage
        self.database = database
    }

    /// Performs an exhaustive cryptographic scrubbing pass over snapshots on the specified backup destination.
    /// - Parameters:
    ///   - backupRootURL: Root backup folder URL.
    ///   - limitSnapshots: Optional maximum count of recent snapshots to inspect (default: nil = all).
    ///   - throttleSleepMs: Micro-sleep duration in milliseconds between file checks to throttle I/O.
    ///   - onProgress: Optional progress callback.
    /// - Returns: A persisted `ScrubAuditRecord` documenting the results.
    public func performScrub(
        backupRootURL: URL,
        limitSnapshots: Int? = nil,
        throttleSleepMs: UInt64 = 0,
        onProgress: (@Sendable (ScrubRunProgress) -> Void)? = nil
    ) async throws -> ScrubAuditRecord {
        let startTime = Date()
        logger.info("Initiating background data scrubbing pass on: \(backupRootURL.path)")

        let internalDir = backupRootURL.standardizedFileURL.appendingPathComponent(".otterkeep")
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)
        try await database.open(at: dbPath)
        defer {
            Task { await database.close() }
        }

        var snapshots = try await database.listSnapshots()
        if let limit = limitSnapshots, limit > 0 {
            snapshots = Array(snapshots.prefix(limit))
        }

        var checkedFilesCount = 0
        var corruptedFiles: [String] = []

        var totalFilesToInspect = 0
        for snap in snapshots {
            let files = try await database.listFiles(forSnapshotId: snap.id)
            totalFilesToInspect += files.filter { $0.checksum != nil && !$0.isDirectory && !$0.isSymlink }.count
        }

        var progress = ScrubRunProgress(totalFiles: totalFilesToInspect)

        for snap in snapshots {
            try Task.checkCancellation()

            let snapRoot = backupRootURL.standardizedFileURL
                .appendingPathComponent(snap.snapshotPath)
                .appendingPathComponent("root")

            let files = try await database.listFiles(forSnapshotId: snap.id)
            for record in files where record.checksum != nil && !record.isDirectory && !record.isSymlink {
                try Task.checkCancellation()

                // Thermal state governance: if device is under heavy thermal pressure, pause momentarily
                if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500 ms cool-off
                }

                // Adaptive I/O throttling micro-sleep
                if throttleSleepMs > 0 {
                    try? await Task.sleep(nanoseconds: throttleSleepMs * 1_000_000)
                }

                let fileURL = snapRoot.appendingPathComponent(record.relativePath)
                let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)

                progress.currentSnapshot = snap.id
                progress.currentFile = record.relativePath
                progress.checkedFiles = checkedFilesCount
                progress.corruptedFilesCount = corruptedFiles.count
                onProgress?(progress)

                guard FileManager.default.fileExists(atPath: filePath) else {
                    corruptedFiles.append("[\(snap.id)] Missing: \(record.relativePath)")
                    continue
                }

                do {
                    let actualChecksum = try ChecksumCalculator.computeSHA256(for: fileURL)
                    if let expected = record.checksum, actualChecksum.caseInsensitiveCompare(expected) != .orderedSame {
                        logger.error("BIT-ROT DETECTED in snapshot '\(snap.id)' for '\(record.relativePath)'! Expected: \(expected), Actual: \(actualChecksum)")
                        corruptedFiles.append("[\(snap.id)] Bit-rot: \(record.relativePath) (Expected: \(expected.prefix(8)), Actual: \(actualChecksum.prefix(8)))")
                    }
                } catch {
                    corruptedFiles.append("[\(snap.id)] Read error: \(record.relativePath) (\(error.localizedDescription))")
                }

                checkedFilesCount += 1
            }
        }

        let status = corruptedFiles.isEmpty ? "healthy" : "corruption_detected"
        let detailsJson: String?
        if !corruptedFiles.isEmpty {
            detailsJson = try? String(data: JSONSerialization.data(withJSONObject: ["corrupted": corruptedFiles], options: [.prettyPrinted]), encoding: .utf8)
        } else {
            detailsJson = nil
        }

        let auditRecord = ScrubAuditRecord(
            timestamp: startTime,
            checkedSnapshotsCount: snapshots.count,
            checkedFilesCount: checkedFilesCount,
            corruptedFilesCount: corruptedFiles.count,
            status: status,
            detailsJson: detailsJson
        )

        try await database.insertScrubAudit(auditRecord)

        progress.isComplete = true
        progress.checkedFiles = checkedFilesCount
        progress.corruptedFilesCount = corruptedFiles.count
        onProgress?(progress)

        if corruptedFiles.isEmpty {
            logger.info("Data scrubbing completed cleanly: \(checkedFilesCount) files verified across \(snapshots.count) snapshots.")
            LogManager.shared.log("Data Scrubbing pass: \(checkedFilesCount) files verified across \(snapshots.count) snapshots. All blocks healthy (No bit-rot detected).", level: .info, category: "Integrity")
        } else {
            logger.error("Data scrubbing finished with \(corruptedFiles.count) corrupted files detected!")
            LogManager.shared.log("WARNING: Data Scrubbing pass detected errors! \(corruptedFiles.count) corrupted or missing files found.", level: .error, category: "Integrity")

            // Proactively alert the user via macOS native notification center
            let firstSnapshot = snapshots.first?.id ?? "unknown"
            NotificationDeliveryService.shared.notifyScrubCorruptionDetected(
                corruptedCount: corruptedFiles.count,
                snapshotId: firstSnapshot
            )
        }

        await database.close()
        return auditRecord
    }

    /// Spawns an asynchronous, low-priority background data scrubbing task with `.background` QoS and adaptive I/O throttling.
    public nonisolated func performSilentBackgroundScrub(
        backupRootURL: URL,
        limitSnapshots: Int? = nil,
        throttleSleepMs: UInt64 = 5,
        onProgress: (@Sendable (ScrubRunProgress) -> Void)? = nil
    ) -> Task<ScrubAuditRecord, Error> {
        Task(priority: .background) {
            return try await self.performScrub(
                backupRootURL: backupRootURL,
                limitSnapshots: limitSnapshots,
                throttleSleepMs: throttleSleepMs,
                onProgress: onProgress
            )
        }
    }
}
