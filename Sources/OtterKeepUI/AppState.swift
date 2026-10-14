import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

/// Central `@Observable` view-model orchestrating application state, profile switching, background backup execution, and restore operations on the `@MainActor`.
@MainActor
@Observable
public final class AppState: Sendable {
    /// List of all configured backup profiles.
    public var profiles: [BackupProfile] = []
    /// Currently selected backup profile ID.
    public var selectedProfileId: UUID?
    /// Active navigation section in the split view sidebar.
    public var activeNavigation: NavigationSection = .photos

    /// Currently active tab within the selected Profile workspace.
    public var activeProfileTab: ProfileWorkspaceTab = .overview
    /// Currently active sub-tab within the Profile Rules & Maintenance workspace.
    public var activeMaintenanceSubTab: ProfileMaintenanceSubTab = .rules
    /// Currently active tab within the Apple Photos workspace.
    public var activePhotosTab: PhotosWorkspaceTab = .syncAndBackup

    // MARK: - Feature Stores
    /// Maintenance, diagnostics and settings state (modals, alerts, logs, preferences, draft forms).
    let maintenanceSettings = MaintenanceSettingsStore()
    /// 3-2-1 replication runtime state and every remote destination editor field.
    let replicationDestinations = ReplicationDestinationStore()
    /// Restore, timeline and diff comparison state.
    let restoreTimeline = RestoreTimelineStore()
    /// Photos backup and browsing state; its persisted configuration is loaded in `init()`.
    let photosStore: PhotosStore

    // MARK: - Per-Profile Parallel Backup Operations State (1.3.1)
    /// Per-profile runtime state (tasks, progress, summaries, snapshot caches).
    let backupRuntime = BackupRuntimeStore()

    /// Active background backup tasks keyed by profile UUID.
    var activeBackupTasks: [UUID: Task<Void, Never>] {
        get { backupRuntime.activeBackupTasks }
        set { backupRuntime.activeBackupTasks = newValue }
    }

    /// Live telemetry progress states keyed by profile UUID.
    public internal(set) var profileProgressStates: [UUID: BackupProgressState] {
        get { backupRuntime.progressStates }
        set { backupRuntime.progressStates = newValue }
    }

    /// Last session summaries keyed by profile UUID.
    public internal(set) var profileLastSummaries: [UUID: BackupSessionSummary] {
        get { backupRuntime.lastSummaries }
        set { backupRuntime.lastSummaries = newValue }
    }

    /// Indicates whether a backup operation is currently executing for any profile.
    public var isBackupRunning: Bool {
        backupRuntime.isRunning
    }

    /// Checks if a specific profile is currently backing up.
    public func isBackupRunning(for profileId: UUID) -> Bool {
        backupRuntime.isRunning(for: profileId)
    }

    /// Retrieves the live progress state for a specific profile (or idle if not running).
    public func progressState(for profileId: UUID) -> BackupProgressState {
        backupRuntime.progressState(for: profileId)
    }

    // MARK: - Per-Profile Historical Status & Snapshot Cache (1.6.0)
    /// Latest snapshot records cached per profile UUID to preserve status across profile switching.
    public internal(set) var profileLatestSnapshots: [UUID: SnapshotRecord] {
        get { backupRuntime.latestSnapshots }
        set { backupRuntime.latestSnapshots = newValue }
    }
    /// Total snapshot counts cached per profile UUID.
    public internal(set) var profileSnapshotCounts: [UUID: Int] {
        get { backupRuntime.snapshotCounts }
        set { backupRuntime.snapshotCounts = newValue }
    }

    /// Caches snapshot and summary metadata for a profile (useful for testing and cross-profile synchronization).
    public func cacheProfileStatus(
        profileId: UUID,
        latestSnapshot: SnapshotRecord?,
        snapshotCount: Int? = nil,
        lastSummary: BackupSessionSummary? = nil
    ) {
        if let snap = latestSnapshot {
            backupRuntime.latestSnapshots[profileId] = snap
            backupRuntime.snapshotCounts[profileId] = snapshotCount ?? 1
        } else {
            backupRuntime.latestSnapshots.removeValue(forKey: profileId)
            backupRuntime.snapshotCounts.removeValue(forKey: profileId)
        }
        if let summary = lastSummary {
            backupRuntime.lastSummaries[profileId] = summary
        } else {
            backupRuntime.lastSummaries.removeValue(forKey: profileId)
        }
    }

    public struct ProfileBackupStatusInfo: Sendable {
        public let profileId: UUID
        public let profileName: String
        public let isRunning: Bool
        public let hasSnapshots: Bool
        public let totalSnapshots: Int
        public let lastBackupDate: Date?
        public let lastSessionSummary: BackupSessionSummary?
        public let lastSnapshot: SnapshotRecord?
        public let displayStatusText: String
        public let displayDetailText: String

        public init(
            profileId: UUID,
            profileName: String,
            isRunning: Bool,
            hasSnapshots: Bool,
            totalSnapshots: Int,
            lastBackupDate: Date?,
            lastSessionSummary: BackupSessionSummary?,
            lastSnapshot: SnapshotRecord?,
            displayStatusText: String,
            displayDetailText: String
        ) {
            self.profileId = profileId
            self.profileName = profileName
            self.isRunning = isRunning
            self.hasSnapshots = hasSnapshots
            self.totalSnapshots = totalSnapshots
            self.lastBackupDate = lastBackupDate
            self.lastSessionSummary = lastSessionSummary
            self.lastSnapshot = lastSnapshot
            self.displayStatusText = displayStatusText
            self.displayDetailText = displayDetailText
        }

        public var statusColor: Color {
            if isRunning {
                return OtterTheme.oceanicTeal
            } else if let summary = lastSessionSummary, summary.errorCount > 0 {
                return OtterTheme.statusWarning
            } else if hasSnapshots {
                return OtterTheme.statusGreen
            } else {
                return .secondary
            }
        }
    }

    /// Formats a date relative to now in friendly localized terms (e.g., "5 minutes ago", "Yesterday").
    public static func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Retrieves structured status information for a given profile, reflecting live execution or last snapshot.
    public func lastStatusInfo(for profile: BackupProfile) -> ProfileBackupStatusInfo {
        let isRunning = isBackupRunning(for: profile.id)
        let summary = profileLastSummaries[profile.id]
        let latestSnap = (selectedProfileId == profile.id ? snapshots.first : nil) ?? profileLatestSnapshots[profile.id]
        let snapCount = (selectedProfileId == profile.id && !snapshots.isEmpty) ? snapshots.count : (profileSnapshotCounts[profile.id] ?? (latestSnap != nil ? 1 : 0))

        if isRunning {
            let prog = progressState(for: profile.id)
            let phaseText = L10n.t(prog.phase.localizedKey)
            return ProfileBackupStatusInfo(
                profileId: profile.id,
                profileName: profile.name,
                isRunning: true,
                hasSnapshots: snapCount > 0,
                totalSnapshots: snapCount,
                lastBackupDate: latestSnap?.timestamp,
                lastSessionSummary: summary,
                lastSnapshot: latestSnap,
                displayStatusText: L10n.t(.statusRunning),
                displayDetailText: phaseText
            )
        } else if let sum = summary {
            let isSuccess = sum.errorCount == 0
            let date = latestSnap?.timestamp ?? Date()
            let dateStr = Self.relativeDateString(for: date)
            let statusText = isSuccess ? L10n.t(.lastBackupSuccess) : L10n.t(.lastBackupWarning)
            return ProfileBackupStatusInfo(
                profileId: profile.id,
                profileName: profile.name,
                isRunning: false,
                hasSnapshots: true,
                totalSnapshots: snapCount,
                lastBackupDate: date,
                lastSessionSummary: sum,
                lastSnapshot: latestSnap,
                displayStatusText: statusText,
                displayDetailText: L10n.format(.profileStatusLastBackupFormat, dateStr)
            )
        } else if let snap = latestSnap {
            let dateStr = Self.relativeDateString(for: snap.timestamp)
            return ProfileBackupStatusInfo(
                profileId: profile.id,
                profileName: profile.name,
                isRunning: false,
                hasSnapshots: true,
                totalSnapshots: snapCount,
                lastBackupDate: snap.timestamp,
                lastSessionSummary: nil,
                lastSnapshot: snap,
                displayStatusText: L10n.t(.lastBackupSuccess),
                displayDetailText: L10n.format(.profileStatusLastBackupFormat, dateStr)
            )
        } else {
            return ProfileBackupStatusInfo(
                profileId: profile.id,
                profileName: profile.name,
                isRunning: false,
                hasSnapshots: false,
                totalSnapshots: 0,
                lastBackupDate: nil,
                lastSessionSummary: nil,
                lastSnapshot: nil,
                displayStatusText: L10n.t(.profileStatusIdleNoBackups),
                displayDetailText: L10n.t(.sanctuaryNeverBackedUp)
            )
        }
    }

    /// Evaluates the complete health and timeliness status for a backup profile, accounting for active
    /// execution, previous backup errors, schedule deadlines, and 14-day staleness boundaries.
    public func profileHealthStatus(for profile: BackupProfile, now: Date = Date()) -> ProfileHealthStatus {
        let statusInfo = lastStatusInfo(for: profile)

        // 1. Actively running
        if statusInfo.isRunning {
            return .running
        }

        // 2. Never backed up
        guard statusInfo.hasSnapshots, let lastDate = statusInfo.lastBackupDate else {
            return .neverBackedUp
        }

        // 3. Last backup had errors
        if let summary = statusInfo.lastSessionSummary, summary.errorCount > 0 {
            return .failed(errorCount: summary.errorCount)
        }

        let ageSeconds = now.timeIntervalSince(lastDate)

        // 4. Older than 14 days
        let fourteenDaysSeconds: TimeInterval = 14 * 86400
        if ageSeconds > fourteenDaysSeconds {
            let daysOld = Int(ageSeconds / 86400)
            return .staleFourteenDays(daysOld: daysOld)
        }

        // 5. Older than enabled schedule specifies
        if profile.schedule.isEnabled {
            let nextRun = BackupScheduler.shared.calculateNextRunDate(for: profile.schedule, referenceDate: lastDate)
            if nextRun < now && now.timeIntervalSince(nextRun) > 300 {
                return .scheduleOverdue
            }
        }

        // 6. Healthy & up to date
        return .healthy
    }

    /// Backward-compatible progress state resolving to the currently selected profile (or first active).
    public var progressState: BackupProgressState {
        get {
            if let selectedId = selectedProfileId, let state = profileProgressStates[selectedId] {
                return state
            }
            if let firstActive = profileProgressStates.values.first(where: { $0.phase != .idle }) {
                return firstActive
            }
            return BackupProgressState(phase: .idle)
        }
        set {
            if let selectedId = selectedProfileId {
                profileProgressStates[selectedId] = newValue
            }
        }
    }

    // MARK: - Testing State Helpers
    /// Simulates or sets running state for testing profile lockout and multi-profile parallelism.
    public func setBackupRunningForTesting(profileId: UUID, running: Bool) {
        if running {
            activeBackupTasks[profileId] = Task { try? await Task.sleep(nanoseconds: 10_000_000_000) }
            profileProgressStates[profileId] = BackupProgressState(phase: .copying)
        } else {
            activeBackupTasks[profileId]?.cancel()
            activeBackupTasks.removeValue(forKey: profileId)
            profileProgressStates.removeValue(forKey: profileId)
        }
    }

    /// Sets simulated system dark mode state for theme switcher testing.
    public func setSystemDarkModeForTesting(_ isDark: Bool) {
        self.isSystemDarkMode = isDark
    }

    // MARK: - New Profile Draft Helpers
    public func resetNewProfileDraft() {
        maintenanceSettings.resetNewProfileDraft()
    }

    public func applyDeveloperPreset() {
        maintenanceSettings.applyDeveloperPreset()
    }

    public func applyDocumentsPreset() {
        maintenanceSettings.applyDocumentsPreset()
    }

    public func applyCreativePreset() {
        maintenanceSettings.applyCreativePreset()
    }

    public func updateNewProfileName(_ newName: String) {
        maintenanceSettings.updateNewProfileName(newName)
    }

    // MARK: - Language, Theme & Settings State

    /// Evaluates the true operating system appearance setting.
    public func updateSystemDarkMode() {
        maintenanceSettings.updateSystemDarkMode()
    }

    /// Synchronizes the global macOS application appearance with the selected theme mode.
    public func applyThemeAppearance(_ theme: AppThemeMode) {
        updateSystemDarkMode()
        let targetAppearance: NSAppearance?
        switch theme {
        case .system:
            targetAppearance = nil
        case .light:
            targetAppearance = NSAppearance(named: .aqua)
        case .dark:
            targetAppearance = NSAppearance(named: .darkAqua)
        }

        NSApplication.shared.appearance = targetAppearance
        for window in NSApplication.shared.windows {
            window.appearance = targetAppearance
        }
    }

    // MARK: - Finder Integration State
    /// Re-evaluates macOS permissions and extension state for the Finder integration.
    public func refreshFinderPermissionStatus() {
        self.finderPermissionStatus = FinderPermissionManager.shared.evaluateStatus(for: profiles)
    }

    let storage: FileSystemProvider
    let database: DatabaseEngine
    let coordinator: BackupSessionCoordinator
    let retentionManager: RetentionManager
    let restoreEngine: RestoreEngine
    let photosCoordinator: PhotosBackupCoordinator

    public init() {
        let storage = DefaultFileSystemProvider()
        let database = DatabaseEngine()
        let retentionManager = RetentionManager(storage: storage, database: database)
        self.storage = storage
        self.database = database
        self.retentionManager = retentionManager
        self.coordinator = BackupSessionCoordinator(
            storage: storage,
            database: database,
            retentionManager: retentionManager,
            volumeEjector: SystemVolumeEjector()
        )
        self.restoreEngine = RestoreEngine(storage: storage, database: database)
        self.photosCoordinator = PhotosBackupCoordinator(storage: storage, dbEngine: database)

        // Load persistent profiles from ~/.otterkeep/profiles.json
        let loadedProfiles = ProfileStore.shared.loadProfiles()
        self.profiles = loadedProfiles
        if let firstId = loadedProfiles.first?.id {
            self.selectedProfileId = firstId
            self.activeNavigation = .profile(firstId)
        } else {
            self.activeNavigation = .photos
        }

        // Load Photos backup configuration
        self.photosStore = PhotosStore(config: PhotosProfileStore.shared.loadConfiguration())

        // Rename default profile if required by the effective language
        let currentEffective = LocalizationManager.shared.effectiveLanguage
        let expectedDefault = L10n.t(.defaultProfileName, lang: currentEffective)
        let oppositeDefault = currentEffective == .english ? "Alapértelmezett profil" : "Default profile"
        if let defaultProf = loadedProfiles.first(where: { $0.name == oppositeDefault }) {
            renameProfile(id: defaultProf.id, newName: expectedDefault)
        }

        refreshVolumeEvaluation()
        refreshLogs()
        checkPhotosAuthorization()
        refreshPhotosLibraryStats()
        loadPhotosSnapshots()
        applyThemeAppearance(self.currentTheme)

        // Observe macOS system theme changes (Auto mode live switching)
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.updateSystemDarkMode()
                if self.currentTheme == .system {
                    self.applyThemeAppearance(.system)
                }
            }
        }

        startScheduler()
    }

    public var selectedProfile: BackupProfile? {
        get {
            profiles.first(where: { $0.id == selectedProfileId })
        }
        set {
            if let newValue = newValue, let index = profiles.firstIndex(where: { $0.id == newValue.id }) {
                profiles[index] = newValue
                saveProfiles()
                refreshVolumeEvaluation()
            }
        }
    }

    public func selectProfile(id: UUID) {
        selectedProfileId = id
        activeNavigation = .profile(id)
        self.lastSessionSummary = self.profileLastSummaries[id]
        refreshVolumeEvaluation()
        loadSnapshots()
    }

    public func saveProfiles() {
        try? ProfileStore.shared.saveProfiles(profiles)
        BackupScheduler.shared.syncContinuousWatchers()
    }

    public func refreshVolumeEvaluation() {
        guard let profile = selectedProfile else {
            self.volumeEvaluation = nil
            return
        }
        self.volumeEvaluation = VolumeCapabilityEvaluator.evaluate(
            sourceURL: profile.sourceURL,
            destinationURL: profile.destinationURL
        )
    }

    /// Queries total, free, and available storage capacities on the currently selected destination volume.
    public func destinationStorageCapacity() -> StorageCapacity? {
        guard let destURL = selectedProfile?.destinationURL else { return nil }
        return try? storage.storageCapacity(at: destURL)
    }

    /// Checks whether the destination volume/folder of a given profile is reachable and mounted.
    public func isDestinationReachable(for profile: BackupProfile) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: profile.destinationURL.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Retrieves the volume name of the profile's destination.
    public func destinationVolumeName(for profile: BackupProfile) -> String? {
        let vals = try? profile.destinationURL.resourceValues(forKeys: [.volumeNameKey])
        return vals?.volumeName
    }

    /// Determines whether the destination of the profile resides on an external or removable storage device.
    public func isDestinationRemovable(for profile: BackupProfile) -> Bool {
        guard let vals = try? profile.destinationURL.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsInternalKey]) else {
            return false
        }
        return vals.volumeIsRemovable == true || vals.volumeIsInternal == false
    }

    /// Safely unmounts and ejects the destination volume for the given profile.
    public func ejectDestinationVolume(for profile: BackupProfile) {
        guard !isBackupRunning(for: profile.id) else {
            showError(L10n.t(.errBackupInProgress))
            return
        }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: profile.destinationURL)
            LogManager.shared.log("Destination volume safely unmounted and ejected for profile '\(profile.name)'.", level: .info, category: "Storage")
            refreshLogs()
            let volName = destinationVolumeName(for: profile) ?? profile.name
            showSuccess(L10n.format(.destinationEjectedSuccessFormat, volName))
        } catch {
            LogManager.shared.log("Failed to safely unmount destination volume for profile '\(profile.name)': \(error.localizedDescription)", level: .error, category: "Storage")
            refreshLogs()
            showError(error.localizedDescription)
        }
    }

    /// Calculates the sum of all stored snapshot catalog sizes for the selected profile.
    public func totalBackupSize() -> Int64 {
        snapshots.reduce(0) { $0 + $1.totalBytes }
    }

}
