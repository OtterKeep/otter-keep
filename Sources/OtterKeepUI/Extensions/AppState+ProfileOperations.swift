import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension AppState {
    // MARK: - Scheduler Management

    func startScheduler() {
        BackupScheduler.shared.start(
            triggerHandler: { [weak self] profile, isCatchUp in
                Task { @MainActor in
                    guard let self = self else { return }
                    if isCatchUp {
                        LogManager.shared.log("Running catch-up backup for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]", level: .info, category: "Scheduler")
                    } else {
                        LogManager.shared.log("Running scheduled backup for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]", level: .info, category: "Scheduler")
                    }
                    self.startBackup(for: profile)
                }
            },
            photosTriggerHandler: { [weak self] config, isCatchUp in
                Task { @MainActor in
                    guard let self = self else { return }
                    if isCatchUp {
                        LogManager.shared.log("Running catch-up Photos backup", level: .info, category: "Scheduler")
                    } else {
                        LogManager.shared.log("Running scheduled Photos backup", level: .info, category: "Scheduler")
                    }
                    self.startPhotosBackup()
                }
            }
        )

        Task {
            await BackupScheduler.shared.checkAndRunCatchUpBackups()
        }
    }

    public func updateSchedule(
        isEnabled: Bool,
        frequency: ScheduleFrequency,
        hour: Int,
        minute: Int,
        weekday: Int,
        intervalMinutes: Int,
        catchUp: Bool
    ) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        profile.schedule.isEnabled = isEnabled
        profile.schedule.frequency = frequency
        profile.schedule.hour = hour
        profile.schedule.minute = minute
        profile.schedule.weekday = weekday
        profile.schedule.intervalMinutes = intervalMinutes
        profile.schedule.catchUpIfMissed = catchUp
        self.selectedProfile = profile
        saveProfiles()
        LogManager.shared.log("Schedule updated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: Enabled=\(isEnabled), Frequency=\(frequency.rawValue), Time=\(String(format: "%02d:%02d", hour, minute)), Interval=\(intervalMinutes)m, CatchUp=\(catchUp)", level: .info, category: "Scheduler")
        refreshLogs()
    }

    public func nextScheduledRunDescription(for profile: BackupProfile) -> String {
        guard profile.schedule.isEnabled else {
            return L10n.t(.scheduleNotScheduled)
        }
        let refDate = profile.schedule.lastRunDate ?? Date()
        let nextDate = BackupScheduler.shared.calculateNextRunDate(for: profile.schedule, referenceDate: refDate)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: nextDate)
    }

    public var nextScheduledRunDescription: String {
        guard let profile = selectedProfile else {
            return L10n.t(.scheduleNotScheduled)
        }
        return nextScheduledRunDescription(for: profile)
    }

    // MARK: - Auto-Pruning Policy Configuration

    public func updateAutoPruning(isEnabled: Bool, maxKeep: Int) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        profile.pruningPolicy.isAutoPruningEnabled = isEnabled
        profile.pruningPolicy.maxSnapshotsToKeep = maxKeep
        self.selectedProfile = profile
        self.maxSnapshotsToKeep = maxKeep
        saveProfiles()
        LogManager.shared.log("Auto-pruning policy updated for profile '\(profile.name)': Enabled=\(isEnabled), Retain=\(maxKeep)", level: .info, category: "Retention")
        refreshLogs()
    }

    // MARK: - Folder Validation & Selection Helpers

    public func validateFolderPair(sourceURL: URL, destinationURL: URL) -> Bool {
        let stdSource = sourceURL.standardizedFileURL.path
        let stdDest = destinationURL.standardizedFileURL.path
        if stdSource == stdDest { return false }
        if stdDest.hasPrefix(stdSource + "/") { return false }
        return true
    }

    @MainActor
    public func selectSourceDirectory() {
        guard let profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        pickDirectory(
            title: L10n.t(.selectSourceFolder),
            prompt: L10n.t(.selectFolderConfirm),
            initialURL: profile.sourceURL,
            canCreateDirectories: false
        ) { [weak self] url in
            self?.updateSourceURL(url)
        }
    }

    @MainActor
    public func selectDestinationDirectory() {
        guard let profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        pickDirectory(
            title: L10n.t(.selectDestinationFolder),
            prompt: L10n.t(.selectFolderConfirm),
            initialURL: profile.destinationURL,
            canCreateDirectories: true
        ) { [weak self] url in
            self?.updateDestinationURL(url)
        }
    }

    @MainActor
    public func pickDirectory(
        title: String? = nil,
        prompt: String? = nil,
        initialURL: URL? = nil,
        canCreateDirectories: Bool = true,
        completion: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = canCreateDirectories
        panel.allowsMultipleSelection = false
        if let title = title {
            panel.title = title
            panel.message = title
        }
        if let prompt = prompt {
            panel.prompt = prompt
        }
        if let initial = initialURL {
            panel.directoryURL = initial
        }

        if let keyWindow = NSApp.keyWindow {
            let targetWindow = keyWindow.attachedSheet ?? keyWindow
            panel.beginSheetModal(for: targetWindow) { response in
                if response == .OK, let url = panel.url {
                    completion(url)
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                completion(url)
            }
        }
    }

    // MARK: - Source, Destination & Exclusions Persistence

    public func updateSourceURL(_ url: URL) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        guard validateFolderPair(sourceURL: url, destinationURL: profile.destinationURL) else {
            showError(L10n.t(.invalidFolderSelectionMessage))
            return
        }
        profile.sourceURL = url
        self.selectedProfile = profile
        saveProfiles()
        refreshVolumeEvaluation()
        LogManager.shared.log("Source directory updated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: '\(url.path)'", level: .info, category: "Profile")
        refreshLogs()
    }

    public func updateDestinationURL(_ url: URL) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        guard validateFolderPair(sourceURL: profile.sourceURL, destinationURL: url) else {
            showError(L10n.t(.invalidFolderSelectionMessage))
            return
        }
        profile.destinationURL = url
        self.selectedProfile = profile
        saveProfiles()
        refreshVolumeEvaluation()
        loadSnapshots()
        LogManager.shared.log("Destination directory updated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: '\(url.path)'", level: .info, category: "Profile")
        refreshLogs()
    }

    public func addExcludePattern(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        if !profile.excludePatterns.contains(trimmed) {
            profile.excludePatterns.append(trimmed)
            self.selectedProfile = profile
            saveProfiles()
            LogManager.shared.log("Exclusion pattern added for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: '\(trimmed)'", level: .info, category: "Profile")
            refreshLogs()
        }
    }

    public func removeExcludePattern(_ pattern: String) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        profile.excludePatterns.removeAll(where: { $0 == pattern })
        self.selectedProfile = profile
        saveProfiles()
        LogManager.shared.log("Exclusion pattern removed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: '\(pattern)'", level: .info, category: "Profile")
        refreshLogs()
    }

    // MARK: - Profile Operations

    public func createProfile(
        name: String,
        sourceURL: URL? = nil,
        destinationURL: URL? = nil,
        excludePatterns: [String]? = nil,
        enableIgnoreFiles: Bool = true,
        respectGitIgnore: Bool = false,
        backupOnVolumeMount: Bool = false,
        autoEjectOnCompletion: Bool = false
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let defaultSource = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let defaultDest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups_\(trimmed.replacingOccurrences(of: " ", with: "_"))")

        let effectiveSource = sourceURL ?? defaultSource
        let effectiveDest = destinationURL ?? defaultDest

        guard validateFolderPair(sourceURL: effectiveSource, destinationURL: effectiveDest) else {
            showError(L10n.t(.invalidFolderSelectionMessage))
            return
        }

        let newProfile = BackupProfile(
            name: trimmed,
            sourceURL: effectiveSource,
            destinationURL: effectiveDest,
            excludePatterns: excludePatterns ?? ["*.tmp", ".DS_Store", "node_modules", "DerivedData"],
            enableIgnoreFiles: enableIgnoreFiles,
            respectGitIgnore: respectGitIgnore,
            backupOnVolumeMount: backupOnVolumeMount,
            autoEjectOnCompletion: autoEjectOnCompletion
        )
        profiles.append(newProfile)
        selectedProfileId = newProfile.id
        saveProfiles()
        refreshVolumeEvaluation()
        loadSnapshots()
        LogManager.shared.log("New profile created: '\(trimmed)' [UUID: \(newProfile.id.uuidString)] (Source: '\(newProfile.sourceURL.path)', Dest: '\(newProfile.destinationURL.path)')", level: .info, category: "Profile")
        refreshLogs()
    }

    public func createProfileFromDraft() {
        let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        createProfile(
            name: trimmed,
            sourceURL: newProfileSourceURL,
            destinationURL: newProfileDestinationURL,
            excludePatterns: newProfileExcludePatterns,
            enableIgnoreFiles: newProfileEnableIgnoreFiles,
            respectGitIgnore: newProfileRespectGitIgnore,
            backupOnVolumeMount: newProfileBackupOnVolumeMount,
            autoEjectOnCompletion: newProfileAutoEjectOnCompletion
        )
    }

    public func renameProfile(id: UUID, newName: String) {
        guard !isBackupRunning(for: id) else {
            LogManager.shared.log("Cannot rename profile while backup is actively running [UUID: \(id.uuidString)]", level: .warning, category: "Profile")
            return
        }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = trimmed
        saveProfiles()
        LogManager.shared.log("Profile renamed to: '\(trimmed)' [UUID: \(id.uuidString)]", level: .info, category: "Profile")
        refreshLogs()
    }

    public func deleteProfile(id: UUID) {
        guard !isBackupRunning(for: id) else {
            LogManager.shared.log("Cannot delete profile while backup is actively running [UUID: \(id.uuidString)]", level: .warning, category: "Profile")
            return
        }
        guard profiles.count > 1, let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        let removedProfile = profiles[idx]
        let removedName = removedProfile.name
        profiles.remove(at: idx)
        if selectedProfileId == id {
            selectedProfileId = profiles.first?.id
        }

        // Clean up Keychain credentials associated with the deleted profile
        KeychainManager.deletePassphrase(for: id)
        KeychainManager.deleteSecret(for: id.uuidString)
        KeychainManager.deleteSecret(for: "s3_\(id.uuidString)")
        KeychainManager.deleteSecret(for: "smb_\(id.uuidString)")
        KeychainManager.deleteSecret(for: "webdav_\(id.uuidString)")
        KeychainManager.deleteSecret(for: "sftp_\(id.uuidString)")
        KeychainManager.deleteSecret(for: "webhook_\(id.uuidString)")
        for dest in removedProfile.copyJobConfig.destinations {
            KeychainManager.deleteSecret(for: dest.id.uuidString)
            KeychainManager.deleteSecret(for: "s3_\(dest.id.uuidString)")
            KeychainManager.deleteSecret(for: "smb_\(dest.id.uuidString)")
            KeychainManager.deleteSecret(for: "webdav_\(dest.id.uuidString)")
            KeychainManager.deleteSecret(for: "sftp_\(dest.id.uuidString)")
        }

        saveProfiles()
        refreshVolumeEvaluation()
        loadSnapshots()
        LogManager.shared.log("Profile deleted: '\(removedName)' [UUID: \(id.uuidString)]", level: .info, category: "Profile")
        refreshLogs()
    }

    /// Opens the native macOS Sequoia About (Névjegy) panel.
    public func openAbout() {
        AboutWindowController.shared.show()
    }


}
