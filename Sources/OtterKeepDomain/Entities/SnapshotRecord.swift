import Foundation

/// Pure domain entity representing an immutable snapshot in the backup catalog.
public struct SnapshotRecord: Sendable, Identifiable, Equatable {
    /// Unique snapshot identifier (e.g. "snapshot_2026-09-26_173000").
    public let id: String
    /// Snapshot creation timestamp.
    public let timestamp: Date
    /// Completion status ("completed", "completed_with_warnings", "completed_with_errors").
    public let status: String
    /// Total number of indexed files and directories in this snapshot.
    public let totalFiles: Int64
    /// Total logical byte size of all files in this snapshot.
    public let totalBytes: Int64
    /// Relative directory path on the backup destination disk (e.g. "2026-09-26_173000").
    public let snapshotPath: String
    /// Type of the backup ("incremental" or "full").
    public let backupType: String
    /// Immutability lock expiration date (nil if not locked).
    public let lockedUntil: Date?

    /// Initializes a new `SnapshotRecord`.
    public init(
        id: String,
        timestamp: Date,
        status: String,
        totalFiles: Int64,
        totalBytes: Int64,
        snapshotPath: String,
        backupType: String = "incremental",
        lockedUntil: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.status = status
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.snapshotPath = snapshotPath
        self.backupType = backupType
        self.lockedUntil = lockedUntil
    }

    /// Whether this snapshot is currently immutable and protected against pruning.
    public var isLocked: Bool {
        guard let lockDate = lockedUntil else { return false }
        return lockDate > Date()
    }
}
