import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension AppState {
    // MARK: - Photos Backup Operations

    @MainActor
    public func checkPhotosAuthorization() {
        self.photosAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    @MainActor
    public func requestPhotosAuthorization() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            Task { @MainActor in
                self.photosAuthorizationStatus = status
                if status == .authorized || status == .limited {
                    self.refreshPhotosLibraryStats()
                }
            }
        }
    }

    @MainActor
    public func refreshPhotosLibraryStats() {
        guard photosAuthorizationStatus == .authorized || photosAuthorizationStatus == .limited else { return }
        self.isScanningPhotosLibrary = true
        Task.detached {
            let fetchOptions = PHFetchOptions()
            fetchOptions.includeHiddenAssets = false
            let count = PHAsset.fetchAssets(with: fetchOptions).count
            Task { @MainActor in
                self.photosLibraryTotalCount = count
                self.isScanningPhotosLibrary = false
            }
        }
    }

    @MainActor
    public func savePhotosConfig() {
        try? PhotosProfileStore.shared.saveConfiguration(self.photosConfig)
    }

    @MainActor
    public func startPhotosBackup() {
        guard !isPhotosBackupRunning else { return }
        self.isPhotosBackupRunning = true
        self.photosProgressState = PhotosBackupProgressState()
        self.photosProgressState.isRunning = true

        savePhotosConfig()

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let summary = try await self.photosCoordinator.executeBackup(configuration: self.photosConfig) { [weak self] progress in
                    Task { @MainActor in
                        self?.photosProgressState = progress
                    }
                }

                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isPhotosBackupRunning = false
                    self.lastPhotosSessionSummary = summary
                    self.photosConfig.schedule.lastRunDate = Date()
                    self.savePhotosConfig()
                    NotificationDeliveryService.shared.notifyPhotosBackupCompleted(
                        copiedCount: summary.newDownloadedCount + summary.reflinkClonedCount,
                        durationSec: summary.durationSeconds
                    )
                    LogManager.shared.log("Photos backup finished successfully: \(summary.newDownloadedCount) downloaded, \(summary.reflinkClonedCount) cloned", level: .info, category: "Photos")
                    self.refreshLogs()
                    self.loadPhotosSnapshots()
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isPhotosBackupRunning = false
                    self.photosProgressState.isRunning = false
                    NotificationDeliveryService.shared.notifyPhotosBackupFailed(
                        errorMessage: error.localizedDescription
                    )
                    LogManager.shared.log("Photos backup error: \(error.localizedDescription)", level: .error, category: "Photos")
                    self.refreshLogs()
                    self.showError("Photos backup error: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    public func cancelPhotosBackup() {
        Task {
            await photosCoordinator.cancel()
            Task { @MainActor in
                self.isPhotosBackupRunning = false
                self.photosProgressState.isRunning = false
            }
        }
    }

    func photosDatabasePath(for destURL: URL) -> String? {
        let unifiedPath = destURL.appendingPathComponent(".otterkeep/manifest.sqlite").path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: unifiedPath) {
            return unifiedPath
        }
        return nil
    }

    @MainActor
    public func loadPhotosSnapshots(force: Bool = false) {
        let destURL = photosConfig.destinationURL
        guard let dbPath = photosDatabasePath(for: destURL) else {
            self.photosSnapshots = []
            self.loadedPhotosSnapshotId = nil
            return
        }

        Task {
            do {
                try await database.open(at: dbPath)
                let snaps = try await database.fetchSnapshots()
                Task { @MainActor in
                    let snapsChanged = self.photosSnapshots.map(\.id) != snaps.map(\.id)
                    if snapsChanged || self.photosSnapshots.isEmpty {
                        self.photosSnapshots = snaps
                    }
                    if self.selectedPhotosSnapshotId == nil || !snaps.contains(where: { $0.id == self.selectedPhotosSnapshotId }) {
                        self.selectedPhotosSnapshotId = snaps.first?.id
                    }
                    if let selId = self.selectedPhotosSnapshotId {
                        if force || snapsChanged || self.photosAssets.isEmpty || self.loadedPhotosSnapshotId != selId {
                            self.loadPhotosAssets(for: selId, force: force)
                        }
                    }
                }
            } catch {
                Task { @MainActor in
                    self.photosSnapshots = []
                    self.loadedPhotosSnapshotId = nil
                }
            }
        }
    }

    @MainActor
    public func selectPhotosSnapshot(id: String) {
        self.selectedPhotosSnapshotId = id
        loadPhotosAssets(for: id, force: true)
    }

    @MainActor
    public func loadPhotosAssets(for snapshotId: String, force: Bool = false) {
        if !force && self.loadedPhotosSnapshotId == snapshotId && !self.photosAssets.isEmpty {
            return
        }
        let destURL = photosConfig.destinationURL
        guard let dbPath = photosDatabasePath(for: destURL) else { return }

        Task {
            do {
                try await database.open(at: dbPath)
                let assets = try await database.fetchPhotosAssetRecords(for: snapshotId)
                Task { @MainActor in
                    self.loadedPhotosSnapshotId = snapshotId
                    self.photosAssets = assets
                    let prevLocalId = self.selectedPhotosAsset?.localIdentifier
                    if let prevLocalId = prevLocalId,
                       let matching = assets.first(where: { $0.localIdentifier == prevLocalId }) {
                        self.selectedPhotosAsset = matching
                    } else if self.selectedPhotosAsset == nil || !assets.contains(where: { $0.id == self.selectedPhotosAsset?.id }) {
                        self.selectedPhotosAsset = assets.first
                    }
                }
            } catch {
                Task { @MainActor in
                    self.photosAssets = []
                    self.loadedPhotosSnapshotId = nil
                }
            }
        }
    }

    @MainActor
    public func revealPhotosAssetInFinder(_ asset: PhotosAssetRecord) {
        let fileURL = photosConfig.destinationURL.appendingPathComponent(asset.relativePath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([photosConfig.destinationURL])
        }
    }


}
