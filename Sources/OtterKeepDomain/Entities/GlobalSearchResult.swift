import Foundation

/// Pure domain representation of a cross-snapshot global search hit in the catalog.
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
