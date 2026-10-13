import Foundation
import Observation
import Photos
import OtterKeepDatabase
import OtterKeepCore

/// Apple Photos backup and browsing state.
///
/// Owns the Photos backup configuration, live Photos backup telemetry, authorization status, the
/// Photos snapshot catalog and the asset browsing selection. `AppState` exposes this state through
/// forwarding accessors so views keep their existing call sites.
@MainActor
@Observable
public final class PhotosStore: Sendable {
    /// Persisted Photos backup configuration.
    public var photosConfig: PhotosBackupConfiguration

    /// Indicates an ongoing Photos backup.
    public var isPhotosBackupRunning: Bool = false

    /// Live progress of the ongoing Photos backup.
    public var photosProgressState: PhotosBackupProgressState = PhotosBackupProgressState()

    /// Summary of the last completed Photos backup session.
    public var lastPhotosSessionSummary: PhotosSessionSummary?

    /// Current Photos library authorization status.
    public var photosAuthorizationStatus: PHAuthorizationStatus = .notDetermined

    /// Identifier of the Photos snapshot whose assets are loaded.
    public var loadedPhotosSnapshotId: String? = nil

    /// Photos snapshots of the selected profile.
    public var photosSnapshots: [SnapshotRecord] = []

    /// Currently selected Photos snapshot identifier.
    public var selectedPhotosSnapshotId: String?

    /// Assets of the loaded Photos snapshot.
    public var photosAssets: [PhotosAssetRecord] = []

    /// Currently selected Photos asset.
    public var selectedPhotosAsset: PhotosAssetRecord?

    /// Total number of assets in the system Photos library.
    public var photosLibraryTotalCount: Int = 0

    /// Indicates an ongoing Photos library scan.
    public var isScanningPhotosLibrary: Bool = false

    /// Initializes the store with a persisted Photos backup configuration.
    public init(config: PhotosBackupConfiguration) {
        self.photosConfig = config
    }

    /// Persists the current Photos backup configuration.
    public func saveConfiguration() {
        try? PhotosProfileStore.shared.saveConfiguration(photosConfig)
    }
}
