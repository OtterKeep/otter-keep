import SwiftUI
import AppKit
import Observation
import OtterKeepDatabase
import OtterKeepCore

/// Maintenance, diagnostics and user-settings state.
///
/// Owns data-integrity scrubbing, storage forecasting, diagnostics logs and alerts, software update
/// checks, dry-run simulation, inspector/dialog/modal form state, cross-snapshot search and all
/// appearance, language and integration settings. The new-profile draft helpers and the derived
/// color scheme live here as pure logic; `AppState` exposes this state through forwarding accessors
/// so views keep their existing call sites.
///
/// Settings whose previous stored declarations carried `didSet` observers keep those observers in the
/// forwarding setters on `AppState`, because they also drive other app-wide subsystems.
@MainActor
@Observable
public final class MaintenanceSettingsStore: Sendable {
    // MARK: - Modal Operation Feedback State

    /// Feedback of the last modal operation.
    public var activeFeedback: OperationFeedback? = nil

    /// Controls presentation of the operation feedback modal.
    public var showFeedbackModal: Bool = false

    // MARK: - Software Updates State

    /// Indicates an ongoing software update check.
    public var isCheckingForSoftwareUpdates: Bool = false

    /// Status message of the last software update check.
    public var softwareUpdateStatusMessage: String? = nil

    /// Metadata of an available software update.
    public var softwareUpdateAvailableInfo: SoftwareUpdateInfo? = nil

    /// Native update checker callback (e.g. Sparkle).
    public var onCheckForUpdatesNative: (@MainActor () -> Void)? = nil

    // MARK: - Pre-backup Simulation (Dry-Run)

    /// Indicates an ongoing dry-run simulation.
    public var isDryRunRunning: Bool = false

    /// Summary of the last dry-run simulation.
    public var dryRunSummary: DryRunSummary?

    /// Controls presentation of the dry-run modal.
    public var showDryRunModal: Bool = false

    /// Category filter of the dry-run modal.
    public var dryRunSelectedCategory: String = "all"

    // MARK: - Backup Inspector Modal

    /// Summary of the last backup session shown in the inspector.
    public var lastSessionSummary: BackupSessionSummary?

    /// Controls presentation of the backup inspector modal.
    public var showInspectorModal: Bool = false

    /// Controls presentation of the global preferences modal.
    public var showPreferencesModal: Bool = false

    /// Active tab in the preferences modal sheet.
    public var activePreferencesTab: PreferencesTab = .general

    /// Controls presentation of the system logs modal.
    public var showSystemLogsModal: Bool = false

    /// Controls presentation of the tabbed profile settings modal.
    public var showProfileSettingsModal: Bool = false

    /// Controls presentation of the last backup session summary modal.
    public var showLastBackupSummaryModal: Bool = false

    /// Controls presentation of the delete profile confirmation dialog.
    public var showDeleteProfileConfirmation: Bool = false

    /// Profile queued for deletion confirmation.
    public var profilePendingDeletion: BackupProfile?

    /// Active tab of the backup inspector modal.
    public var inspectorSelectedTab: String = "summary"

    /// Search query of the backup inspector modal.
    public var inspectorSearchQuery: String = ""

    // MARK: - Profile Management Dialogs

    /// Controls presentation of the 4-step Sanctuary Onboarding Wizard modal.
    public var showOnboardingModal: Bool = false
    public var onboardingCurrentStep: Int = 0
    public var onboardingProfileName: String = ""
    public var onboardingSourceURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    public var onboardingDestinationURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups")
    public var onboardingIsContinuousMode: Bool = false
    public var onboardingEnableCanaryTraps: Bool = true
    public var onboardingHasFDAPermission: Bool = false

    /// Controls presentation of the new profile sheet.
    public var showNewProfileSheet: Bool = false

    /// Draft profile name.
    public var newProfileName: String = ""

    /// Draft source directory.
    public var newProfileSourceURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")

    /// Draft destination directory.
    public var newProfileDestinationURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups")

    /// Indicates a manually customized draft destination.
    public var newProfileIsDestinationCustomized: Bool = false

    /// Draft exclude patterns.
    public var newProfileExcludePatterns: [String] = ["*.tmp", ".DS_Store", "node_modules", "DerivedData"]

    /// Draft switch for ignore-file support.
    public var newProfileEnableIgnoreFiles: Bool = true

    /// Draft switch for `.gitignore` support.
    public var newProfileRespectGitIgnore: Bool = false

    /// Draft switch for backup-on-volume-mount.
    public var newProfileBackupOnVolumeMount: Bool = false

    /// Draft switch for automatic volume ejection after completion.
    public var newProfileAutoEjectOnCompletion: Bool = false

    /// Draft switch for continuous real-time FSEvents backup mode.
    public var newProfileIsContinuous: Bool = false

    /// Draft quiet-window debouncing seconds for continuous mode.
    public var newProfileDebouncingSeconds: Int = 30

    /// Tag of the currently applied configuration preset.
    public var selectedPresetTag: String? = nil

    /// Controls presentation of the rename profile sheet.
    public var showRenameProfileSheet: Bool = false

    /// Draft name of the profile being renamed.
    public var renameProfileName: String = ""

    // MARK: - Cross-Snapshot Global Search State

    /// Search query across all snapshots.
    public var globalSearchQuery: String = ""

    /// Results of the cross-snapshot search.
    public var globalSearchResults: [GlobalSearchResult] = []

    /// Currently selected cross-snapshot search result.
    public var selectedGlobalSearchResult: GlobalSearchResult? = nil

    /// Indicates an ongoing cross-snapshot search.
    public var isGlobalSearching: Bool = false

    // MARK: - Data Integrity Scrubber State (1.5.0)

    /// Indicates an ongoing data integrity scrub.
    public var isDataScrubInProgress: Bool = false

    /// Live progress of the ongoing data integrity scrub.
    public var scrubProgress: ScrubRunProgress? = nil

    // MARK: - Storage Capacity Forecast & Quota Alerts

    /// Latest storage capacity forecast report.
    public var storageForecastReport: StorageForecastReport?

    /// Indicates an ongoing storage forecast computation.
    public var isLoadingForecast: Bool = false

    /// Status of the last webhook connectivity test.
    public var webhookTestingStatus: (isTesting: Bool, message: String?, isSuccess: Bool) = (false, nil, false)

    // MARK: - Wi-Fi Filter Input State

    /// Draft allowed Wi-Fi SSID.
    public var newAllowedWiFiSSID: String = ""

    /// Draft disallowed Wi-Fi SSID.
    public var newDisallowedWiFiSSID: String = ""

    // MARK: - Diagnostics Log & Alert State

    /// In-memory diagnostics log entries.
    public var logEntries: [LogEntry] = []

    /// Message of the currently presented alert.
    public var alertMessage: String?

    /// Controls presentation of the global alert.
    public var showAlert: Bool = false

    /// Active log level filter.
    public var selectedLogLevel: LogEntry.LogLevel? = nil

    /// Free-text filter applied to diagnostics log entries.
    public var logFilterQuery: String = ""

    // MARK: - UI Interaction State

    /// Draft exclude pattern entered in the rules editor.
    public var newExcludePattern: String = ""

    /// Free-text filter of the maintenance workspace.
    public var searchFilter: String = ""

    /// Maximum number of snapshots kept by auto-pruning.
    public var maxSnapshotsToKeep: Int = 5

    /// Controls presentation of the prune confirmation.
    public var showConfirmPrune: Bool = false

    /// Controls presentation of the catalog rebuild confirmation.
    public var showConfirmRebuild: Bool = false

    /// Controls presentation of the full backup confirmation.
    public var showConfirmFullBackup: Bool = false

    // MARK: - Language, Theme & Settings State

    /// System appearance flag mirrored from macOS.
    public internal(set) var isSystemDarkMode: Bool = false

    /// Selected application theme mode.
    public var currentTheme: AppThemeMode = LocalizationManager.shared.currentTheme

    /// Selected application language.
    public var currentLanguage: AppLanguage = LocalizationManager.shared.currentLanguage

    /// Launch-at-login registration state.
    public var launchAtLoginEnabled: Bool = LaunchAtLoginManager.shared.isEnabled

    /// Start-minimized launch preference.
    public var startMinimized: Bool = LocalizationManager.shared.startMinimized

    /// Finder integration extension state.
    public var isFinderIntegrationEnabled: Bool = FinderIntegrationStore.shared.isEnabled

    /// Debug file logging state.
    public var isDebugFileLoggingEnabled: Bool = LogManager.shared.isDebugFileLoggingEnabled

    /// File URL of the active debug log file, if enabled.
    public var currentDebugLogFileURL: URL? = LogManager.shared.currentDebugLogFileURL

    /// Last evaluated Finder extension permission status.
    public var finderPermissionStatus: FinderPermissionStatus?

    /// Indicates an ongoing Finder permission evaluation.
    public var isCheckingFinderPermissions: Bool = false

    /// Initializes the store from the persisted system and application preferences.
    public init() {}

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

    /// Resets every field of the new-profile draft to its default value.
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
        newProfileIsContinuous = false
        newProfileDebouncingSeconds = 30
        selectedPresetTag = nil
    }

    /// Applies the developer configuration preset to the new-profile draft.
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

    /// Applies the documents configuration preset to the new-profile draft.
    public func applyDocumentsPreset() {
        selectedPresetTag = "documents"
        newProfileName = "Documents"
        newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        updateNewProfileName("Documents")
        newProfileExcludePatterns = ["*.tmp", "~*", "*.crdownload"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = false
    }

    /// Applies the creative configuration preset to the new-profile draft.
    public func applyCreativePreset() {
        selectedPresetTag = "creative"
        newProfileName = "Photos & Media"
        newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        updateNewProfileName("Photos & Media")
        newProfileExcludePatterns = ["*.tmp"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = false
    }

    /// Updates the draft profile name and derives the destination folder unless it was customized.
    public func updateNewProfileName(_ newName: String) {
        newProfileName = newName
        if !newProfileIsDestinationCustomized {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = trimmed.isEmpty ? "" : "_\(trimmed.replacingOccurrences(of: " ", with: "_"))"
            newProfileDestinationURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups\(suffix)")
        }
    }

    /// Presents an error alert with the given message.
    public func showError(_ message: String) {
        self.alertMessage = message
        self.showAlert = true
    }

    /// Presents a success alert with the given message.
    public func showSuccess(_ message: String) {
        self.alertMessage = message
        self.showAlert = true
    }
}
