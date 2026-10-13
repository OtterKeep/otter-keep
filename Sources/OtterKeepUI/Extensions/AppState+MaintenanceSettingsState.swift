import SwiftUI
import AppKit
import Photos
import OtterKeepDatabase
import OtterKeepCore

/// Forwarding accessors exposing the maintenance, diagnostics and settings state owned by
/// ``MaintenanceSettingsStore`` on `AppState` so views keep their existing call sites.
///
/// Settings that previously carried `didSet` observers keep them in their setters here.
extension AppState {
    // MARK: - Modal Operation Feedback State
    /// Feedback of the last modal operation.
    public var activeFeedback: OperationFeedback? { get { maintenanceSettings.activeFeedback } set { maintenanceSettings.activeFeedback = newValue } }
    /// Controls presentation of the operation feedback modal.
    public var showFeedbackModal: Bool { get { maintenanceSettings.showFeedbackModal } set { maintenanceSettings.showFeedbackModal = newValue } }

    // MARK: - Software Updates State
    /// Indicates an ongoing software update check.
    public var isCheckingForSoftwareUpdates: Bool {
        get { maintenanceSettings.isCheckingForSoftwareUpdates }
        set { maintenanceSettings.isCheckingForSoftwareUpdates = newValue }
    }
    /// Status message of the last software update check.
    public var softwareUpdateStatusMessage: String? {
        get { maintenanceSettings.softwareUpdateStatusMessage }
        set { maintenanceSettings.softwareUpdateStatusMessage = newValue }
    }
    /// Metadata of an available software update.
    public var softwareUpdateAvailableInfo: SoftwareUpdateInfo? {
        get { maintenanceSettings.softwareUpdateAvailableInfo }
        set { maintenanceSettings.softwareUpdateAvailableInfo = newValue }
    }

    // MARK: - Pre-backup Simulation (Dry-Run)
    /// Indicates an ongoing dry-run simulation.
    public var isDryRunRunning: Bool { get { maintenanceSettings.isDryRunRunning } set { maintenanceSettings.isDryRunRunning = newValue } }
    /// Summary of the last dry-run simulation.
    public var dryRunSummary: DryRunSummary? { get { maintenanceSettings.dryRunSummary } set { maintenanceSettings.dryRunSummary = newValue } }
    /// Controls presentation of the dry-run modal.
    public var showDryRunModal: Bool { get { maintenanceSettings.showDryRunModal } set { maintenanceSettings.showDryRunModal = newValue } }
    /// Category filter of the dry-run modal.
    public var dryRunSelectedCategory: String {
        get { maintenanceSettings.dryRunSelectedCategory }
        set { maintenanceSettings.dryRunSelectedCategory = newValue }
    }

    // MARK: - Backup Inspector Modal
    /// Summary of the last backup session shown in the inspector.
    public var lastSessionSummary: BackupSessionSummary? {
        get { maintenanceSettings.lastSessionSummary }
        set { maintenanceSettings.lastSessionSummary = newValue }
    }
    /// Controls presentation of the backup inspector modal.
    public var showInspectorModal: Bool { get { maintenanceSettings.showInspectorModal } set { maintenanceSettings.showInspectorModal = newValue } }
    /// Active tab of the backup inspector modal.
    public var inspectorSelectedTab: String { get { maintenanceSettings.inspectorSelectedTab } set { maintenanceSettings.inspectorSelectedTab = newValue } }
    /// Search query of the backup inspector modal.
    public var inspectorSearchQuery: String { get { maintenanceSettings.inspectorSearchQuery } set { maintenanceSettings.inspectorSearchQuery = newValue } }

    // MARK: - Profile Management Dialogs
    /// Controls presentation of the new profile sheet.
    public var showNewProfileSheet: Bool { get { maintenanceSettings.showNewProfileSheet } set { maintenanceSettings.showNewProfileSheet = newValue } }
    /// Draft profile name.
    public var newProfileName: String { get { maintenanceSettings.newProfileName } set { maintenanceSettings.newProfileName = newValue } }
    /// Draft source directory.
    public var newProfileSourceURL: URL { get { maintenanceSettings.newProfileSourceURL } set { maintenanceSettings.newProfileSourceURL = newValue } }
    /// Draft destination directory.
    public var newProfileDestinationURL: URL {
        get { maintenanceSettings.newProfileDestinationURL }
        set { maintenanceSettings.newProfileDestinationURL = newValue }
    }
    /// Indicates a manually customized draft destination.
    public var newProfileIsDestinationCustomized: Bool {
        get { maintenanceSettings.newProfileIsDestinationCustomized }
        set { maintenanceSettings.newProfileIsDestinationCustomized = newValue }
    }
    /// Draft exclude patterns.
    public var newProfileExcludePatterns: [String] {
        get { maintenanceSettings.newProfileExcludePatterns }
        set { maintenanceSettings.newProfileExcludePatterns = newValue }
    }
    /// Draft switch for ignore-file support.
    public var newProfileEnableIgnoreFiles: Bool {
        get { maintenanceSettings.newProfileEnableIgnoreFiles }
        set { maintenanceSettings.newProfileEnableIgnoreFiles = newValue }
    }
    /// Draft switch for `.gitignore` support.
    public var newProfileRespectGitIgnore: Bool {
        get { maintenanceSettings.newProfileRespectGitIgnore }
        set { maintenanceSettings.newProfileRespectGitIgnore = newValue }
    }
    /// Draft switch for backup-on-volume-mount.
    public var newProfileBackupOnVolumeMount: Bool {
        get { maintenanceSettings.newProfileBackupOnVolumeMount }
        set { maintenanceSettings.newProfileBackupOnVolumeMount = newValue }
    }
    /// Draft switch for automatic volume ejection after completion.
    public var newProfileAutoEjectOnCompletion: Bool {
        get { maintenanceSettings.newProfileAutoEjectOnCompletion }
        set { maintenanceSettings.newProfileAutoEjectOnCompletion = newValue }
    }
    /// Tag of the currently applied configuration preset.
    public var selectedPresetTag: String? { get { maintenanceSettings.selectedPresetTag } set { maintenanceSettings.selectedPresetTag = newValue } }
    /// Controls presentation of the rename profile sheet.
    public var showRenameProfileSheet: Bool { get { maintenanceSettings.showRenameProfileSheet } set { maintenanceSettings.showRenameProfileSheet = newValue } }
    /// Draft name of the profile being renamed.
    public var renameProfileName: String { get { maintenanceSettings.renameProfileName } set { maintenanceSettings.renameProfileName = newValue } }

    // MARK: - Cross-Snapshot Global Search State
    /// Search query across all snapshots.
    public var globalSearchQuery: String { get { maintenanceSettings.globalSearchQuery } set { maintenanceSettings.globalSearchQuery = newValue } }
    /// Results of the cross-snapshot search.
    public var globalSearchResults: [GlobalSearchResult] {
        get { maintenanceSettings.globalSearchResults }
        set { maintenanceSettings.globalSearchResults = newValue }
    }
    /// Currently selected cross-snapshot search result.
    public var selectedGlobalSearchResult: GlobalSearchResult? {
        get { maintenanceSettings.selectedGlobalSearchResult }
        set { maintenanceSettings.selectedGlobalSearchResult = newValue }
    }
    /// Indicates an ongoing cross-snapshot search.
    public var isGlobalSearching: Bool { get { maintenanceSettings.isGlobalSearching } set { maintenanceSettings.isGlobalSearching = newValue } }

    // MARK: - Data Integrity Scrubber State (1.5.0)
    /// Indicates an ongoing data integrity scrub.
    public var isDataScrubInProgress: Bool { get { maintenanceSettings.isDataScrubInProgress } set { maintenanceSettings.isDataScrubInProgress = newValue } }
    /// Live progress of the ongoing data integrity scrub.
    public var scrubProgress: ScrubRunProgress? { get { maintenanceSettings.scrubProgress } set { maintenanceSettings.scrubProgress = newValue } }

    // MARK: - Storage Capacity Forecast & Quota Alerts
    /// Latest storage capacity forecast report.
    public var storageForecastReport: StorageForecastReport? {
        get { maintenanceSettings.storageForecastReport }
        set { maintenanceSettings.storageForecastReport = newValue }
    }
    /// Indicates an ongoing storage forecast computation.
    public var isLoadingForecast: Bool { get { maintenanceSettings.isLoadingForecast } set { maintenanceSettings.isLoadingForecast = newValue } }
    /// Status of the last webhook connectivity test.
    public var webhookTestingStatus: (isTesting: Bool, message: String?, isSuccess: Bool) {
        get { maintenanceSettings.webhookTestingStatus }
        set { maintenanceSettings.webhookTestingStatus = newValue }
    }

    // MARK: - Wi-Fi Filter Input State
    /// Draft allowed Wi-Fi SSID.
    public var newAllowedWiFiSSID: String { get { maintenanceSettings.newAllowedWiFiSSID } set { maintenanceSettings.newAllowedWiFiSSID = newValue } }
    /// Draft disallowed Wi-Fi SSID.
    public var newDisallowedWiFiSSID: String { get { maintenanceSettings.newDisallowedWiFiSSID } set { maintenanceSettings.newDisallowedWiFiSSID = newValue } }

    // MARK: - Diagnostics Log & Alert State
    /// In-memory diagnostics log entries.
    public var logEntries: [LogEntry] { get { maintenanceSettings.logEntries } set { maintenanceSettings.logEntries = newValue } }
    /// Message of the currently presented alert.
    public var alertMessage: String? { get { maintenanceSettings.alertMessage } set { maintenanceSettings.alertMessage = newValue } }
    /// Controls presentation of the global alert.
    public var showAlert: Bool { get { maintenanceSettings.showAlert } set { maintenanceSettings.showAlert = newValue } }
    /// Active log level filter.
    public var selectedLogLevel: LogEntry.LogLevel? { get { maintenanceSettings.selectedLogLevel } set { maintenanceSettings.selectedLogLevel = newValue } }
    /// Free-text filter applied to diagnostics log entries.
    public var logFilterQuery: String { get { maintenanceSettings.logFilterQuery } set { maintenanceSettings.logFilterQuery = newValue } }

    // MARK: - UI Interaction State
    /// Draft exclude pattern entered in the rules editor.
    public var newExcludePattern: String { get { maintenanceSettings.newExcludePattern } set { maintenanceSettings.newExcludePattern = newValue } }
    /// Free-text filter of the maintenance workspace.
    public var searchFilter: String { get { maintenanceSettings.searchFilter } set { maintenanceSettings.searchFilter = newValue } }
    /// Maximum number of snapshots kept by auto-pruning.
    public var maxSnapshotsToKeep: Int { get { maintenanceSettings.maxSnapshotsToKeep } set { maintenanceSettings.maxSnapshotsToKeep = newValue } }
    /// Controls presentation of the prune confirmation.
    public var showConfirmPrune: Bool { get { maintenanceSettings.showConfirmPrune } set { maintenanceSettings.showConfirmPrune = newValue } }
    /// Controls presentation of the catalog rebuild confirmation.
    public var showConfirmRebuild: Bool { get { maintenanceSettings.showConfirmRebuild } set { maintenanceSettings.showConfirmRebuild = newValue } }
    /// Controls presentation of the full backup confirmation.
    public var showConfirmFullBackup: Bool { get { maintenanceSettings.showConfirmFullBackup } set { maintenanceSettings.showConfirmFullBackup = newValue } }

    // MARK: - Language, Theme & Settings State
    /// System appearance flag mirrored from macOS.
    public internal(set) var isSystemDarkMode: Bool { get { maintenanceSettings.isSystemDarkMode } set { maintenanceSettings.isSystemDarkMode = newValue } }
    /// Selected application theme mode.
    ///
    /// The setter mirrors the previous `didSet` observer: it persists the selection and applies the
    /// matching macOS appearance to every window.
    public var currentTheme: AppThemeMode {
        get { maintenanceSettings.currentTheme }
        set {
            maintenanceSettings.currentTheme = newValue
            LocalizationManager.shared.currentTheme = newValue
            applyThemeAppearance(newValue)
        }
    }
    /// Selected application language.
    ///
    /// The setter mirrors the previous `didSet` observer: it persists the selection and renames the
    /// default profile so it matches the newly selected language.
    public var currentLanguage: AppLanguage {
        get { maintenanceSettings.currentLanguage }
        set {
            maintenanceSettings.currentLanguage = newValue
            LocalizationManager.shared.currentLanguage = newValue
            let targetName = L10n.t(.defaultProfileName, lang: newValue)
            let otherName = newValue == .hungarian ? "Default profile" : "Alapértelmezett profil"
            if let defaultProf = profiles.first(where: { $0.name == otherName }) {
                renameProfile(id: defaultProf.id, newName: targetName)
            }
        }
    }
    /// Launch-at-login registration state.
    ///
    /// The setter mirrors the previous `didSet` observer and updates the login item registration.
    public var launchAtLoginEnabled: Bool {
        get { maintenanceSettings.launchAtLoginEnabled }
        set {
            maintenanceSettings.launchAtLoginEnabled = newValue
            LaunchAtLoginManager.shared.isEnabled = newValue
        }
    }
    /// Start-minimized launch preference.
    ///
    /// The setter mirrors the previous `didSet` observer and persists the preference.
    public var startMinimized: Bool {
        get { maintenanceSettings.startMinimized }
        set {
            maintenanceSettings.startMinimized = newValue
            LocalizationManager.shared.startMinimized = newValue
        }
    }
    /// Finder integration extension state.
    ///
    /// The setter mirrors the previous `didSet` observer: it toggles the extension and re-evaluates
    /// the permission status when enabling.
    public var isFinderIntegrationEnabled: Bool {
        get { maintenanceSettings.isFinderIntegrationEnabled }
        set {
            maintenanceSettings.isFinderIntegrationEnabled = newValue
            FinderIntegrationStore.shared.setEnabled(newValue)
            if newValue {
                refreshFinderPermissionStatus()
            }
        }
    }
    /// Debug file logging state.
    ///
    /// The setter mirrors the previous `didSet` observer: it toggles the file logger and keeps the
    /// active debug log URL in sync.
    public var isDebugFileLoggingEnabled: Bool {
        get { maintenanceSettings.isDebugFileLoggingEnabled }
        set {
            maintenanceSettings.isDebugFileLoggingEnabled = newValue
            if newValue {
                currentDebugLogFileURL = LogManager.shared.enableDebugFileLogging(persistSetting: true)
            } else {
                LogManager.shared.disableDebugFileLogging(persistSetting: true)
                currentDebugLogFileURL = nil
            }
        }
    }
    /// File URL of the active debug log file, if enabled.
    public var currentDebugLogFileURL: URL? { get { maintenanceSettings.currentDebugLogFileURL } set { maintenanceSettings.currentDebugLogFileURL = newValue } }
    /// Last evaluated Finder extension permission status.
    public var finderPermissionStatus: FinderPermissionStatus? {
        get { maintenanceSettings.finderPermissionStatus }
        set { maintenanceSettings.finderPermissionStatus = newValue }
    }
    /// Indicates an ongoing Finder permission evaluation.
    public var isCheckingFinderPermissions: Bool {
        get { maintenanceSettings.isCheckingFinderPermissions }
        set { maintenanceSettings.isCheckingFinderPermissions = newValue }
    }
    /// Computes the active SwiftUI color scheme, dynamically synchronizing system mode with the OS interface style.
    public var effectiveColorScheme: ColorScheme {
        maintenanceSettings.effectiveColorScheme
    }
}
