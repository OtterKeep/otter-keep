import Foundation

/// Classification of a line change in a differential comparison.
public enum DiffLineType: String, Sendable, Codable, Equatable {
    /// Line is identical in both versions.
    case unchanged
    /// Line was added in the target version.
    case added
    /// Line was removed from the base version.
    case deleted
    /// Line was modified between versions.
    case modified
}

/// Aligned row in a side-by-side text comparison.
public struct SideBySideDiffLine: Sendable, Identifiable, Equatable {
    public let id: Int
    /// 1-based line number in base/left file (nil if line was added on the right).
    public let leftLineNumber: Int?
    /// Text content in base/left file.
    public let leftText: String?
    /// 1-based line number in target/right file (nil if line was deleted from the left).
    public let rightLineNumber: Int?
    /// Text content in target/right file.
    public let rightText: String?
    /// Classification of the diff line.
    public let type: DiffLineType

    public init(
        id: Int,
        leftLineNumber: Int?,
        leftText: String?,
        rightLineNumber: Int?,
        rightText: String?,
        type: DiffLineType
    ) {
        self.id = id
        self.leftLineNumber = leftLineNumber
        self.leftText = leftText
        self.rightLineNumber = rightLineNumber
        self.rightText = rightText
        self.type = type
    }
}

/// Comprehensive side-by-side and unified comparison outcome for a specific file.
public struct FileComparisonResult: Sendable, Equatable {
    /// Relative path of the compared file.
    public let relativePath: String
    /// True if either version is detected as binary (non-UTF8 or contains null bytes).
    public let isBinary: Bool
    /// Logical size in bytes of the base/left file.
    public let leftSize: Int64
    /// Logical size in bytes of the target/right file.
    public let rightSize: Int64
    /// SHA-256 digest of the base/left file.
    public let leftSHA256: String?
    /// SHA-256 digest of the target/right file.
    public let rightSHA256: String?
    /// Last modification timestamp of the base/left file.
    public let leftMtime: Date?
    /// Last modification timestamp of the target/right file.
    public let rightMtime: Date?
    /// Array of aligned side-by-side diff rows.
    public let rows: [SideBySideDiffLine]
    /// Total count of added lines.
    public let addedLinesCount: Int
    /// Total count of deleted lines.
    public let deletedLinesCount: Int
    /// Total count of modified lines.
    public let modifiedLinesCount: Int

    public init(
        relativePath: String,
        isBinary: Bool,
        leftSize: Int64,
        rightSize: Int64,
        leftSHA256: String? = nil,
        rightSHA256: String? = nil,
        leftMtime: Date? = nil,
        rightMtime: Date? = nil,
        rows: [SideBySideDiffLine],
        addedLinesCount: Int,
        deletedLinesCount: Int,
        modifiedLinesCount: Int
    ) {
        self.relativePath = relativePath
        self.isBinary = isBinary
        self.leftSize = leftSize
        self.rightSize = rightSize
        self.leftSHA256 = leftSHA256
        self.rightSHA256 = rightSHA256
        self.leftMtime = leftMtime
        self.rightMtime = rightMtime
        self.rows = rows
        self.addedLinesCount = addedLinesCount
        self.deletedLinesCount = deletedLinesCount
        self.modifiedLinesCount = modifiedLinesCount
    }
}
