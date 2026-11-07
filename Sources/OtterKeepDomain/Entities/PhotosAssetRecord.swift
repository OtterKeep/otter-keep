import Foundation

/// Pure domain representation of an indexed Photos item record in a Photos backup snapshot catalog.
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
