import Foundation
import SQLite3
import os

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
    /// - Parameters:
    ///   - id: Unique snapshot ID.
    ///   - timestamp: Creation timestamp.
    ///   - status: Completion status.
    ///   - totalFiles: Total indexed items count.
    ///   - totalBytes: Total byte size.
    ///   - snapshotPath: Relative snapshot directory name.
    ///   - backupType: Backup type ("incremental" or "full").
    ///   - lockedUntil: Optional immutability lock expiration date.
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

/// Representation of a deferred or pending secondary replication task awaiting destination availability.
public struct PendingReplicationRecord: Sendable, Identifiable, Equatable {
    public let id: String
    public let profileId: UUID
    public let snapshotId: String
    public let destinationId: UUID
    public let destinationType: String
    public let status: String
    public let retryCount: Int
    public let createdAt: Date
    public let lastAttemptAt: Date?
    public let errorMessage: String?

    public init(
        id: String = UUID().uuidString,
        profileId: UUID,
        snapshotId: String,
        destinationId: UUID,
        destinationType: String,
        status: String = "pending",
        retryCount: Int = 0,
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.profileId = profileId
        self.snapshotId = snapshotId
        self.destinationId = destinationId
        self.destinationType = destinationType
        self.status = status
        self.retryCount = retryCount
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.errorMessage = errorMessage
    }
}

/// Representation of an indexed file or directory record in a specific snapshot catalog.
public struct FileCatalogRecord: Sendable, Identifiable, Equatable {
    /// Primary key in the database (0 for unpersisted records).
    public let id: Int64
    /// Associated snapshot identifier foreign key.
    public let snapshotId: String
    /// Relative path from the snapshot root folder (e.g. "Projects/App/main.swift").
    public let relativePath: String
    /// Logical file size in bytes (0 for directories).
    public let fileSize: Int64
    /// Last modification timestamp.
    public let modificationTime: Date
    /// Inode number on the filesystem.
    public let inode: UInt64
    /// Optional cryptographic SHA-256 hash (hex string).
    public let checksum: String?
    /// Optional fast sparse sample hash (head/mid/tail 64KB digest).
    public let sampleHash: String?
    /// True if this catalog entry is a directory.
    public let isDirectory: Bool
    /// True if this catalog entry is a symbolic link.
    public let isSymlink: Bool

    /// Initializes a new `FileCatalogRecord`.
    public init(
        id: Int64 = 0,
        snapshotId: String,
        relativePath: String,
        fileSize: Int64,
        modificationTime: Date,
        inode: UInt64,
        checksum: String? = nil,
        sampleHash: String? = nil,
        isDirectory: Bool,
        isSymlink: Bool
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.modificationTime = modificationTime
        self.inode = inode
        self.checksum = checksum
        self.sampleHash = sampleHash
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
    }
}

/// Representation of a cross-snapshot global search hit in the catalog.
public struct GlobalSearchResult: Sendable, Identifiable, Equatable {
    public var id: String { "\(snapshotId)_\(relativePath)" }
    public let snapshotId: String
    public let snapshotTimestamp: Date
    public let snapshotPath: String
    public let relativePath: String
    public let fileSize: Int64
    public let modificationDate: Date
    public let sha256: String

    public var snapshotDate: Date { snapshotTimestamp }

    public var fileRecord: FileCatalogRecord {
        FileCatalogRecord(
            snapshotId: snapshotId,
            relativePath: relativePath,
            fileSize: fileSize,
            modificationTime: modificationDate,
            inode: 0,
            checksum: sha256.isEmpty ? nil : sha256,
            sampleHash: nil,
            isDirectory: false,
            isSymlink: false
        )
    }

    public init(
        snapshotId: String,
        snapshotTimestamp: Date,
        snapshotPath: String = "",
        relativePath: String,
        fileSize: Int64,
        modificationDate: Date,
        sha256: String
    ) {
        self.snapshotId = snapshotId
        self.snapshotTimestamp = snapshotTimestamp
        self.snapshotPath = snapshotPath
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.sha256 = sha256
    }
}

/// Representation of an indexed Photos item record in a Photos backup snapshot catalog.
public struct PhotosAssetRecord: Sendable, Identifiable, Equatable {
    /// Primary key in the database (0 for unpersisted records).
    public let id: Int64
    /// Associated snapshot identifier foreign key.
    public let snapshotId: String
    /// Unique Photos.app local identifier (e.g. "ED123456-7890-.../L0/001").
    public let localIdentifier: String
    /// Original file name (e.g. "IMG_1234.HEIC").
    public let originalFilename: String
    /// Relative path within the snapshot destination (e.g. "Originals/2026/09/IMG_1234.HEIC").
    public let relativePath: String
    /// Logical file size in bytes.
    public let fileSize: Int64
    /// Modification timestamp in Photos library.
    public let modificationTime: Date
    /// Optional SHA-256 checksum.
    public let sha256: String?
    /// Indicates whether this represents an adjusted/edited version.
    public let isEdited: Bool
    /// Indicates whether this asset is part of a Live Photo pair.
    public let isLivePhoto: Bool
    /// Media type ("image", "video", "audio").
    public let mediaType: String
    /// JSON serialized array of album names.
    public let albumsJson: String?

    /// Initializes a new `PhotosAssetRecord`.
    public init(
        id: Int64 = 0,
        snapshotId: String,
        localIdentifier: String,
        originalFilename: String,
        relativePath: String,
        fileSize: Int64,
        modificationTime: Date,
        sha256: String? = nil,
        isEdited: Bool = false,
        isLivePhoto: Bool = false,
        mediaType: String = "image",
        albumsJson: String? = nil
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.localIdentifier = localIdentifier
        self.originalFilename = originalFilename
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.modificationTime = modificationTime
        self.sha256 = sha256
        self.isEdited = isEdited
        self.isLivePhoto = isLivePhoto
        self.mediaType = mediaType
        self.albumsJson = albumsJson
    }
}

/// Representation of a background data integrity scrubbing audit record.
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

/// Representation of a snapshot replication event / status stored in SQLite.
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

/// Representation of an individual file's replication status.
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


/// Structured errors encountered during SQLite catalog database operations.
public enum DatabaseError: Error, Sendable, LocalizedError {
    /// Failed to open or initialize the SQLite database connection.
    case openFailed(String)
    /// SQL statement execution failed.
    case executionFailed(String, String)
    /// SQL query compilation/preparation failed.
    case prepareFailed(String, String)
    /// SQL statement step iteration failed.
    case stepFailed(String, String)

    /// Human-readable localized error description.
    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Database connection error: \(msg)"
        case .executionFailed(let query, let msg): return "SQL execution error '\(query)': \(msg)"
        case .prepareFailed(let query, let msg): return "SQL prepare error '\(query)': \(msg)"
        case .stepFailed(let query, let msg): return "SQL step error '\(query)': \(msg)"
        }
    }
}
