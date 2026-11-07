import Foundation

/// Type of change detected between two snapshots for a specific file path.
public enum DiffChangeType: String, Codable, Sendable, CaseIterable {
    /// File was newly created in the target snapshot.
    case added = "added"
    /// File was modified (content hash, modification time, or size changed).
    case modified = "modified"
    /// File was deleted in the target snapshot.
    case deleted = "deleted"
    /// File is identical in both snapshots.
    case unchanged = "unchanged"

    public var isDifference: Bool {
        self != .unchanged
    }
}

/// Represents a single file or directory difference between two snapshots.
public struct SnapshotDiffItem: Sendable, Identifiable, Equatable {
    public var id: String { relativePath }
    /// Relative path within the snapshot root.
    public let relativePath: String
    /// Classification of the change.
    public let changeType: DiffChangeType
    /// Catalog record in the base snapshot (nil if newly added).
    public let oldRecord: FileCatalogRecord?
    /// Catalog record in the target snapshot (nil if deleted).
    public let newRecord: FileCatalogRecord?
    /// Net size delta in bytes (positive for growth/addition, negative for shrinkage/deletion).
    public let sizeDelta: Int64

    public init(
        relativePath: String,
        changeType: DiffChangeType,
        oldRecord: FileCatalogRecord?,
        newRecord: FileCatalogRecord?,
        sizeDelta: Int64
    ) {
        self.relativePath = relativePath
        self.changeType = changeType
        self.oldRecord = oldRecord
        self.newRecord = newRecord
        self.sizeDelta = sizeDelta
    }

    /// Primary display file name (last path component).
    public var fileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    /// Parent directory path (empty if at snapshot root).
    public var parentDirectory: String {
        let dir = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
        return (dir == "/" || dir == ".") ? "" : dir
    }

    /// Whether this item is a directory.
    public var isDirectory: Bool {
        newRecord?.isDirectory ?? oldRecord?.isDirectory ?? false
    }
}

/// Consolidated comparison report between two snapshots.
public struct SnapshotDiffReport: Sendable, Equatable {
    /// Base snapshot identifier (nil if comparing against an empty state / initial backup).
    public let baseSnapshotId: String?
    /// Target snapshot identifier.
    public let targetSnapshotId: String
    /// Base snapshot creation timestamp (nil if initial).
    public let baseTimestamp: Date?
    /// Target snapshot creation timestamp.
    public let targetTimestamp: Date
    /// List of all changed items (added, modified, deleted).
    public let items: [SnapshotDiffItem]

    /// Total count of newly added files and directories.
    public let addedCount: Int
    /// Total count of modified files.
    public let modifiedCount: Int
    /// Total count of deleted files and directories.
    public let deletedCount: Int

    /// Logical bytes added by new files.
    public let addedBytes: Int64
    /// Logical net bytes changed by modified files.
    public let modifiedBytes: Int64
    /// Logical bytes freed by deleted files.
    public let deletedBytes: Int64
    /// Overall net size change in bytes.
    public let netBytesDelta: Int64

    public init(
        baseSnapshotId: String?,
        targetSnapshotId: String,
        baseTimestamp: Date?,
        targetTimestamp: Date,
        items: [SnapshotDiffItem]
    ) {
        self.baseSnapshotId = baseSnapshotId
        self.targetSnapshotId = targetSnapshotId
        self.baseTimestamp = baseTimestamp
        self.targetTimestamp = targetTimestamp
        self.items = items

        var addCount = 0
        var modCount = 0
        var delCount = 0
        var addBytes: Int64 = 0
        var modBytes: Int64 = 0
        var delBytes: Int64 = 0
        var totalDelta: Int64 = 0

        for item in items {
            totalDelta += item.sizeDelta
            switch item.changeType {
            case .added:
                addCount += 1
                addBytes += max(0, item.sizeDelta)
            case .modified:
                modCount += 1
                modBytes += item.sizeDelta
            case .deleted:
                delCount += 1
                delBytes += abs(item.sizeDelta)
            case .unchanged:
                break
            }
        }

        self.addedCount = addCount
        self.modifiedCount = modCount
        self.deletedCount = delCount
        self.addedBytes = addBytes
        self.modifiedBytes = modBytes
        self.deletedBytes = delBytes
        self.netBytesDelta = totalDelta
    }

    /// Returns true if no changes exist between the two snapshots.
    public var isEmpty: Bool {
        items.isEmpty
    }

    /// Convenience accessors for categorized differences.
    public var addedFiles: [SnapshotDiffItem] {
        items.filter { $0.changeType == .added }
    }

    public var modifiedFiles: [SnapshotDiffItem] {
        items.filter { $0.changeType == .modified }
    }

    public var deletedFiles: [SnapshotDiffItem] {
        items.filter { $0.changeType == .deleted }
    }
}
