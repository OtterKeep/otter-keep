import SwiftUI
import AppKit
import Photos
import OtterKeepDatabase
import OtterKeepCore

/// Forwarding accessors exposing the Apple Photos backup and browsing state owned by
/// ``PhotosStore`` on `AppState` so views keep their existing call sites.
extension AppState {
    /// Persisted Photos backup configuration.
    public var photosConfig: PhotosBackupConfiguration { get { photosStore.photosConfig } set { photosStore.photosConfig = newValue } }
    /// Indicates an ongoing Photos backup.
    public var isPhotosBackupRunning: Bool { get { photosStore.isPhotosBackupRunning } set { photosStore.isPhotosBackupRunning = newValue } }
    /// Live progress of the ongoing Photos backup.
    public var photosProgressState: PhotosBackupProgressState { get { photosStore.photosProgressState } set { photosStore.photosProgressState = newValue } }
    /// Summary of the last completed Photos backup session.
    public var lastPhotosSessionSummary: PhotosSessionSummary? {
        get { photosStore.lastPhotosSessionSummary }
        set { photosStore.lastPhotosSessionSummary = newValue }
    }
    /// Current Photos library authorization status.
    public var photosAuthorizationStatus: PHAuthorizationStatus {
        get { photosStore.photosAuthorizationStatus }
        set { photosStore.photosAuthorizationStatus = newValue }
    }
    /// Identifier of the Photos snapshot whose assets are loaded.
    public var loadedPhotosSnapshotId: String? { get { photosStore.loadedPhotosSnapshotId } set { photosStore.loadedPhotosSnapshotId = newValue } }
    /// Photos snapshots of the selected profile.
    public var photosSnapshots: [SnapshotRecord] { get { photosStore.photosSnapshots } set { photosStore.photosSnapshots = newValue } }
    /// Currently selected Photos snapshot identifier.
    public var selectedPhotosSnapshotId: String? { get { photosStore.selectedPhotosSnapshotId } set { photosStore.selectedPhotosSnapshotId = newValue } }
    /// Assets of the loaded Photos snapshot.
    public var photosAssets: [PhotosAssetRecord] { get { photosStore.photosAssets } set { photosStore.photosAssets = newValue } }
    /// Currently selected Photos asset.
    public var selectedPhotosAsset: PhotosAssetRecord? { get { photosStore.selectedPhotosAsset } set { photosStore.selectedPhotosAsset = newValue } }
    /// Total number of assets in the system Photos library.
    public var photosLibraryTotalCount: Int { get { photosStore.photosLibraryTotalCount } set { photosStore.photosLibraryTotalCount = newValue } }
    /// Indicates an ongoing Photos library scan.
    public var isScanningPhotosLibrary: Bool { get { photosStore.isScanningPhotosLibrary } set { photosStore.isScanningPhotosLibrary = newValue } }
}
