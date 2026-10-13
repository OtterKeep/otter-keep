import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension AppState {
    // MARK: - Software Updates Management

    public var automaticallyChecksForUpdates: Bool {
        get {
            if UserDefaults.standard.object(forKey: "OtterKeep.AutoCheckForUpdates") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "OtterKeep.AutoCheckForUpdates")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "OtterKeep.AutoCheckForUpdates")
        }
    }

    public func checkForSoftwareUpdates(silent: Bool = false) {
        guard !isCheckingForSoftwareUpdates else { return }
        isCheckingForSoftwareUpdates = true
        if !silent {
            softwareUpdateStatusMessage = L10n.t(.settingsUpdateStatusChecking)
        }
        softwareUpdateAvailableInfo = nil

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let status = await SoftwareUpdateCoordinator.shared.checkForUpdates()
            switch status {
            case .updateAvailable(let info):
                self.softwareUpdateAvailableInfo = info
                self.softwareUpdateStatusMessage = L10n.format(.settingsUpdateStatusAvailableFormat, info.version)
                NotificationDeliveryService.shared.notifySoftwareUpdateAvailable(version: info.version)
            case .upToDate:
                if !silent {
                    self.softwareUpdateStatusMessage = L10n.t(.settingsUpdateStatusUpToDate)
                }
            case .failed(let err):
                if !silent {
                    self.softwareUpdateStatusMessage = L10n.format(.settingsUpdateStatusFailedFormat, err)
                }
            case .checking, .idle:
                break
            }
            self.isCheckingForSoftwareUpdates = false
        }
    }

    // MARK: - Backup Operations & Analysis

    /// Parallel executes backups across all configured profiles.
    public func startBackupAll(mode: BackupMode = .incremental) {
        let profilesToRun = self.profiles
        guard !profilesToRun.isEmpty else { return }

        LogManager.shared.log("Parallel batch backup requested for all \(profilesToRun.count) profile(s).", level: .info, category: "UI")
        refreshLogs()

        for profile in profilesToRun {
            if !isBackupRunning(for: profile.id) {
                startBackup(for: profile, mode: mode)
            }
        }
    }

    public func startBackup(for profileToBackup: BackupProfile? = nil, mode: BackupMode = .incremental) {
        guard let profile = profileToBackup ?? selectedProfile else { return }
        guard !isBackupRunning(for: profile.id) else {
            LogManager.shared.log("Backup already in progress for profile '\(profile.name)' [UUID: \(profile.id.uuidString)] - skipping duplicate launch.", level: .warning, category: "UI")
            return
        }

        profileProgressStates[profile.id] = BackupProgressState(phase: .scanning)
        let modeTag = mode == .full ? " (FORCED FULL)" : " (Incremental)"
        LogManager.shared.log("Backup initiated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]\(modeTag)", level: .info, category: "UI")
        refreshLogs()

        // Create dedicated, isolated session coordinator and SQLite database to support zero-contention parallel backups
        let sessionDb = DatabaseEngine()
        let sessionRetention = RetentionManager(storage: self.storage, database: sessionDb)
        let sessionCoordinator = BackupSessionCoordinator(
            storage: self.storage,
            database: sessionDb,
            retentionManager: sessionRetention,
            volumeEjector: SystemVolumeEjector()
        )

        let task = Task { [weak self] in
            guard let self = self else { return }
            do {
                _ = try await sessionCoordinator.performBackup(profile: profile, mode: mode) { [weak self] progress in
                    Task { @MainActor in
                        self?.profileProgressStates[profile.id] = progress
                    }
                }
                let coordinatorSummary = await sessionCoordinator.lastSessionSummary
                let finalSummary = coordinatorSummary ?? self.profileProgressStates[profile.id]?.lastSummary
                if let summary = finalSummary {
                    self.profileLastSummaries[profile.id] = summary
                }
                if self.selectedProfileId == profile.id {
                    self.lastSessionSummary = finalSummary
                }

                self.activeBackupTasks.removeValue(forKey: profile.id)
                self.profileProgressStates[profile.id] = BackupProgressState(phase: .idle)

                if let idx = self.profiles.firstIndex(where: { $0.id == profile.id }) {
                    self.profiles[idx].schedule.lastRunDate = Date()
                    self.saveProfiles()
                }

                LogManager.shared.log("Backup completed successfully for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]\(modeTag)", level: .info, category: "UI")
                self.refreshLogs()
                self.loadSnapshots()

                // Trigger Operation Feedback Modal
                self.activeFeedback = OperationFeedback(
                    type: .success,
                    title: L10n.t(.feedbackSuccessTitle),
                    message: L10n.format(.feedbackSuccessMessage, profile.name),
                    profileName: profile.name,
                    summary: finalSummary
                )
                self.showFeedbackModal = true

                // Trigger 3-2-1 Replication from UI AppState to provide live telemetry
                if profile.copyJobConfig.isEnabled && profile.copyJobConfig.trigger == .onPrimarySuccess {
                    self.startReplication(for: profile)
                }
            } catch is CancellationError {
                self.activeBackupTasks.removeValue(forKey: profile.id)
                self.profileProgressStates[profile.id] = BackupProgressState(phase: .idle)
                LogManager.shared.log("Backup cancelled by user for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]", level: .info, category: "UI")
                self.refreshLogs()
            } catch {
                self.activeBackupTasks.removeValue(forKey: profile.id)
                self.profileProgressStates[profile.id] = BackupProgressState(phase: .failed)
                NotificationDeliveryService.shared.notifyBackupFailed(profileName: profile.name, errorMessage: error.localizedDescription)
                LogManager.shared.log("Backup failed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: \(error.localizedDescription)", level: .error, category: "UI")
                self.refreshLogs()

                let analyzed = Self.analyzeBackupError(error, destinationURL: profile.destinationURL, sourceURL: profile.sourceURL)
                self.activeFeedback = OperationFeedback(
                    type: .failure,
                    title: analyzed.title,
                    message: analyzed.message,
                    detailedReason: analyzed.detailedReason,
                    profileName: profile.name
                )
                self.showFeedbackModal = true
            }
        }

        activeBackupTasks[profile.id] = task
    }

    @MainActor
    public func cancelBackup(for profileId: UUID? = nil) {
        let targetId = profileId ?? selectedProfileId
        if let id = targetId, let task = activeBackupTasks[id] {
            let profileName = profiles.first(where: { $0.id == id })?.name ?? id.uuidString
            LogManager.shared.log("Cancelling backup upon user request for profile '\(profileName)'...", level: .info, category: "UI")
            task.cancel()
            activeBackupTasks.removeValue(forKey: id)
            profileProgressStates[id] = BackupProgressState(phase: .idle)
            refreshLogs()
        } else if targetId == nil {
            LogManager.shared.log("Cancelling all running backups upon user request...", level: .info, category: "UI")
            for (id, task) in activeBackupTasks {
                task.cancel()
                profileProgressStates[id] = BackupProgressState(phase: .idle)
            }
            activeBackupTasks.removeAll()
            refreshLogs()
        }
    }

    /// Analyzes backup failure errors to produce precise, non-misleading user guidance.
    public static func analyzeBackupError(_ error: Error, destinationURL: URL?, sourceURL: URL?) -> (title: String, message: String, detailedReason: String) {
        let errorDesc = error.localizedDescription

        // 1. External drive disconnected or destination directory vanished
        if let dest = destinationURL, !FileManager.default.fileExists(atPath: dest.path) {
            return (
                title: L10n.t(.feedbackExternalDriveMissingTitle),
                message: L10n.format(.feedbackExternalDriveMissingMessage, dest.lastPathComponent),
                detailedReason: L10n.t(.feedbackExternalDriveMissingAdvice)
            )
        }

        // 2. Source folder missing or renamed
        if let src = sourceURL, !FileManager.default.fileExists(atPath: src.path) {
            return (
                title: L10n.t(.feedbackSourceFolderMissingTitle),
                message: L10n.format(.feedbackSourceFolderMissingMessage, src.lastPathComponent),
                detailedReason: L10n.t(.feedbackSourceFolderMissingAdvice)
            )
        }

        // 3. Insufficient disk space
        if errorDesc.localizedCaseInsensitiveContains("space") ||
           errorDesc.localizedCaseInsensitiveContains("No space left") ||
           (error as NSError).code == 28 {
            return (
                title: L10n.t(.feedbackDiskFullTitle),
                message: L10n.t(.feedbackDiskFullMessage),
                detailedReason: L10n.t(.feedbackDiskFullAdvice)
            )
        }

        // 4. macOS Full Disk Access or filesystem permission denied
        if errorDesc.localizedCaseInsensitiveContains("permission") ||
           errorDesc.localizedCaseInsensitiveContains("Permission denied") ||
           (error as NSError).code == 13 {
            return (
                title: L10n.t(.feedbackPermissionDeniedTitle),
                message: L10n.t(.feedbackPermissionDeniedMessage),
                detailedReason: L10n.t(.feedbackPermissionDeniedAdvice)
            )
        }

        // 5. General failure with calm, reassuring advice
        return (
            title: L10n.t(.feedbackGeneralErrorTitle),
            message: errorDesc,
            detailedReason: L10n.t(.feedbackGeneralErrorAdvice)
        )
    }

    public func performDryRun(mode: BackupMode = .incremental) {
        guard let profile = selectedProfile, !isBackupRunning(for: profile.id), !isDryRunRunning else { return }

        isDryRunRunning = true
        let modeTag = mode == .full ? " (FULL)" : " (Incremental)"
        LogManager.shared.log("Pre-backup analysis (Dry-Run\(modeTag)) started for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]", level: .info, category: "UI")
        refreshLogs()

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let summary = try await self.coordinator.performDryRun(profile: profile, mode: mode)
                Task { @MainActor in
                    self.isDryRunRunning = false
                    self.dryRunSummary = summary
                    self.showDryRunModal = true
                    LogManager.shared.log("Dry-Run completed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: Added: \(summary.addedCount) files (\(summary.addedBytes) bytes), Modified: \(summary.modifiedCount) files (\(summary.modifiedBytes) bytes), Deleted: \(summary.deletedCount) files, Unmodified (CoW): \(summary.unmodifiedCount) files, Estimated new storage: \(summary.estimatedNewBytes) bytes.", level: .info, category: "UI")
                    self.refreshLogs()
                }
            } catch {
                Task { @MainActor in
                    self.isDryRunRunning = false
                    LogManager.shared.log("Dry-Run analysis failed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: \(error.localizedDescription)", level: .error, category: "UI")
                    self.refreshLogs()
                    self.showError(error.localizedDescription)
                }
            }
        }
    }


}
