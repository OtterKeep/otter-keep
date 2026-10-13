import Foundation
import Observation
import OtterKeepDatabase
import OtterKeepCore

/// Snapshot browsing, file timeline and diff-comparison state for the Restore workspace.
///
/// Owns the loaded snapshot/file-tree selection, the per-path version timeline, the snapshot diff and
/// side-by-side comparison state, direct file version history, volume capability evaluation and the
/// entire-snapshot restore flow. `AppState` exposes this state through forwarding accessors so views
/// keep their existing call sites.
@MainActor
@Observable
public final class RestoreTimelineStore: Sendable {
    // MARK: - Snapshot Browsing & File Tree

    /// Identifier of the profile whose snapshot catalog is currently loaded.
    public var loadedProfileId: UUID? = nil

    /// Identifier of the snapshot whose file catalog is currently loaded.
    public var loadedSnapshotId: String? = nil

    /// Snapshots of the currently selected profile.
    public var snapshots: [SnapshotRecord] = []

    /// Currently selected snapshot identifier.
    public var selectedSnapshotId: String?

    /// File catalog records of the loaded snapshot.
    public var snapshotFiles: [FileCatalogRecord] = []

    /// Tree nodes built from the loaded snapshot file catalog.
    public var snapshotTreeNodes: [FileTreeNode] = []

    /// Currently selected file tree node.
    public var selectedTreeNode: FileTreeNode?

    /// Currently selected file catalog record.
    public var selectedFile: FileCatalogRecord?

    // MARK: - File Timeline & Tree Structure

    /// Active browsing mode (snapshot catalog or timeline).
    public var restoreBrowseMode: RestoreBrowseMode = .snapshot

    /// Search query filtering the timeline paths.
    public var timelineSearchQuery: String = ""

    /// Distinct relative paths matching the current timeline search.
    public var timelinePaths: [String] = []

    /// Tree nodes built from the timeline paths.
    public var timelineTreeNodes: [FileTreeNode] = []

    /// Currently selected relative path in the timeline.
    public var selectedTimelinePath: String?

    /// All known versions of the selected timeline path.
    public var selectedPathVersions: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] = []

    /// Currently selected version of the selected timeline path.
    public var selectedTimelineVersion: (snapshot: SnapshotRecord, file: FileCatalogRecord)?

    /// Version of a file pending a restore operation.
    public var versionToRestore: (snapshot: SnapshotRecord, file: FileCatalogRecord)?

    // MARK: - Snapshot Diff & What Changed State

    /// Snapshot identifier used as the "new" side of the diff.
    public var selectedDiffTargetSnapshotId: String?

    /// Snapshot identifier used as the "old" side of the diff.
    public var selectedDiffBaseSnapshotId: String?

    /// Diff report for the selected snapshot pair.
    public var snapshotDiffReport: SnapshotDiffReport?

    /// Indicates an ongoing snapshot diff computation.
    public var isLoadingDiff: Bool = false

    /// Active change-type filter of the diff sheet.
    public var diffFilterType: DiffChangeType? = nil

    /// Free-text filter of the diff sheet.
    public var diffSearchQuery: String = ""

    /// Controls presentation of the snapshot diff sheet.
    public var showDiffSheet: Bool = false

    // MARK: - Side-by-Side Snapshot File Diff (1.5.0)

    /// Controls presentation of the side-by-side comparison modal.
    public var showSideBySideDiffModal: Bool = false

    /// Diff item currently compared side by side.
    public var activeSideBySideDiffItem: SnapshotDiffItem? = nil

    /// Text comparison result of the active side-by-side diff.
    public var activeSideBySideDiffComparison: FileComparisonResult? = nil

    /// Indicates an ongoing side-by-side comparison computation.
    public var isLoadingSideBySideDiff: Bool = false

    // MARK: - Direct File Version History & Finder In-Place Restore

    /// Controls presentation of the file version history modal.
    public var showFileVersionHistoryModal: Bool = false

    /// On-disk URL of the file whose version history is displayed.
    public var activeVersionHistoryFile: URL? = nil

    /// Profile owning the file whose version history is displayed.
    public var activeVersionHistoryProfile: BackupProfile? = nil

    /// Known versions of the file whose history is displayed.
    public var activeVersionHistoryRecords: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] = []

    /// Indicates an ongoing version history lookup.
    public var isLoadingFileVersions: Bool = false

    /// Version currently selected inside the version history modal.
    public var selectedFileVersionHistoryRecord: (snapshot: SnapshotRecord, file: FileCatalogRecord)? = nil

    /// Version pending an in-place Finder restore.
    public var versionForInPlaceRestore: (snapshot: SnapshotRecord, file: FileCatalogRecord)? = nil

    /// Controls presentation of the in-place restore confirmation.
    public var showConfirmInPlaceRestore: Bool = false

    /// Collision policy applied to an in-place restore.
    public var inPlaceRestoreCollisionChoice: CollisionResolution = .overwrite

    // MARK: - Volume & CoW Capability Evaluation

    /// Capability evaluation of the selected profile's volumes.
    public var volumeEvaluation: VolumeEvaluationResult?

    // MARK: - Quick Look

    /// URL currently previewed in Quick Look.
    public var quickLookURL: URL?

    // MARK: - Entire-Snapshot Restore

    /// Controls presentation of the single-file restore dialog.
    public var showRestoreDialog: Bool = false

    /// Controls presentation of the entire-snapshot restore dialog.
    public var showRestoreSnapshotDialog: Bool = false

    /// Snapshot pending a full restore.
    public var snapshotToRestoreEntirely: SnapshotRecord? = nil

    /// Indicates an ongoing entire-snapshot restore.
    public var isSnapshotRestoreInProgress: Bool = false

    /// Live progress of the ongoing entire-snapshot restore.
    public var snapshotRestoreProgress: RestoreProgressState? = nil

    /// Collision policy applied while restoring a snapshot.
    public var collisionChoice: CollisionResolution = .keepBoth

    /// Initializes an empty restore/timeline store.
    public init() {}

    /// Resolves the on-disk URL of a specific file version inside its snapshot.
    public func url(forVersionHistoryRecord record: (snapshot: SnapshotRecord, file: FileCatalogRecord)) -> URL? {
        guard let profile = activeVersionHistoryProfile else { return nil }
        return profile.destinationURL
            .appendingPathComponent(record.snapshot.snapshotPath)
            .appendingPathComponent("root")
            .appendingPathComponent(record.file.relativePath)
    }
}
