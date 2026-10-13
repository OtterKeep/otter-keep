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

    // MARK: - Per-Profile Parallel Backup Operations State (1.3.1)
    /// Active background backup tasks keyed by profile UUID.
    var activeBackupTasks: [UUID: Task<Void, Never>] = [:]

    /// Live telemetry progress states keyed by profile UUID.
    public internal(set) var profileProgressStates: [UUID: BackupProgressState] = [:]

    /// Last session summaries keyed by profile UUID.
    public internal(set) var profileLastSummaries: [UUID: BackupSessionSummary] = [:]

    /// Indicates whether a backup operation is currently executing for any profile.
    public var isBackupRunning: Bool {
        !activeBackupTasks.isEmpty
    }

    /// Checks if a specific profile is currently backing up.
    public func isBackupRunning(for profileId: UUID) -> Bool {
        activeBackupTasks[profileId] != nil
    }

    /// Retrieves the live progress state for a specific profile (or idle if not running).
    public func progressState(for profileId: UUID) -> BackupProgressState {
        profileProgressStates[profileId] ?? BackupProgressState(phase: .idle)
    }

    // MARK: - Per-Profile Historical Status & Snapshot Cache (1.6.0)
    /// Latest snapshot records cached per profile UUID to preserve status across profile switching.
    public internal(set) var profileLatestSnapshots: [UUID: SnapshotRecord] = [:]
    /// Total snapshot counts cached per profile UUID.
    public internal(set) var profileSnapshotCounts: [UUID: Int] = [:]

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

    // MARK: - Modal Operation Feedback State (1.3.1)
    public var activeFeedback: OperationFeedback? = nil
    public var showFeedbackModal: Bool = false

    // MARK: - 3-2-1 Replication State
    public var isReplicationRunning: Bool = false
    public var replicationProgressState: ReplicationProgressState = ReplicationProgressState()
    public var lastReplicationSummary: ReplicationJobSummary?

    // MARK: - Remote Destination Editor Sheet State
    public var showRemoteDestinationEditorSheet: Bool = false
    public var destinationEditorTargetId: UUID? = nil
    public var destinationEditorName: String = ""
    public var destinationEditorTypeIndex: Int = 0 // 0: S3, 1: SMB, 2: WebDAV, 3: SFTP, 4: Backblaze B2
    public var destinationEditorS3Endpoint: String = "https://s3.amazonaws.com"
    public var destinationEditorS3Bucket: String = ""
    public var destinationEditorS3Region: String = "eu-central-1"
    public var destinationEditorS3AccessKeyId: String = ""
    public var destinationEditorS3SecretAccessKey: String = ""
    public var destinationEditorS3PathPrefix: String = "otterkeep"
    public var destinationEditorS3ForcePathStyle: Bool = true
    public var destinationEditorSmbShareURL: String = "smb://nas.local/backups"
    public var destinationEditorSmbMountPath: String = "/Volumes/backups"
    public var destinationEditorSmbUsername: String = ""
    public var destinationEditorSmbPassword: String = ""
    public var destinationEditorWebDAVURL: String = "https://nas.local:5006"
    public var destinationEditorWebDAVPath: String = "/backups"
    public var destinationEditorWebDAVUsername: String = ""
    public var destinationEditorWebDAVPassword: String = ""
    public var destinationEditorSFTPHost: String = "nas.local"
    public var destinationEditorSFTPPort: Int = 22
    public var destinationEditorSFTPUsername: String = ""
    public var destinationEditorSFTPPasswordOrKey: String = ""
    public var destinationEditorSFTPAuthModeIndex: Int = 0
    public var destinationEditorSFTPPath: String = "/var/backups/otterkeep"
    public var destinationEditorB2KeyId: String = ""
    public var destinationEditorB2AppKey: String = ""
    public var destinationEditorB2BucketName: String = ""
    public var destinationEditorB2Region: String = "us-west-004"
    public var destinationEditorB2CustomEndpoint: String = ""
    public var destinationEditorB2PathPrefix: String = "otterkeep"
    public var destinationEditorArchivePackagingEnabled: Bool = false
    public var destinationEditorArchiveCompressionLevel: Int = 3
    public var destinationEditorIsClientEncryptionEnabled: Bool = true
    public var destinationEditorIsEnabled: Bool = true
    public var destinationEditorIsTesting: Bool = false
    public var destinationEditorTestSuccessMessage: String? = nil
    public var destinationEditorTestErrorMessage: String? = nil

    // MARK: - Software Updates State
    public var isCheckingForSoftwareUpdates: Bool = false
    public var softwareUpdateStatusMessage: String? = nil
    public var softwareUpdateAvailableInfo: SoftwareUpdateInfo? = nil

    // MARK: - Photos Backup State
    public var photosConfig: PhotosBackupConfiguration
    public var isPhotosBackupRunning: Bool = false
    public var photosProgressState: PhotosBackupProgressState = PhotosBackupProgressState()
    public var lastPhotosSessionSummary: PhotosSessionSummary?
    public var photosAuthorizationStatus: PHAuthorizationStatus = .notDetermined
    public var loadedPhotosSnapshotId: String? = nil
    public var photosSnapshots: [SnapshotRecord] = []
    public var selectedPhotosSnapshotId: String?
    public var photosAssets: [PhotosAssetRecord] = []
    public var selectedPhotosAsset: PhotosAssetRecord?
    public var photosLibraryTotalCount: Int = 0
    public var isScanningPhotosLibrary: Bool = false

    // MARK: - Pre-backup Simulation (Dry-Run)
    public var isDryRunRunning: Bool = false
    public var dryRunSummary: DryRunSummary?
    public var showDryRunModal: Bool = false
    public var dryRunSelectedCategory: String = "all"

    // MARK: - Backup Inspector Modal
    public var lastSessionSummary: BackupSessionSummary?
    public var showInspectorModal: Bool = false
    public var inspectorSelectedTab: String = "summary"
    public var inspectorSearchQuery: String = ""

    // MARK: - Profile Management Dialogs
    public var showNewProfileSheet: Bool = false
    public var newProfileName: String = ""
    public var newProfileSourceURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    public var newProfileDestinationURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups")
    public var newProfileIsDestinationCustomized: Bool = false
    public var newProfileExcludePatterns: [String] = ["*.tmp", ".DS_Store", "node_modules", "DerivedData"]
    public var newProfileEnableIgnoreFiles: Bool = true
    public var newProfileRespectGitIgnore: Bool = false
    public var newProfileBackupOnVolumeMount: Bool = false
    public var newProfileAutoEjectOnCompletion: Bool = false
    public var selectedPresetTag: String? = nil

    public var showRenameProfileSheet: Bool = false
    public var renameProfileName: String = ""

    // MARK: - Cross-Snapshot Global Search State
    public var globalSearchQuery: String = ""
    public var globalSearchResults: [GlobalSearchResult] = []
    public var selectedGlobalSearchResult: GlobalSearchResult? = nil
    public var isGlobalSearching: Bool = false

    public func resetNewProfileDraft() {
        newProfileName = ""
        newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        newProfileDestinationURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups")
        newProfileIsDestinationCustomized = false
        newProfileExcludePatterns = ["*.tmp", ".DS_Store", "node_modules", "DerivedData"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = false
        newProfileBackupOnVolumeMount = false
        newProfileAutoEjectOnCompletion = false
        selectedPresetTag = nil
    }

    public func applyDeveloperPreset() {
        selectedPresetTag = "developer"
        newProfileName = "Development"
        let devURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Development")
        let projURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects")
        if FileManager.default.fileExists(atPath: devURL.path) {
            newProfileSourceURL = devURL
        } else if FileManager.default.fileExists(atPath: projURL.path) {
            newProfileSourceURL = projURL
        } else {
            newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Projects")
        }
        updateNewProfileName("Development")
        newProfileExcludePatterns = ["node_modules", ".build", "target", ".venv", "Pods", "DerivedData", ".gradle", "vendor", "*.pyc"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = true
    }

    public func applyDocumentsPreset() {
        selectedPresetTag = "documents"
        newProfileName = "Documents"
        newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        updateNewProfileName("Documents")
        newProfileExcludePatterns = ["*.tmp", "~*", "*.crdownload"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = false
    }

    public func applyCreativePreset() {
        selectedPresetTag = "creative"
        newProfileName = "Photos & Media"
        newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        updateNewProfileName("Photos & Media")
        newProfileExcludePatterns = ["*.tmp"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = false
    }

    public func updateNewProfileName(_ newName: String) {
        newProfileName = newName
        if !newProfileIsDestinationCustomized {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = trimmed.isEmpty ? "" : "_\(trimmed.replacingOccurrences(of: " ", with: "_"))"
            newProfileDestinationURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups\(suffix)")
        }
    }

    // MARK: - Snapshot Browsing & File Tree
    public var loadedProfileId: UUID? = nil
    public var loadedSnapshotId: String? = nil
    public var snapshots: [SnapshotRecord] = []
    public var selectedSnapshotId: String?
    public var snapshotFiles: [FileCatalogRecord] = []
    public var snapshotTreeNodes: [FileTreeNode] = []
    public var selectedTreeNode: FileTreeNode?
    public var selectedFile: FileCatalogRecord?

    // MARK: - File Timeline & Tree Structure
    public var restoreBrowseMode: RestoreBrowseMode = .snapshot
    public var timelineSearchQuery: String = ""
    public var timelinePaths: [String] = []
    public var timelineTreeNodes: [FileTreeNode] = []
    public var selectedTimelinePath: String?
    public var selectedPathVersions: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] = []
    public var selectedTimelineVersion: (snapshot: SnapshotRecord, file: FileCatalogRecord)?
    public var versionToRestore: (snapshot: SnapshotRecord, file: FileCatalogRecord)?

    // MARK: - Snapshot Diff & What Changed State
    public var selectedDiffTargetSnapshotId: String?
    public var selectedDiffBaseSnapshotId: String?
    public var snapshotDiffReport: SnapshotDiffReport?
    public var isLoadingDiff: Bool = false
    public var diffFilterType: DiffChangeType? = nil
    public var diffSearchQuery: String = ""
    public var showDiffSheet: Bool = false

    // MARK: - Side-by-Side Snapshot File Diff (1.5.0)
    public var showSideBySideDiffModal: Bool = false
    public var activeSideBySideDiffItem: SnapshotDiffItem? = nil
    public var activeSideBySideDiffComparison: FileComparisonResult? = nil
    public var isLoadingSideBySideDiff: Bool = false

    // MARK: - Data Integrity Scrubber State (1.5.0)
    public var isDataScrubInProgress: Bool = false
    public var scrubProgress: ScrubRunProgress? = nil

    // MARK: - Storage Capacity Forecast & Quota Alerts
    public var storageForecastReport: StorageForecastReport?
    public var isLoadingForecast: Bool = false
    public var webhookTestingStatus: (isTesting: Bool, message: String?, isSuccess: Bool) = (false, nil, false)

    // MARK: - Wi-Fi Filter Input State
    public var newAllowedWiFiSSID: String = ""
    public var newDisallowedWiFiSSID: String = ""


    // MARK: - Direct File Version History & Finder In-Place Restore

    public var showFileVersionHistoryModal: Bool = false
    public var activeVersionHistoryFile: URL? = nil
    public var activeVersionHistoryProfile: BackupProfile? = nil
    public var activeVersionHistoryRecords: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] = []
    public var isLoadingFileVersions: Bool = false
    public var selectedFileVersionHistoryRecord: (snapshot: SnapshotRecord, file: FileCatalogRecord)? = nil
    public var versionForInPlaceRestore: (snapshot: SnapshotRecord, file: FileCatalogRecord)? = nil
    public var showConfirmInPlaceRestore: Bool = false
    public var inPlaceRestoreCollisionChoice: CollisionResolution = .overwrite

    // MARK: - Volume & CoW Capability Evaluation
    public var volumeEvaluation: VolumeEvaluationResult?

    // MARK: - Quick Look
    public var quickLookURL: URL?

    public var logEntries: [LogEntry] = []
    public var alertMessage: String?
    public var showAlert: Bool = false

    // MARK: - UI Interaction State
    public var newExcludePattern: String = ""
    public var searchFilter: String = ""
    public var showRestoreDialog: Bool = false
    public var showRestoreSnapshotDialog: Bool = false
    public var snapshotToRestoreEntirely: SnapshotRecord? = nil
    public var isSnapshotRestoreInProgress: Bool = false
    public var snapshotRestoreProgress: RestoreProgressState? = nil
    public var collisionChoice: CollisionResolution = .keepBoth
    public var maxSnapshotsToKeep: Int = 5
    public var showConfirmPrune: Bool = false
    public var showConfirmRebuild: Bool = false
    public var showConfirmFullBackup: Bool = false
    public var selectedLogLevel: LogEntry.LogLevel? = nil
    public var logFilterQuery: String = ""

    // MARK: - Language, Theme & Settings State
    public internal(set) var isSystemDarkMode: Bool = false

    /// Computes the active SwiftUI color scheme, dynamically synchronizing system mode with the OS interface style.
    public var effectiveColorScheme: ColorScheme {
        switch currentTheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return isSystemDarkMode ? .dark : .light
        }
    }

    /// Evaluates the true operating system appearance setting.
    public func updateSystemDarkMode() {
        let isDark: Bool
        if let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            isDark = (match == .darkAqua)
        } else if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
            isDark = (style.caseInsensitiveCompare("Dark") == .orderedSame)
        } else {
            isDark = false
        }
        self.isSystemDarkMode = isDark
    }

    public var currentTheme: AppThemeMode = LocalizationManager.shared.currentTheme {
        didSet {
            LocalizationManager.shared.currentTheme = currentTheme
            applyThemeAppearance(currentTheme)
        }
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

    public var currentLanguage: AppLanguage = LocalizationManager.shared.currentLanguage {
        didSet {
            LocalizationManager.shared.currentLanguage = currentLanguage
            let targetName = L10n.t(.defaultProfileName, lang: currentLanguage)
            let otherName = currentLanguage == .hungarian ? "Default profile" : "Alapértelmezett profil"
            if let defaultProf = profiles.first(where: { $0.name == otherName }) {
                renameProfile(id: defaultProf.id, newName: targetName)
            }
        }
    }

    public var launchAtLoginEnabled: Bool = LaunchAtLoginManager.shared.isEnabled {
        didSet {
            LaunchAtLoginManager.shared.isEnabled = launchAtLoginEnabled
        }
    }

    public var startMinimized: Bool = LocalizationManager.shared.startMinimized {
        didSet {
            LocalizationManager.shared.startMinimized = startMinimized
        }
    }

    public var isFinderIntegrationEnabled: Bool = FinderIntegrationStore.shared.isEnabled {
        didSet {
            FinderIntegrationStore.shared.setEnabled(isFinderIntegrationEnabled)
            if isFinderIntegrationEnabled {
                refreshFinderPermissionStatus()
            }
        }
    }

    public var isDebugFileLoggingEnabled: Bool = LogManager.shared.isDebugFileLoggingEnabled {
        didSet {
            if isDebugFileLoggingEnabled {
                self.currentDebugLogFileURL = LogManager.shared.enableDebugFileLogging(persistSetting: true)
            } else {
                LogManager.shared.disableDebugFileLogging(persistSetting: true)
                self.currentDebugLogFileURL = nil
            }
        }
    }

    public var currentDebugLogFileURL: URL? = LogManager.shared.currentDebugLogFileURL

    public var finderPermissionStatus: FinderPermissionStatus?
    public var isCheckingFinderPermissions: Bool = false

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
        self.coordinator = BackupSessionCoordinator(storage: storage, database: database, retentionManager: retentionManager)
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
        self.photosConfig = PhotosProfileStore.shared.loadConfiguration()

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
