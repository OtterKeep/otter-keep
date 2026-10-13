import Foundation

/// Pure domain representation of a background data integrity scrubbing audit record.
public struct ScrubAuditRecord: Sendable, Identifiable, Equatable {
    /// Primary key.
    public let id: Int64
    /// Timestamp when scrubbing completed.
    public let timestamp: Date
    /// Total snapshots inspected.
    public let checkedSnapshotsCount: Int
    /// Total files checksum-verified.
    public let checkedFilesCount: Int
    /// Count of corrupted files discovered (bit-rot).
    public let corruptedFilesCount: Int
    /// Overall audit status ("healthy", "corruption_detected", "failed").
    public let status: String
    /// JSON details of any corrupted items or audit log.
    public let detailsJson: String?

    public init(
        id: Int64 = 0,
        timestamp: Date,
        checkedSnapshotsCount: Int,
        checkedFilesCount: Int,
        corruptedFilesCount: Int,
        status: String,
        detailsJson: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.checkedSnapshotsCount = checkedSnapshotsCount
        self.checkedFilesCount = checkedFilesCount
        self.corruptedFilesCount = corruptedFilesCount
        self.status = status
        self.detailsJson = detailsJson
    }
}

/// Pure domain representation of a snapshot replication event / status.
public struct ReplicationSnapshotRecord: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let snapshotId: String
    public let destinationType: String
    public let destinationIdentifier: String
    public let status: String
    public let replicatedBytes: Int64
    public let totalBytes: Int64
    public let startedAt: Date
    public let completedAt: Date?
    public let errorMessage: String?

    public init(
        id: Int64 = 0,
        snapshotId: String,
        destinationType: String,
        destinationIdentifier: String,
        status: String = "pending",
        replicatedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.destinationType = destinationType
        self.destinationIdentifier = destinationIdentifier
        self.status = status
        self.replicatedBytes = replicatedBytes
        self.totalBytes = totalBytes
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }
}

/// Pure domain representation of an individual file's replication status.
public struct ReplicationFileRecord: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let snapshotId: String
    public let destinationIdentifier: String
    public let relativePath: String
    public let remoteKey: String
    public let remoteETag: String?
    public let checksum: String?
    public let fileSize: Int64
    public let status: String

    public init(
        id: Int64 = 0,
        snapshotId: String,
        destinationIdentifier: String,
        relativePath: String,
        remoteKey: String,
        remoteETag: String? = nil,
        checksum: String? = nil,
        fileSize: Int64,
        status: String = "replicated"
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.destinationIdentifier = destinationIdentifier
        self.relativePath = relativePath
        self.remoteKey = remoteKey
        self.remoteETag = remoteETag
        self.checksum = checksum
        self.fileSize = fileSize
        self.status = status
    }
}
