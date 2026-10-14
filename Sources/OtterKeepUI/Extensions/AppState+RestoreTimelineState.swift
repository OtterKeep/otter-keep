import SwiftUI
import AppKit
import Photos
import OtterKeepDatabase
import OtterKeepCore

/// Forwarding accessors exposing the restore, timeline and diff state owned by
/// ``RestoreTimelineStore`` on `AppState` so views keep their existing call sites.
extension AppState {
    // MARK: - Snapshot Browsing & File Tree
    /// Identifier of the profile whose snapshot catalog is currently loaded.
    public var loadedProfileId: UUID? { get { restoreTimeline.loadedProfileId } set { restoreTimeline.loadedProfileId = newValue } }
    /// Identifier of the snapshot whose file catalog is currently loaded.
    public var loadedSnapshotId: String? { get { restoreTimeline.loadedSnapshotId } set { restoreTimeline.loadedSnapshotId = newValue } }
    /// Snapshots of the currently selected profile.
    public var snapshots: [SnapshotRecord] { get { restoreTimeline.snapshots } set { restoreTimeline.snapshots = newValue } }
    /// Currently selected snapshot identifier.
    public var selectedSnapshotId: String? { get { restoreTimeline.selectedSnapshotId } set { restoreTimeline.selectedSnapshotId = newValue } }
    /// File catalog records of the loaded snapshot.
    public var snapshotFiles: [FileCatalogRecord] { get { restoreTimeline.snapshotFiles } set { restoreTimeline.snapshotFiles = newValue } }
    /// Tree nodes built from the loaded snapshot file catalog.
    public var snapshotTreeNodes: [FileTreeNode] { get { restoreTimeline.snapshotTreeNodes } set { restoreTimeline.snapshotTreeNodes = newValue } }
    /// Currently selected file tree node.
    public var selectedTreeNode: FileTreeNode? { get { restoreTimeline.selectedTreeNode } set { restoreTimeline.selectedTreeNode = newValue } }
    /// Currently selected file catalog record.
    public var selectedFile: FileCatalogRecord? { get { restoreTimeline.selectedFile } set { restoreTimeline.selectedFile = newValue } }
    /// Differential status for files in the selected snapshot relative to previous snapshot.
    public var snapshotFileDiffStatuses: [String: DiffChangeType] { get { restoreTimeline.snapshotFileDiffStatuses } set { restoreTimeline.snapshotFileDiffStatuses = newValue } }

    // MARK: - File Timeline & Tree Structure
    /// Active browsing mode (snapshot catalog or timeline).
    public var restoreBrowseMode: RestoreBrowseMode { get { restoreTimeline.restoreBrowseMode } set { restoreTimeline.restoreBrowseMode = newValue } }
    /// Search query filtering the timeline paths.
    public var timelineSearchQuery: String { get { restoreTimeline.timelineSearchQuery } set { restoreTimeline.timelineSearchQuery = newValue } }
    /// Distinct relative paths matching the current timeline search.
    public var timelinePaths: [String] { get { restoreTimeline.timelinePaths } set { restoreTimeline.timelinePaths = newValue } }
    /// Tree nodes built from the timeline paths.
    public var timelineTreeNodes: [FileTreeNode] { get { restoreTimeline.timelineTreeNodes } set { restoreTimeline.timelineTreeNodes = newValue } }
    /// Currently selected relative path in the timeline.
    public var selectedTimelinePath: String? { get { restoreTimeline.selectedTimelinePath } set { restoreTimeline.selectedTimelinePath = newValue } }
    /// All known versions of the selected timeline path.
    public var selectedPathVersions: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] {
        get { restoreTimeline.selectedPathVersions }
        set { restoreTimeline.selectedPathVersions = newValue }
    }
    /// Currently selected version of the selected timeline path.
    public var selectedTimelineVersion: (snapshot: SnapshotRecord, file: FileCatalogRecord)? {
        get { restoreTimeline.selectedTimelineVersion }
        set { restoreTimeline.selectedTimelineVersion = newValue }
    }
    /// Version of a file pending a restore operation.
    public var versionToRestore: (snapshot: SnapshotRecord, file: FileCatalogRecord)? {
        get { restoreTimeline.versionToRestore }
        set { restoreTimeline.versionToRestore = newValue }
    }

    // MARK: - Snapshot Diff & What Changed State
    /// Snapshot identifier used as the "new" side of the diff.
    public var selectedDiffTargetSnapshotId: String? {
        get { restoreTimeline.selectedDiffTargetSnapshotId }
        set { restoreTimeline.selectedDiffTargetSnapshotId = newValue }
    }
    /// Snapshot identifier used as the "old" side of the diff.
    public var selectedDiffBaseSnapshotId: String? {
        get { restoreTimeline.selectedDiffBaseSnapshotId }
        set { restoreTimeline.selectedDiffBaseSnapshotId = newValue }
    }
    /// Diff report for the selected snapshot pair.
    public var snapshotDiffReport: SnapshotDiffReport? { get { restoreTimeline.snapshotDiffReport } set { restoreTimeline.snapshotDiffReport = newValue } }
    /// Indicates an ongoing snapshot diff computation.
    public var isLoadingDiff: Bool { get { restoreTimeline.isLoadingDiff } set { restoreTimeline.isLoadingDiff = newValue } }
    /// Active change-type filter of the diff sheet.
    public var diffFilterType: DiffChangeType? { get { restoreTimeline.diffFilterType } set { restoreTimeline.diffFilterType = newValue } }
    /// Free-text filter of the diff sheet.
    public var diffSearchQuery: String { get { restoreTimeline.diffSearchQuery } set { restoreTimeline.diffSearchQuery = newValue } }
    /// Controls presentation of the snapshot diff sheet.
    public var showDiffSheet: Bool { get { restoreTimeline.showDiffSheet } set { restoreTimeline.showDiffSheet = newValue } }

    // MARK: - Side-by-Side Snapshot File Diff (1.5.0)
    /// Controls presentation of the side-by-side comparison modal.
    public var showSideBySideDiffModal: Bool { get { restoreTimeline.showSideBySideDiffModal } set { restoreTimeline.showSideBySideDiffModal = newValue } }
    /// Diff item currently compared side by side.
    public var activeSideBySideDiffItem: SnapshotDiffItem? {
        get { restoreTimeline.activeSideBySideDiffItem }
        set { restoreTimeline.activeSideBySideDiffItem = newValue }
    }
    /// Text comparison result of the active side-by-side diff.
    public var activeSideBySideDiffComparison: FileComparisonResult? {
        get { restoreTimeline.activeSideBySideDiffComparison }
        set { restoreTimeline.activeSideBySideDiffComparison = newValue }
    }
    /// Indicates an ongoing side-by-side comparison computation.
    public var isLoadingSideBySideDiff: Bool { get { restoreTimeline.isLoadingSideBySideDiff } set { restoreTimeline.isLoadingSideBySideDiff = newValue } }

    // MARK: - Direct File Version History & Finder In-Place Restore
    /// Controls presentation of the file version history modal.
    public var showFileVersionHistoryModal: Bool {
        get { restoreTimeline.showFileVersionHistoryModal }
        set { restoreTimeline.showFileVersionHistoryModal = newValue }
    }
    /// On-disk URL of the file whose version history is displayed.
    public var activeVersionHistoryFile: URL? { get { restoreTimeline.activeVersionHistoryFile } set { restoreTimeline.activeVersionHistoryFile = newValue } }
    /// Profile owning the file whose version history is displayed.
    public var activeVersionHistoryProfile: BackupProfile? {
        get { restoreTimeline.activeVersionHistoryProfile }
        set { restoreTimeline.activeVersionHistoryProfile = newValue }
    }
    /// Known versions of the file whose history is displayed.
    public var activeVersionHistoryRecords: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] {
        get { restoreTimeline.activeVersionHistoryRecords }
        set { restoreTimeline.activeVersionHistoryRecords = newValue }
    }
    /// Indicates an ongoing version history lookup.
    public var isLoadingFileVersions: Bool { get { restoreTimeline.isLoadingFileVersions } set { restoreTimeline.isLoadingFileVersions = newValue } }
    /// Version currently selected inside the version history modal.
    public var selectedFileVersionHistoryRecord: (snapshot: SnapshotRecord, file: FileCatalogRecord)? {
        get { restoreTimeline.selectedFileVersionHistoryRecord }
        set { restoreTimeline.selectedFileVersionHistoryRecord = newValue }
    }
    /// Version pending an in-place Finder restore.
    public var versionForInPlaceRestore: (snapshot: SnapshotRecord, file: FileCatalogRecord)? {
        get { restoreTimeline.versionForInPlaceRestore }
        set { restoreTimeline.versionForInPlaceRestore = newValue }
    }
    /// Controls presentation of the in-place restore confirmation.
    public var showConfirmInPlaceRestore: Bool {
        get { restoreTimeline.showConfirmInPlaceRestore }
        set { restoreTimeline.showConfirmInPlaceRestore = newValue }
    }
    /// Collision policy applied to an in-place restore.
    public var inPlaceRestoreCollisionChoice: CollisionResolution {
        get { restoreTimeline.inPlaceRestoreCollisionChoice }
        set { restoreTimeline.inPlaceRestoreCollisionChoice = newValue }
    }

    // MARK: - Volume & CoW Capability Evaluation
    /// Capability evaluation of the selected profile's volumes.
    public var volumeEvaluation: VolumeEvaluationResult? { get { restoreTimeline.volumeEvaluation } set { restoreTimeline.volumeEvaluation = newValue } }

    // MARK: - Quick Look
    /// URL currently previewed in Quick Look.
    public var quickLookURL: URL? { get { restoreTimeline.quickLookURL } set { restoreTimeline.quickLookURL = newValue } }

    // MARK: - Entire-Snapshot Restore
    /// Controls presentation of the single-file restore dialog.
    public var showRestoreDialog: Bool { get { restoreTimeline.showRestoreDialog } set { restoreTimeline.showRestoreDialog = newValue } }
    /// Controls presentation of the entire-snapshot restore dialog.
    public var showRestoreSnapshotDialog: Bool {
        get { restoreTimeline.showRestoreSnapshotDialog }
        set { restoreTimeline.showRestoreSnapshotDialog = newValue }
    }
    /// Snapshot pending a full restore.
    public var snapshotToRestoreEntirely: SnapshotRecord? {
        get { restoreTimeline.snapshotToRestoreEntirely }
        set { restoreTimeline.snapshotToRestoreEntirely = newValue }
    }
    /// Indicates an ongoing entire-snapshot restore.
    public var isSnapshotRestoreInProgress: Bool {
        get { restoreTimeline.isSnapshotRestoreInProgress }
        set { restoreTimeline.isSnapshotRestoreInProgress = newValue }
    }
    /// Live progress of the ongoing entire-snapshot restore.
    public var snapshotRestoreProgress: RestoreProgressState? {
        get { restoreTimeline.snapshotRestoreProgress }
        set { restoreTimeline.snapshotRestoreProgress = newValue }
    }
    /// Collision policy applied while restoring a snapshot.
    public var collisionChoice: CollisionResolution { get { restoreTimeline.collisionChoice } set { restoreTimeline.collisionChoice = newValue } }
}
