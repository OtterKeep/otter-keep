import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension AppState {
    // MARK: - Data Integrity Scrubber Operations (1.5.0)

    @MainActor
    public func performManualScrub(profile: BackupProfile? = nil) {
        guard !isDataScrubInProgress else { return }

        let targetProfile = profile ?? selectedProfile
        guard let prof = targetProfile else { return }

        isDataScrubInProgress = true
        scrubProgress = ScrubRunProgress()
        LogManager.shared.log("Starting manual data integrity scrub for profile '\(prof.name)'", level: .info, category: "Integrity")
        refreshLogs()

        Task.detached(priority: .background) {
            let scrubber = DataScrubberEngine()
            do {
                let audit = try await scrubber.performScrub(
                    backupRootURL: prof.destinationURL,
                    limitSnapshots: nil,
                    throttleSleepMs: 0
                ) { progress in
                    Task { @MainActor in
                        self.scrubProgress = progress
                    }
                }

                await MainActor.run {
                    self.isDataScrubInProgress = false
                    self.scrubProgress = nil
                    self.refreshLogs()

                    if audit.corruptedFilesCount == 0 {
                        self.activeFeedback = OperationFeedback(
                            type: .success,
                            title: L10n.t(.scrubSuccessTitle),
                            message: L10n.format(.scrubSuccessMessage, prof.name, Int64(audit.checkedSnapshotsCount), Int64(audit.checkedFilesCount)),
                            profileName: prof.name
                        )
                    } else {
                        self.activeFeedback = OperationFeedback(
                            type: .failure,
                            title: L10n.t(.scrubCorruptedTitle),
                            message: L10n.format(.scrubCorruptedMessage, prof.name, Int64(audit.corruptedFilesCount)),
                            detailedReason: audit.detailsJson,
                            profileName: prof.name
                        )
                    }
                    self.showFeedbackModal = true
                }
            } catch {
                await MainActor.run {
                    self.isDataScrubInProgress = false
                    self.scrubProgress = nil
                    self.refreshLogs()
                    self.activeFeedback = OperationFeedback(
                        type: .failure,
                        title: L10n.t(.scrubberCorruptedAlertTitle),
                        message: error.localizedDescription,
                        detailedReason: error.localizedDescription,
                        profileName: prof.name
                    )
                    self.showFeedbackModal = true
                }
            }
        }
    }

    // MARK: - Storage Forecast Operations

    @MainActor
    public func refreshStorageForecast() {
        guard let profile = selectedProfile else {
            self.storageForecastReport = nil
            return
        }
        self.isLoadingForecast = true
        Task {
            do {
                let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
                try await self.database.open(at: dbPath)
                let forecast = try await StorageForecastEngine.shared.evaluateForecast(
                    profile: profile,
                    database: self.database
                )
                Task { @MainActor in
                    self.storageForecastReport = forecast
                    self.isLoadingForecast = false
                }
            } catch {
                Task { @MainActor in
                    self.storageForecastReport = nil
                    self.isLoadingForecast = false
                }
            }
        }
    }

    // MARK: - Webhook Testing

    @MainActor
    public func testWebhook(config: WebhookConfiguration) {
        self.webhookTestingStatus = (true, nil, false)
        Task {
            do {
                _ = try await WebhookDispatcher.shared.sendTestWebhook(config: config)
                Task { @MainActor in
                    self.webhookTestingStatus = (false, L10n.t(.webhookTestSuccess), true)
                }
            } catch {
                Task { @MainActor in
                    self.webhookTestingStatus = (false, L10n.format(.webhookTestFailedFormat, error.localizedDescription), false)
                }
            }
        }
    }

    // MARK: - Restore Operations


    @MainActor
    public func restoreVersion(
        snapshot: SnapshotRecord,
        file: FileCatalogRecord,
        to targetDirectory: URL,
        collision: CollisionResolution = .keepBoth
    ) {
        guard let profile = selectedProfile else { return }

        Task {
            do {
                let dest = try await restoreEngine.restore(
                    snapshotPath: snapshot.snapshotPath,
                    backupRootURL: profile.destinationURL,
                    relativePath: file.relativePath,
                    targetDirectoryURL: targetDirectory,
                    collisionResolution: collision
                )
                Task { @MainActor in
                    LogManager.shared.log("File restored successfully: '\(dest.path)' from snapshot '\(snapshot.id)' (Collision mode: \(collision))", level: .info, category: "Restore")
                    self.refreshLogs()
                    NotificationDeliveryService.shared.notifyRestoreCompleted(fileName: dest.lastPathComponent, profileName: profile.name)
                    self.showSuccess(L10n.format(.restoreSuccessMessage, dest.path))
                }
            } catch {
                Task { @MainActor in
                    LogManager.shared.log("Restore failed for target '\(targetDirectory.path)' [File: \(file.relativePath)]: \(error.localizedDescription)", level: .error, category: "Restore")
                    self.refreshLogs()
                    NotificationDeliveryService.shared.notifyRestoreFailed(fileName: file.relativePath, errorMessage: error.localizedDescription)
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    /// Restores the entire contents of a snapshot to a target directory.
    @MainActor
    public func restoreEntireSnapshot(
        snapshot: SnapshotRecord,
        to targetDirectory: URL,
        collision: CollisionResolution = .keepBoth
    ) {
        guard let profile = selectedProfile else { return }

        self.isSnapshotRestoreInProgress = true
        self.snapshotRestoreProgress = RestoreProgressState(
            phase: .preparing,
            totalFiles: Int(snapshot.totalFiles),
            processedFiles: 0,
            totalBytes: snapshot.totalBytes,
            processedBytes: 0,
            currentItem: ""
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await restoreEngine.restoreSnapshot(
                    snapshotPath: snapshot.snapshotPath,
                    backupRootURL: profile.destinationURL,
                    targetDirectoryURL: targetDirectory,
                    collisionResolution: collision,
                    progress: { [weak self] progressState in
                        Task { @MainActor in
                            self?.snapshotRestoreProgress = progressState
                        }
                    }
                )

                Task { @MainActor in
                    self.isSnapshotRestoreInProgress = false
                    self.snapshotRestoreProgress = nil
                    LogManager.shared.log("Entire snapshot '\(snapshot.id)' restored successfully to '\(targetDirectory.path)' (\(summary.restoredFiles) files, \(summary.restoredBytes) bytes, \(String(format: "%.2f", summary.durationSeconds))s)", level: .info, category: "Restore")
                    self.refreshLogs()
                    NotificationDeliveryService.shared.notifyRestoreCompleted(fileName: snapshot.snapshotPath, profileName: profile.name)

                    // Trigger Operation Feedback Modal with Ottie mascot
                    self.activeFeedback = OperationFeedback(
                        type: .success,
                        title: L10n.t(.feedbackRestoreSuccessTitle),
                        message: L10n.format(.feedbackRestoreSuccessMessage, snapshot.snapshotPath, Int64(summary.restoredFiles)),
                        profileName: profile.name,
                        restoreSummary: summary
                    )
                    self.showFeedbackModal = true
                }
            } catch {
                Task { @MainActor in
                    self.isSnapshotRestoreInProgress = false
                    self.snapshotRestoreProgress = nil
                    LogManager.shared.log("Entire snapshot restore failed for '\(snapshot.id)': \(error.localizedDescription)", level: .error, category: "Restore")
                    self.refreshLogs()
                    NotificationDeliveryService.shared.notifyRestoreFailed(fileName: snapshot.snapshotPath, errorMessage: error.localizedDescription)

                    // Trigger Operation Feedback Modal with Ottie reassurance
                    self.activeFeedback = OperationFeedback(
                        type: .failure,
                        title: L10n.t(.feedbackRestoreFailedTitle),
                        message: L10n.format(.feedbackRestoreFailedMessage, error.localizedDescription),
                        detailedReason: error.localizedDescription,
                        profileName: profile.name
                    )
                    self.showFeedbackModal = true
                }
            }
        }
    }

    // MARK: - Direct File Version History & Finder In-Place Restore

    @MainActor
    public func openVersionHistory(for fileURL: URL) {
        let stdURL = fileURL.standardizedFileURL
        let fullPath = stdURL.path(percentEncoded: false)

        // Prevent duplicate presentation if modal is already open for this exact file
        if showFileVersionHistoryModal && activeVersionHistoryFile == stdURL {
            return
        }

        // Find which profile contains this file within its sourceURL (checking both active and persistent profiles)
        guard let matchingProfile = profiles.first(where: { $0.containsPath(fullPath) }) ?? ProfileStore.shared.loadProfiles().first(where: { $0.containsPath(fullPath) }) else {
            LogManager.shared.log("Requested version history for file not covered by any profile: '\(fullPath)'", level: .warning, category: "FinderSync")
            refreshLogs()
            showError(L10n.t(.fileNotUnderAnyProfile))
            return
        }

        guard let relPath = matchingProfile.relativePath(for: fullPath), !relPath.isEmpty else {
            LogManager.shared.log("Selected path is the root source directory: '\(fullPath)'", level: .info, category: "FinderSync")
            return
        }

        self.activeVersionHistoryFile = stdURL
        self.activeVersionHistoryProfile = matchingProfile
        self.isLoadingFileVersions = true
        self.activeVersionHistoryRecords = []
        self.selectedFileVersionHistoryRecord = nil
        self.showFileVersionHistoryModal = true

        let dbPath = matchingProfile.destinationURL.appendingPathComponent(".otterkeep").appendingPathComponent("manifest.sqlite").path(percentEncoded: false)

        Task {
            do {
                try await database.open(at: dbPath)
                let versions = try await database.listVersions(ofRelativePath: relPath)
                // Race condition safeguard: ensure active file hasn't changed while awaiting database
                guard self.activeVersionHistoryFile == stdURL else { return }
                self.activeVersionHistoryRecords = versions
                self.selectedFileVersionHistoryRecord = versions.first
                self.isLoadingFileVersions = false
                LogManager.shared.log("Loaded \(versions.count) historical versions for '\(relPath)' from profile '\(matchingProfile.name)'", level: .info, category: "FinderSync")
                self.refreshLogs()
            } catch {
                guard self.activeVersionHistoryFile == stdURL else { return }
                self.isLoadingFileVersions = false
                self.activeVersionHistoryRecords = []
                self.selectedFileVersionHistoryRecord = nil
                LogManager.shared.log("Failed to load versions for '\(relPath)': \(error.localizedDescription)", level: .error, category: "FinderSync")
                self.refreshLogs()
            }
        }
    }

    @MainActor
    public func restoreFileInPlace(
        version: (snapshot: SnapshotRecord, file: FileCatalogRecord),
        collision: CollisionResolution = .overwrite
    ) {
        guard let targetURL = activeVersionHistoryFile,
              let profile = activeVersionHistoryProfile else { return }

        Task {
            do {
                let finalURL = try await restoreEngine.restoreToFile(
                    snapshotPath: version.snapshot.snapshotPath,
                    backupRootURL: profile.destinationURL,
                    relativePath: version.file.relativePath,
                    destinationFileURL: targetURL,
                    collisionResolution: collision
                )

                let finalPath = finalURL.path(percentEncoded: false)
                LogManager.shared.log("In-place file restoration completed: '\(finalPath)' from snapshot '\(version.snapshot.id)' (Collision: \(collision))", level: .info, category: "Restore")
                NotificationDeliveryService.shared.notifyRestoreCompleted(
                    fileName: targetURL.lastPathComponent,
                    profileName: profile.name
                )
                self.refreshLogs()
                self.showFileVersionHistoryModal = false
                self.showSuccess(L10n.format(.restoreSuccessMessage, finalPath))
            } catch {
                let targetPath = targetURL.path(percentEncoded: false)
                LogManager.shared.log("In-place file restoration failed for '\(targetPath)': \(error.localizedDescription)", level: .error, category: "Restore")
                NotificationDeliveryService.shared.notifyRestoreFailed(
                    fileName: targetURL.lastPathComponent,
                    errorMessage: error.localizedDescription
                )
                self.refreshLogs()
                self.showError(error.localizedDescription)
            }
        }
    }

    @MainActor
    public func urlForVersionHistoryRecord(_ record: (snapshot: SnapshotRecord, file: FileCatalogRecord)) -> URL? {
        guard let profile = activeVersionHistoryProfile else { return nil }
        return profile.destinationURL
            .appendingPathComponent(record.snapshot.snapshotPath)
            .appendingPathComponent("root")
            .appendingPathComponent(record.file.relativePath)
    }

    @MainActor
    public func toggleQuickLook() {
        guard let url = currentSelectedFileURL() else {
            quickLookURL = nil
            QuickLookCoordinator.shared.closeQuickLook()
            return
        }
        self.quickLookURL = url
        QuickLookCoordinator.shared.toggleQuickLook(for: url)
    }

    @MainActor
    public func updateQuickLookForCurrentSelection() {
        let url = currentSelectedFileURL()
        self.quickLookURL = url
        if QuickLookCoordinator.shared.isVisible {
            QuickLookCoordinator.shared.updateSelection(url: url)
        }
    }

    @MainActor
    public func loadTimeline(for path: String) {
        loadTimelineVersions(for: path)
    }

    @MainActor
    public func currentSelectedFileURL() -> URL? {
        guard let profile = selectedProfile else { return nil }
        let candidateURL: URL?
        if restoreBrowseMode == .snapshot {
            guard let snapId = selectedSnapshotId,
                  let snap = snapshots.first(where: { $0.id == snapId }),
                  let file = selectedFile else { return nil }
            candidateURL = profile.destinationURL
                .appendingPathComponent(snap.snapshotPath)
                .appendingPathComponent("root")
                .appendingPathComponent(file.relativePath)
        } else {
            guard let result = selectedGlobalSearchResult else { return nil }
            candidateURL = profile.destinationURL
                .appendingPathComponent(result.snapshotPath)
                .appendingPathComponent("root")
                .appendingPathComponent(result.fileRecord.relativePath)
        }

        guard let url = candidateURL else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) {
            return url
        }
        return url
    }

    // MARK: - Maintenance & Housekeeping

    @MainActor
    public func pruneOldSnapshots(maxKeep: Int) {
        guard let profile = selectedProfile else { return }

        Task {
            do {
                let policy = PruningPolicy(isAutoPruningEnabled: profile.pruningPolicy.isAutoPruningEnabled, maxSnapshotsToKeep: maxKeep, keepDailyDays: 30)
                let deletedIds = try await retentionManager.applyRetentionPolicy(destinationURL: profile.destinationURL, policy: policy)

                Task { @MainActor in
                    LogManager.shared.log("Retention pruning completed for profile '\(profile.name)': \(deletedIds.count) snapshots pruned. Pruned IDs: [\(deletedIds.joined(separator: ", "))]", level: .info, category: "Retention")
                    self.refreshLogs()
                    self.loadSnapshots()
                    self.showSuccess(L10n.format(.maintenancePruneSuccessMessage, deletedIds.count))
                }
            } catch {
                Task { @MainActor in
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    public func disasterRebuildCatalog() {
        guard let profile = selectedProfile else { return }

        Task {
            do {
                let count = try await restoreEngine.rebuildCatalog(at: profile.destinationURL)
                Task { @MainActor in
                    LogManager.shared.log("Disaster recovery catalog rebuilt for profile '\(profile.name)': \(count) snapshots indexed from target disk", level: .info, category: "Rebuild")
                    self.refreshLogs()
                    self.loadSnapshots()
                    self.showSuccess(L10n.format(.maintenanceRebuildSuccessMessage, count))
                }
            } catch {
                Task { @MainActor in
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Diagnostics

    @MainActor
    public func refreshLogs() {
        self.logEntries = LogManager.shared.getEntries().reversed()
        self.currentDebugLogFileURL = LogManager.shared.currentDebugLogFileURL
        self.isDebugFileLoggingEnabled = LogManager.shared.isDebugFileLoggingEnabled
    }

    @MainActor
    public func exportLogs(to destinationURL: URL) {
        do {
            let logText = LogManager.shared.exportLogsAsPlainText()
            try logText.data(using: .utf8)?.write(to: destinationURL)
            showSuccess(L10n.format(.logExportSuccess, destinationURL.lastPathComponent))
        } catch {
            showError(L10n.format(.logExportError, error.localizedDescription))
        }
    }

    @MainActor
    public func clearLogs() {
        LogManager.shared.clear()
        refreshLogs()
    }

    @MainActor
    public func copyDebugLogPath() {
        if let path = currentDebugLogFileURL?.path(percentEncoded: false) ?? LogManager.shared.currentDebugLogFileURL?.path(percentEncoded: false) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            showSuccess(L10n.t(.settingsDebugCopySuccess))
        }
    }

    // MARK: - Helpers

    @MainActor
    public func showError(_ message: String) {
        self.alertMessage = message
        self.showAlert = true
    }

    @MainActor
    public func showSuccess(_ message: String) {
        self.alertMessage = message
        self.showAlert = true
    }


}
