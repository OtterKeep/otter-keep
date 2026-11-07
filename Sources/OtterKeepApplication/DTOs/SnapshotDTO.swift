import Foundation
import OtterKeepDomain

/// Data Transfer Object for point-in-time backup snapshots across layer boundaries.
public struct SnapshotDTO: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let status: String
    public let totalFiles: Int64
    public let totalBytes: Int64
    public let snapshotPath: String
    public let backupType: String
    public let lockedUntil: Date?

    public var isLocked: Bool {
        guard let lock = lockedUntil else { return false }
        return lock > Date()
    }

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

    /// Initializes DTO from a domain entity.
    public init(from entity: SnapshotRecord) {
        self.id = entity.id
        self.timestamp = entity.timestamp
        self.status = entity.status
        self.totalFiles = entity.totalFiles
        self.totalBytes = entity.totalBytes
        self.snapshotPath = entity.snapshotPath
        self.backupType = entity.backupType
        self.lockedUntil = entity.lockedUntil
    }

    /// Converts DTO back to pure domain entity.
    public func toDomain() -> SnapshotRecord {
        SnapshotRecord(
            id: id,
            timestamp: timestamp,
            status: status,
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            snapshotPath: snapshotPath,
            backupType: backupType,
            lockedUntil: lockedUntil
        )
    }
}

/// Data Transfer Object for indexed files within a snapshot across layer boundaries.
public struct FileCatalogDTO: Sendable, Codable, Equatable, Identifiable {
    public let id: Int64?
    public let snapshotId: String
    public let relativePath: String
    public let fileSize: Int64
    public let modificationTime: Date
    public let inode: UInt64
    public let checksum: String?
    public let sampleHash: String?
    public let isDirectory: Bool
    public let isSymlink: Bool

    public init(
        id: Int64? = nil,
        snapshotId: String,
        relativePath: String,
        fileSize: Int64,
        modificationTime: Date,
        inode: UInt64,
        checksum: String? = nil,
        sampleHash: String? = nil,
        isDirectory: Bool = false,
        isSymlink: Bool = false
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

    /// Initializes DTO from a domain entity.
    public init(from entity: FileCatalogRecord) {
        self.id = entity.id
        self.snapshotId = entity.snapshotId
        self.relativePath = entity.relativePath
        self.fileSize = entity.fileSize
        self.modificationTime = entity.modificationTime
        self.inode = entity.inode
        self.checksum = entity.checksum
        self.sampleHash = entity.sampleHash
        self.isDirectory = entity.isDirectory
        self.isSymlink = entity.isSymlink
    }

    /// Converts DTO back to pure domain entity.
    public func toDomain() -> FileCatalogRecord {
        FileCatalogRecord(
            id: id ?? 0,
            snapshotId: snapshotId,
            relativePath: relativePath,
            fileSize: fileSize,
            modificationTime: modificationTime,
            inode: inode,
            checksum: checksum,
            sampleHash: sampleHash,
            isDirectory: isDirectory,
            isSymlink: isSymlink
        )
    }
}

/// Composite Data Transfer Object conveying a snapshot record and its indexed catalog items.
public struct SnapshotDetailsDTO: Sendable, Codable, Equatable {
    public let snapshot: SnapshotDTO
    public let files: [FileCatalogDTO]

    public init(snapshot: SnapshotDTO, files: [FileCatalogDTO]) {
        self.snapshot = snapshot
        self.files = files
    }

    public init(snapshot: SnapshotRecord, files: [FileCatalogRecord]) {
        self.snapshot = SnapshotDTO(from: snapshot)
        self.files = files.map { FileCatalogDTO(from: $0) }
    }

    /// Converts composite DTO back to domain entities.
    public func toDomain() -> (snapshot: SnapshotRecord, files: [FileCatalogRecord]) {
        (snapshot: snapshot.toDomain(), files: files.map { $0.toDomain() })
    }
}
