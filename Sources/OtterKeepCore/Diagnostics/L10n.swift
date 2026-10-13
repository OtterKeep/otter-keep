import Foundation

/// Type-safe, extensible localization system providing compile-time verified string resources.
public enum L10n {
    /// Retrieves the localized string for a given key on the active or specified language.
    /// - Parameters:
    ///   - key: Localization key.
    ///   - lang: Optional explicit language override.
    /// - Returns: Localized text.
    public static func t(_ key: Key, lang: AppLanguage? = nil) -> String {
        let activeLang = lang ?? LocalizationManager.shared.effectiveLanguage
        if let translation = translations[activeLang]?[key] {
            return translation
        }
        // Fallback: English -> Raw key
        return translations[.english]?[key] ?? key.rawValue
    }

    /// Checks whether an explicit translation entry exists for the given key in the specified language.
    public static func hasExplicitTranslation(for key: Key, in lang: AppLanguage) -> Bool {
        guard let translation = stringTable[key] else { return false }
        let target = lang == .system ? LocalizationManager.shared.effectiveLanguage : lang
        switch target {
        case .english:
            return !translation.english.isEmpty
        case .hungarian:
            return !translation.hungarian.isEmpty
        case .system:
            return !translation.english.isEmpty
        }
    }

    /// Formats a localized string template with variadic format arguments.
    /// - Parameters:
    ///   - key: Localization key.
    ///   - args: Format arguments.
    ///   - lang: Optional explicit language override.
    /// - Returns: Formatted localized text.
    public static func format(_ key: Key, _ args: CVarArg..., lang: AppLanguage? = nil) -> String {
        let formatString = t(key, lang: lang)
        return String(format: formatString, locale: Locale.current, arguments: args)
    }

    /// Enumeration of all localized UI and CLI string keys.
    public enum Key: String, Sendable, CaseIterable {
        // MARK: - Navigation
        case navDashboard
        case navProfileRules
        case navPhotosBackup
        case navPhotosSnapshots
        case navRestore
        case navMaintenance
        case navLogs
        case navSettings

        // MARK: - General Actions & Common
        case cancel
        case create
        case save
        case delete
        case confirm
        case details
        case searchPlaceholder
        case okDone
        case unitCountFormat
        case filesCountUnit

        // MARK: - Profiles
        case defaultProfileName
        case profilesMenuTitle
        case activeProfileLabel
        case newProfileButton
        case renameProfileButton
        case deleteProfileButton
        case newProfileSheetTitle
        case newProfileSheetPrompt
        case renameProfileSheetTitle
        case renameProfileSheetPrompt
        case deleteProfileConfirmTitle
        case deleteProfileConfirmMessage
        case selectSourceFolder
        case selectDestinationFolder
        case selectFolderConfirm
        case browseButton
        case newProfileSourceDesc
        case newProfileDestinationDesc
        case newProfileNamePlaceholder
        case invalidFolderSelectionTitle
        case invalidFolderSelectionMessage

        // MARK: - Dashboard
        case dashboardHeroSubtitle
        case startBackupButton
        case backupRunningButton
        case stopBackupButton
        case backupStopping
        case backupCancelled
        case dryRunButton
        case analyzingProgress
        case sourceFolderTitle
        case destinationFolderTitle
        case changeFolderButton
        case revealInFinderButton
        case excludeRulesTitle
        case addRulePlaceholder
        case addRuleButton
        case commonRulesTitle
        case activeRulesCount
        case backupFoldersTitle
        case icloudStrategyTitle
        case lastBackupSuccess
        case lastBackupWarning
        case processedFilesSummary
        case spofBannerTitle
        case spofBannerDesc

        // MARK: - Telemetry & Progress
        case telemetryCopied
        case telemetryCloned
        case telemetrySkipped
        case telemetryErrors
        case telemetrySpeed
        case telemetryRemaining
        case phaseIdle
        case phaseScanning
        case phaseAnalyzing
        case phaseCopying
        case phaseFinalizing
        case phaseCompleted
        case phaseFailed

        // MARK: - CoW Capabilities & Badges
        case cowBadgeIntraVolume
        case cowBadgeSnapshotTarget
        case cowBadgeNonAPFS
        case cowBadgeExFAT
        case cowBadgeNTFS
        case cowBadgeNTFSReadOnly
        case cowDescIntraVolume
        case cowDescSnapshotTarget
        case cowDescNonAPFS
        case cowDescExFAT
        case cowDescNTFS
        case cowDescNTFSReadOnly
        case errNTFSTargetReadOnly
        case errDestinationReadOnly




        // MARK: - Scheduling
        case scheduleCardTitle
        case scheduleCardSubtitle
        case scheduleEnableToggle
        case scheduleFrequencyLabel
        case scheduleHourly
        case scheduleDaily
        case scheduleWeekly
        case scheduleInterval
        case scheduleIntervalMinutes
        case scheduleIntervalLabel
        case scheduleHourLabel
        case scheduleDayLabel
        case scheduleCatchUpToggle
        case scheduleCatchUpDesc
        case scheduleNextRunLabel
        case scheduleNotScheduled
        case scheduleEveryDayAt
        case scheduleEveryWeekOn
        case scheduleHourlyDesc
        case monday
        case tuesday
        case wednesday
        case thursday
        case friday
        case saturday
        case sunday

        // MARK: - Pruning / Auto-Pruning
        case autoPruningToggleTitle
        case autoPruningToggleDesc
        case autoPruningRetainCountLabel
        case autoPruningRetainFormat

        // MARK: - Settings View
        case settingsTitle
        case settingsSubtitle
        case settingsAppearanceSection
        case settingsAppearanceDesc
        case themeAuto
        case themeLight
        case themeDark
        case settingsLanguageSection
        case settingsLanguageDesc
        case settingsStartupSection
        case settingsLaunchAtLoginToggle
        case settingsLaunchAtLoginDesc
        case settingsStartMinimizedToggle
        case settingsStartMinimizedDesc
        case settingsStorageSection
        case settingsProfilesPathLabel
        case settingsLogsPathLabel
        case settingsOpenFolder
        case settingsAboutSection
        case settingsVersionLabel
        case settingsEngineDesc
        case settingsProfilesSection
        case settingsProfilesSectionDesc
        case profileMetadataSectionTitle
        case profileMetadataSectionDesc
        case settingsCopyUUID
        case settingsUUIDCopied
        case settingsActiveBadge
        case settingsDebugLoggingTitle
        case settingsDebugLoggingDesc
        case settingsDebugLoggingToggle
        case settingsDebugLoggingActive
        case settingsDebugLoggingInactive
        case settingsDebugLoggingPathLabel
        case settingsDebugLoggingPrivacyNotice
        case settingsDebugOpenLogsFolder
        case settingsDebugCopyPath
        case settingsDebugCopySuccess
        case cliDebugActiveNotice
        case cliDebugSavedNotice
        case cliLogsPathLabel
        case cliNoLogsFound
        case cliDebugLoggingEnabled
        case cliDebugLoggingDisabled

        // MARK: - Menubar
        case menuBarStatusIdle
        case menuBarStatusRunning
        case menuBarTriggerBackup
        case menuBarBackupAll
        case menuBarBackupProfile
        case menuBarProfilesTitle
        case menuBarStorageGlance
        case menuBarQuickTheme
        case menuBarOpenLogs
        case menuBarOpenSettings
        case menuBarOpenApp
        case menuBarQuit
        case menuBarNextRun
        case menuBarLastRun

        // MARK: - Inspector Modal
        case inspectorTitle
        case inspectorSubtitle
        case inspectorTabSummary
        case inspectorTabSkipped
        case inspectorTabErrors
        case inspectorCloseButton
        case inspectorOpenLogsButton
        case inspectorOperationalParams
        case inspectorDuration
        case inspectorAverageSpeed
        case inspectorTotalScanned
        case inspectorInProgressNotice
        case inspectorDataIntegrityTitle
        case inspectorDataIntegrityDesc
        case inspectorNoErrorsNotice
        case inspectorPermissionWarningTitle
        case inspectorPermissionWarningDesc
        case inspectorFullDiskAccessButton

        // MARK: - Restore & Tree Explorer
        case restoreExplorerTitle
        case restoreExplorerSubtitle
        case restoreSnapshotMode
        case restoreTimelineMode
        case previewSpaceButton
        case snapshotsCountTitle
        case noSnapshotsAvailable
        case noSnapshotsAvailableDesc
        case snapshotFilesCount
        case noMatchingFilesInSnapshot
        case noMatchingFilesInSnapshotDesc
        case selectedFileLabel
        case selectFileToRestorePrompt
        case searchFileTitle
        case searchFilePlaceholder
        case searchTreePlaceholder
        case noMatchingFilesFound
        case noMatchingFilesFoundDesc
        case versionsCountLabel
        case timelineSelectPrompt
        case fileSizeLabel
        case modificationDateLabel
        case sha256IntegrityLabel
        case restoreThisVersionButton
        case restoreSheetTitle
        case restoreItemLabel
        case sourceSnapshotLabel
        case collisionResolutionLabel
        case collisionKeepBoth
        case collisionOverwrite
        case collisionSkip
        case restoreToFolderButton
        case restoreSuccessMessage
        case restoreChoosePrompt
        case restoreRootFolder
        case restoreItemsCountFormat

        // MARK: - Full Snapshot Restore
        case restoreEntireSnapshotButton
        case restoreEntireSnapshotTitle
        case restoreEntireSnapshotConfirmFormat
        case restoreEntireSnapshotSuccessFormat
        case cliCmdRestoreEntireSnapshot
        case cliOptionCollision

        // MARK: - Timeline State Badges
        case timelineInitialVersion
        case timelineInitialCreated
        case timelineModifiedContent
        case timelineModifiedMeta
        case timelineUnmodifiedCoW

        // MARK: - Maintenance & Flattening
        case maintenanceTitle
        case maintenanceSubtitle
        case maintenanceTotalSnapshots
        case maintenanceTotalBackupSize
        case maintenanceConsolidationTitle
        case maintenanceConsolidationDesc
        case maintenanceKeepSnapshotsLabel
        case maintenancePruneButton
        case maintenancePruneConfirmTitle
        case maintenancePruneConfirmMessage
        case maintenancePruneConfirmAction
        case maintenancePruneSuccessMessage
        case maintenanceRecoveryTitle
        case maintenanceRecoveryDesc
        case maintenanceRebuildButton
        case maintenanceRebuildConfirmTitle
        case maintenanceRebuildConfirmMessage
        case maintenanceRebuildConfirmAction
        case maintenanceRebuildSuccessMessage

        // MARK: - Dry Run Modal
        case dryRunTitle
        case dryRunEstimatedStorage
        case dryRunCoWGrowth
        case dryRunTabAll
        case dryRunTabAdded
        case dryRunTabModified
        case dryRunTabDeleted
        case dryRunNoChangesInTab

        // MARK: - Diagnostic Logs
        case logsTitle
        case logsSubtitle
        case exportLogsButton
        case logAllLevels
        case logSearchPlaceholder
        case logEmptyTitle
        case logEmptyDesc
        case logExportSuccess
        case logExportError

        // MARK: - iCloud Strategies
        case icloudStrategyDownloadAndEvict
        case icloudStrategyDownloadAndEvictDesc
        case icloudStrategyMetadataOnly
        case icloudStrategyMetadataOnlyDesc

        // MARK: - Hash & Full Backup
        case hashModeMetadataOnly
        case hashModeSmartHash
        case hashModeThoroughSampling
        case backupTypeIncremental
        case backupTypeFull
        case startFullBackupButton
        case confirmFullBackupTitle
        case confirmFullBackupMessage
        case confirmFullBackupAction
        case cliCmdBackupFull

        // MARK: - Photos Backup
        case photosStructureDateHierarchy
        case photosStructureAlbumHierarchy
        case photosStructureFlat
        case photosBackupHeroTitle
        case photosBackupHeroSubtitle
        case photosStatusAuthorized
        case photosStatusNotAuthorized
        case photosStatusLimited
        case photosRequestPermissionButton
        case photosCardLibraryStatus
        case photosCardLibraryTotal
        case photosCardLibraryICloud
        case photosCardLibraryLocal
        case photosCardSettings
        case photosExportStructureLabel
        case photosIncludeEditedToggle
        case photosIncludeEditedDesc
        case photosIncludeLivePhotoVideosToggle
        case photosIncludeLivePhotoVideosDesc
        case photosGenerateXMPToggle
        case photosGenerateXMPDesc
        case photosStartBackupButton
        case photosBackupRunningButton
        case photosBufferStatus
        case photosSavedByReflink
        case photosRestorationTitle
        case photosRestorationSubtitle

        // MARK: - Refinements & Global UI
        case sidebarSectionFolders
        case sidebarSectionPhotos
        case sidebarSectionSystem
        case sidebarStatusReady
        case sidebarStatusRunning
        case noProfileSelectedTitle
        case noProfileSelectedDesc
        case rulesProfileSubtitleFormat
        case rulesConfigOnDashboardNotice
        case commonRulesLabel
        case noActiveRulesNotice
        case scheduleAndRetentionHeader
        case photosAuthRequiredDesc
        case photosBackupCardTitle
        case photosBackupCardSubtitle
        case photosConfigCardTitle
        case photosDownloadedClonedFormat
        case quickStatsSnapshotsTitle
        case quickStatsNextRunTitle
        case quickStatsActiveRulesTitle
        case quickStatsExcludeRulesCountFormat
        case sessionSummaryStatsFormat
        case interval15m
        case interval30m
        case interval1h
        case interval2h
        case interval4h
        case interval8h

        // MARK: - CLI Specifics
        case cliDescription
        case cliUsage
        case cliCommandsHeader
        case cliCmdBackup
        case cliCmdBackupProfile
        case cliCmdBackupDryRun
        case cliCmdStatus
        case cliCmdProfileList
        case cliCmdProfileCreate
        case cliCmdProfileName
        case cliCmdProfileSource
        case cliCmdProfileDest
        case cliCmdSnapshotsList
        case cliCmdRestore
        case cliCmdRestoreProfile
        case cliCmdRestoreSnapshot
        case cliCmdRestoreFile
        case cliCmdRestoreTarget
        case cliCmdLogs
        case cliCmdLogsLimit
        case cliCmdScheduleCheck
        case cliExamplesHeader
        case cliUnknownCommand
        case cliNoProfiles
        case cliProfileNotFound
        case cliMissingParams
        case cliProfileCreated
        case cliProfileDeleted
        case cliProfileSaveError
        case cliProfileDeleteError
        case cliLastProfileError
        case cliUnknownSubcommand
        case cliDryRunStarting
        case cliDryRunFinished
        case cliDryRunError
        case cliBackupStarting
        case cliBackupFinished
        case cliBackupError
        case cliSystemStatus
        case cliProfilesCountFormat
        case cliLastRunFormat
        case cliNeverRun
        case cliScheduleCheckStarting
        case cliScheduleCheckDone
        case cliDiskWaitNotice

        // MARK: - Finder Integration & In-Place Version History
        case finderContextMenuBrowseVersions
        case fileVersionsHistoryTitle
        case fileVersionsHistorySubtitle
        case confirmRestoreTitle
        case confirmRestoreMessage
        case confirmRestoreButton
        case confirmRestoreKeepBoth
        case confirmRestoreOverwrite
        case noVersionsFoundForFile
        case fileNotUnderAnyProfile
        case finderExtensionSettingsTitle
        case finderExtensionSettingsDesc
        case finderExtensionToggle
        case finderExtensionActive
        case finderExtensionDisabled
        case finderExtensionToggleDesc
        case finderExtensionMonitoredFolders
        case finderExtensionEnableHint
        case finderExtensionPermissionCheck
        case finderExtensionNotEnabledSystem
        case finderExtensionInaccessibleFolders
        case finderExtensionOpenSettings
        case finderExtensionOpenFDA
        case finderExtensionRestartFinder
        case finderExtensionAllPermissionsGranted
        case refreshStatus
        case cliCmdFileHistory
        case cliCmdFileHistoryPath
        case cliCmdFileHistoryGui

        // MARK: - Modern UI Columns & Settings Additions
        case columnDate
        case columnSize
        case columnType
        case settingsPhotosConfigTitle
        case remainingSecondsFormat

        // MARK: - Safety & System Notifications
        case spofWarningFormat
        case notifBackupCompletedTitleFormat
        case notifBackupCompletedSuccessFormat
        case notifBackupCompletedWarningFormat
        case notifBackupFailedTitleFormat
        case notifBackupFailedBodyFormat
        case notifStaleBackupTitleFormat
        case notifStaleBackupBodyFormat
        case notifBitRotTitle
        case notifBitRotBodyFormat
        // MARK: - 3-2-1 Rule, Remote Destinations & Backup Copy Job
        case copyJobTriggerOnPrimary
        case copyJobTriggerScheduled
        case copyJobTriggerManual
        case copyJobPolicyUnmetered
        case copyJobPolicyAny
        case remoteDestinationsTitle
        case remoteS3Title
        case remoteSMBTitle
        case rule321StatusCompliant
        case rule321StatusPartial
        case rule321StatusLocalOnly
        case rule321CopiesFormat
        case rule321MediaTypesFormat
        case rule321OffsiteFormat
        case commonYes
        case commonNo
        case smartThrottlingTitle
        case smartThrottlingDesc
        case rule321Title
        case rule321Desc
        case rule321BadgeLocal
        case rule321BadgeRemote
        case rule321BadgeCloud
        case copyJobMasterToggleTitle
        case copyJobMasterToggleDesc
        case copyJobTriggerLabel
        case copyJobNetworkPolicyLabel
        case copyJobThrottlingUnlimited
        case copyJobThrottlingGentle
        case copyJobThrottlingRecommended
        case copyJobThrottlingFast
        case copyJobThrottlingHigh
        case addRemoteDestinationButton
        case noRemoteDestinationsNotice
        case addRemoteDestinationPrompt
        case editRemoteDestination
        case deleteRemoteDestination
        case remoteDestEditorAddTitle
        case remoteDestEditorEditTitle
        case remoteDestEditorSubtitle
        case remoteDestEditorNameLabel
        case remoteDestEditorNamePlaceholder
        case remoteDestEditorTypeLabel
        case remoteDestEditorTypeS3
        case remoteDestEditorTypeSMB
        case remoteDestEditorS3SettingsTitle
        case remoteDestEditorPresetsLabel
        case remoteDestEditorEndpointLabel
        case remoteDestEditorEndpointPlaceholder
        case remoteDestEditorBucketLabel
        case remoteDestEditorBucketPlaceholder
        case remoteDestEditorRegionLabel
        case remoteDestEditorRegionPlaceholder
        case remoteDestEditorPrefixLabel
        case remoteDestEditorPrefixPlaceholder
        case remoteDestEditorAccessKeyLabel
        case remoteDestEditorAccessKeyPlaceholder
        case remoteDestEditorSecretKeyLabel
        case remoteDestEditorSecretKeyPlaceholder
        case remoteDestEditorForcePathStyle
        case remoteDestEditorSMBSettingsTitle
        case remoteDestEditorSMBShareLabel
        case remoteDestEditorSMBSharePlaceholder
        case remoteDestEditorSMBSubfolderLabel
        case remoteDestEditorSMBSubfolderPlaceholder
        case remoteDestEditorSMBUsernameLabel
        case remoteDestEditorSMBUsernamePlaceholder
        case remoteDestEditorSMBPasswordLabel
        case remoteDestEditorSMBPasswordPlaceholder
        case remoteDestEditorEncryptionTitle
        case remoteDestEditorEncryptionDesc
        case remoteDestEditorEnabledToggle
        case remoteDestEditorTestButton
        case remoteDestEditorTesting
        case remoteDestEditorAddButton
        case runReplicationButton
        case replicatingProgress
        case testConnectionSuccessS3Format
        case testConnectionSuccessSMBFormat
        case testConnectionNoNetwork
        case testConnectionInvalidSMBURL
        case testConnectionMissingSMBHost
        case s3ConnectionErrorFormat

        // MARK: - Notifications & Modern UI
        case notifMissedBackupTitle
        case notifMissedBackupBodyFormat
        case notifPhotosCompletedTitle
        case notifPhotosCompletedBodyFormat
        case notifPhotosFailedTitle
        case notifRestoreCompletedTitle
        case notifRestoreCompletedBodyFormat
        case notifRestoreFailedTitle
        case clearLogsButton

        // MARK: - Modern UI & Unified Workspace Tabs
        case tabOverview
        case tabTimeMachine
        case tabRulesAndMaintenance
        case tabPhotosSync
        case tabPhotosSnapshots
        case pipelineSourceLabel
        case pipelineEngineLabel
        case pipelineTargetLabel
        case storageBackupsLabel
        case storageOtherLabel
        case storageFreeLabel
        case statusReady
        case statusRunning
        case statusIdle
        case quickBackupAction
        case quickDryRunAction

        // MARK: - Error Handling & Actionable Guidance
        case errProfileAlreadyLocked
        case errPermissionDeniedTitle
        case errPermissionDeniedMessage
        case errPermissionDeniedRemediation
        case errNotEnoughSpaceTitle
        case errNotEnoughSpaceMessage
        case errNotEnoughSpaceRemediation
        case errItemNotFoundTitle
        case errItemNotFoundMessage
        case errItemNotFoundRemediation
        case errCloneFailedTitle
        case errCloneFailedRemediation
        case errDatabaseTitle
        case errDatabaseRemediation
        case errGenericTitle
        case errDestinationUnreachable

        // MARK: - Units & UI Labels
        case itemCountUnit
        case assetsCountUnit
        case snapshotsCountUnit
        case itemCountUnitFormat
        case assetsCountUnitFormat
        case uuidLabel
        case apfsCowBadge

        // MARK: - Enhanced System Notifications
        case notifLowDiskSpaceTitle
        case notifLowDiskSpaceBodyFormat
        case notifTCCPermissionTitle
        case notifTCCPermissionBodyFormat
        case notifDestinationDisconnectedTitle
        case notifDestinationDisconnectedBodyFormat
        case notifPruningCompletedTitle
        case notifPruningCompletedBodyFormat

        // MARK: - CLI Subcommands & Options
        case cliCmdPhotos
        case cliCmdPrune
        case cliCmdDaemon
        case cliCmdDoctor
        case cliOptDebug
        case cliOptVersion
        case cliOptLang
        case cliOptHelp
        case cliCmdLogsPath
        case cliCmdLogsList
        case cliCmdLogsEnable
        case cliCmdLogsDisable
        case cliCmdScrubDesc

        // MARK: - v1.5.0 Sprint Keys
        case notifVolumeMountTriggerTitle
        case notifVolumeMountTriggerBodyFormat
        case presetDeveloper
        case presetDeveloperDesc
        case presetDocuments
        case presetDocumentsDesc
        case presetCreative
        case presetCreativeDesc
        case enableIgnoreFilesTitle
        case enableIgnoreFilesDesc
        case respectGitIgnoreTitle
        case respectGitIgnoreDesc
        case backupOnVolumeMountTitle
        case backupOnVolumeMountDesc
        case autoEjectOnCompletionTitle
        case autoEjectOnCompletionDesc
        case searchAllSnapshots
        case searchAllSnapshotsTitle
        case searchAllSnapshotsDesc
        case searchAllSnapshotsEmpty
        case searchAcrossSnapshotsMode
        case permissionStatusTitle
        case permissionFDAGranted
        case permissionFDAMissing
        case permissionFinderActive
        case permissionFinderInactive
        case permissionOpenSettings
        case profilePresetsSection
        case enableIgnoreFilesToggle
        case respectGitIgnoreToggle
        case backupOnVolumeMountToggle
        case autoEjectOnCompletionToggle
        case driveAutomationHeader

        // MARK: - v1.6.0 Sprint Keys
        // Snapshot Diff
        case restoreDiffMode
        case diffCompareWithLabel
        case diffTargetSnapshotLabel
        case diffBaseSnapshotLabel
        case diffPreviousSnapshot
        case diffInitialSnapshot
        case diffTabAll
        case diffTabAdded
        case diffTabModified
        case diffTabDeleted
        case diffNoChanges
        case diffNetChange
        case diffCompareAction

        // Wi-Fi & Hotspot
        case wifiSectionTitle
        case wifiSectionDesc
        case wifiPauseOnMeteredToggle
        case wifiPauseOnMeteredDesc
        case wifiAllowedSSIDsLabel
        case wifiDisallowedSSIDsLabel
        case wifiAddCurrentButton
        case wifiNoActiveNetwork
        case wifiAllNetworksAllowed

        // Webhook Remote Monitoring
        case webhookSectionTitle
        case webhookSectionDesc
        case webhookMasterToggle
        case webhookServiceTypeLabel
        case webhookUrlLabel
        case webhookUrlPlaceholder
        case webhookTokenLabel
        case webhookTokenPlaceholder
        case webhookTargetLabel
        case webhookTargetPlaceholder
        case webhookNotifyOnSuccess
        case webhookNotifyOnWarning
        case webhookNotifyOnFailure
        case webhookTestButton
        case webhookTestSuccess
        case webhookTestFailedFormat

        // Storage Forecast & Quota
        case forecastSectionTitle
        case forecastSectionDesc
        case forecastDailyGrowthLabel
        case forecastDaysRemainingFormat
        case forecastSufficientSpace
        case forecastDiskFullNow
        case forecastFullDatePrefix
        case forecastQuotaWarningLabel
        case forecastQuotaAlertToggle
        case forecastQuotaExceededBanner
        case unitDay
        case wifiAllowedPlaceholder
        case wifiDisallowedPlaceholder
        case copyRelativePathAction
        case copySnapshotIdAction

        // MARK: - v1.7.0: Ransomware & Rate-of-Change Guard
        case ransomwareSectionTitle
        case ransomwareSectionDesc
        case ransomwareGuardToggle
        case ransomwareMaxChangePercentLabel
        case ransomwareMaxDeletedCountLabel
        case ransomwareDetectExtensionsToggle
        case ransomwareAbortToggle
        case ransomwareThresholdPercentFormat
        case ransomwareThresholdCountFormat
        case notifRansomwareAlertTitle
        case notifRansomwareAlertBodyFormat

        // MARK: - v1.7.0: Archive Packaging
        case archivePackagingSectionTitle
        case archivePackagingToggle
        case archivePackagingToggleDesc
        case archiveCompressionLevelLabel
        case archiveCompressionLevelFormat
        case archiveFormatZstd
        case archiveFormatGzip

        // MARK: - v1.7.0: Software Updates
        case settingsUpdatesSection
        case settingsUpdatesDesc
        case settingsAutoUpdateToggle
        case settingsCheckForUpdatesButton
        case settingsCurrentVersionFormat
        case settingsUpdateStatusChecking
        case settingsUpdateStatusUpToDate
        case settingsUpdateStatusAvailableFormat
        case settingsUpdateStatusFailedFormat
        case notifUpdateAvailableTitle
        case notifUpdateAvailableBodyFormat

        // MARK: - v1.7.0: WebDAV & SFTP Storage Providers
        case remoteDestEditorTypeWebDAV
        case remoteDestEditorTypeSFTP
        case remoteDestEditorWebDAVSettingsTitle
        case remoteDestEditorWebDAVURLLabel
        case remoteDestEditorWebDAVURLPlaceholder
        case remoteDestEditorWebDAVPathLabel
        case remoteDestEditorWebDAVPathPlaceholder
        case remoteDestEditorWebDAVUsernameLabel
        case remoteDestEditorWebDAVUsernamePlaceholder
        case remoteDestEditorWebDAVPasswordLabel
        case remoteDestEditorWebDAVPasswordPlaceholder
        case remoteDestEditorSFTPSettingsTitle
        case remoteDestEditorSFTPHostLabel
        case remoteDestEditorSFTPHostPlaceholder
        case remoteDestEditorSFTPPortLabel
        case remoteDestEditorSFTPUsernameLabel
        case remoteDestEditorSFTPUsernamePlaceholder
        case remoteDestEditorSFTPPasswordLabel
        case remoteDestEditorSFTPPasswordPlaceholder
        case remoteDestEditorSFTPPathLabel
        case remoteDestEditorSFTPPathPlaceholder
        case testConnectionSuccessWebDAVFormat
        case testConnectionSuccessSFTPFormat
        case testConnectionFailedFormat
        case remoteDestEditorSFTPAuthMethodLabel
        case remoteDestEditorSFTPAuthPassword
        case remoteDestEditorSFTPAuthKey
        case remoteDestEditorSFTPBrowseKeyButton
        case remoteDestEditorSFTPSelectKeyTitle
        case settingsDownloadInBrowser

        // MARK: - About Window & Brand Lore (v1.0.0 Production Release)
        case aboutWindowTitle
        case aboutTagline
        case aboutLoreTitle
        case aboutLoreStory
        case aboutReleaseHighlightsTitle
        case aboutHighlight1
        case aboutHighlight2
        case aboutHighlight3
        case aboutHighlight4
        case aboutHighlight5
        case aboutVersionInfoFormat
        case aboutCopyright
        case aboutArchitectureTag
        case aboutLinksTitle
        case aboutWebsiteButton
        case aboutDocumentationButton
        case aboutReleaseNotesButton
        case aboutCloseButton

        // MARK: - Modern UI Tooltips & Feature Badges
        case tooltipStartBackup
        case tooltipDryRun
        case tooltipStopBackup
        case tooltipApfsCow
        case tooltip321Rule
        case tooltipRansomwareShield
        case tooltipICloudEviction
        case tooltipStorageForecast
        case tooltipVolumeMount
        case tooltipAutoEject
        case tooltipFinderSync
        case tooltipWebhookAlerts
        case tooltipZstdPackaging
        case tooltipQuickLook

        // MARK: - Actionable Guidance & Permission Errors
        case errFDAInstructionTitle
        case errFDAInstructionDesc
        case errDiskFullRemediationDesc
        case errRemoteUnreachableRemediationDesc
        case errPhotosNotAuthorizedTitle
        case errPhotosNotAuthorizedDesc

        // MARK: - Menu Bar Commands & Configuration Archive
        case menuFile
        case menuBackupActions
        case menuView
        case menuWindow
        case menuHelp
        case menuCheckForUpdates
        case menuPreferences
        case menuNewProfile
        case menuRenameProfile
        case menuExportConfig
        case menuImportConfig
        case menuCloseWindow
        case menuRunBackupSelected
        case menuRunAllBackups
        case menuRunPhotosBackup
        case menuDryRunBackup
        case menuCancelBackup
        case menuBackupInspector
        case menuViewOverview
        case menuViewTimeMachine
        case menuViewRulesMaintenance
        case menuViewPhotos
        case menuViewLogs
        case menuToggleTheme
        case menuRefreshData
        case menuMainWindow
        case menuDocumentation
        case menuReleaseNotes
        case menuRevealLogs
        case menuReportIssue
        case exportConfigTitle
        case exportConfigSuccessMessage
        case exportConfigErrorMessage
        case importConfigTitle
        case importConfigSuccessMessage
        case importConfigErrorMessage
        case importConfigInvalidFile
        case importConfigConfirmTitle
        case importConfigConfirmMessage

        // MARK: - Operation Feedback & Profile Lockout (1.3.1)
        case feedbackSuccessTitle
        case feedbackSuccessMessage
        case feedbackViewDetails
        case feedbackViewLogs
        case feedbackExternalDriveMissingTitle
        case feedbackExternalDriveMissingMessage
        case feedbackExternalDriveMissingAdvice
        case feedbackSourceFolderMissingTitle
        case feedbackSourceFolderMissingMessage
        case feedbackSourceFolderMissingAdvice
        case feedbackDiskFullTitle
        case feedbackDiskFullMessage
        case feedbackDiskFullAdvice
        case feedbackPermissionDeniedTitle
        case feedbackPermissionDeniedMessage
        case feedbackPermissionDeniedAdvice
        case feedbackGeneralErrorTitle
        case feedbackGeneralErrorAdvice
        case profileLockedBannerTitle
        case profileLockedBannerMessage

        // MARK: - Restore & Maintenance (1.4.0)
        case restoredSuffixFormat
        case feedbackRestoreSuccessTitle
        case feedbackRestoreSuccessMessage
        case feedbackRestoreFailedTitle
        case feedbackRestoreFailedMessage

        // MARK: - Version 1.5.0 Features
        case diffSideBySideTitle
        case diffSideBySideCompare
        case diffSideBySideSnapshotA
        case diffSideBySideSnapshotB
        case diffBinaryFileNotice
        case diffIdenticalFiles
        case diffLinesAddedFormat
        case diffLinesRemovedFormat
        case wormLockTitle
        case wormLockDescription
        case wormLockDurationDays
        case wormLockedBadge
        case wormLockedUntilFormat
        case wormLockProtectionNotice
        case destTypeBackblazeB2
        case b2KeyId
        case b2ApplicationKey
        case b2BucketName
        case b2Region
        case b2CustomEndpoint
        case scrubberTitle
        case scrubberDescription
        case scrubbingInProgress
        case scrubberCorruptedAlertTitle
        case scrubberCorruptedAlertMessage
        case parallelMultiDestTitle
        case parallelMultiDestDescription
        case parallelReplicationQueuedNotice
        case verifySnapshotIntegrityButton
        case verifySnapshotIntegrityTitle
        case verifySnapshotIntegrityDesc
        case verifySnapshotIntegrityTooltip
        case scrubSuccessTitle
        case scrubSuccessMessage
        case scrubCorruptedTitle
        case scrubCorruptedMessage

        // MARK: - v1.6.0: Sanctuary Experience & Profile Status
        case sanctuaryHeroTitle
        case sanctuaryHeroSubtitleFormat
        case sanctuaryNeverBackedUp
        case sanctuaryNeverBackedUpAction
        case profileStatusIdleNoBackups
        case profileStatusLastBackupFormat
        case profileStatusSnapshotsFormat
        case menuBarReplicationRunning
        case menuBarMoreProfilesFormat
        case settingsFdaActiveSubtitle
        case settingsFdaRequiredSubtitle
        case settingsFinderActiveSubtitle
        case settingsFinderInactiveSubtitle
        case quickLookKeyboardHint
        case daysCountUnitFormat

        // MARK: - v1.6.0: Dynamic Sanctuary Mood & Profile Rules Redesign
        case sanctuaryHeroWarningTitle
        case sanctuaryHeroDangerTitle
        case profileSubTabRules
        case profileSubTabAutomation
        case profileSubTabMaintenance

        // MARK: - v1.7.0: GUI UX Polish
        case compressionFast
        case compressionRecommended
        case compressionMaximum
        case pathPrefixLabel
        case protocolBadgeS3
        case protocolBadgeSMB
        case protocolBadgeWebDAV
        case protocolBadgeSFTP
        case ransomwareAutoPauseBadge

        // MARK: - v1.7.0: MenuBar Polish
        case menuBarTimeMachine
        case menuBarEjectVolume
        case destinationEjectedSuccessFormat
        case menuBarCheckUpdates
        case menuBarSimulateDryRun
        case menuBarRevealDestination
        case menuBarFullBackup
        case menuBarOpenRules
        case menuBarExternalVolumeDisconnected
        case menuBarTargetVolumeLabel
        case errBackupInProgress

        // MARK: - 2.0.0 UI/UX Modernization
        case profileSettingsTitle
        case profileSettingsButton
        case lastBackupResultTitle
        case lastBackupResultSubtitle
        case tabGeneral
        case tabFinderIntegration
        case tabStorageAndDb
        case tabDiagnosticsAndUpdates
        case tabAbout
        case menuSystemLogs
        case welcomeSanctuaryTitle
        case welcomeSanctuarySubtitle
        case createFirstProfileButton
    }


    // MARK: - Translation Dictionaries

    /// Language-keyed lookup derived from ``stringTable``; every key carries both languages.
    private static let translations: [AppLanguage: [Key: String]] = {
        var english: [Key: String] = [:]
        var hungarian: [Key: String] = [:]
        english.reserveCapacity(stringTable.count)
        hungarian.reserveCapacity(stringTable.count)
        for (key, translation) in stringTable {
            english[key] = translation.english
            hungarian[key] = translation.hungarian
        }
        return [.hungarian: hungarian, .english: english]
    }()

}
