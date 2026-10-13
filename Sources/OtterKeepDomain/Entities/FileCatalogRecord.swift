import Foundation

/// Pure domain representation of an indexed file or directory record in a specific snapshot catalog.
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
