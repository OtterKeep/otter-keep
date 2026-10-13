import Foundation
import OtterKeepApplication

/// Strategy for handling dataless/ubiquitous iCloud Drive items during backups.
public enum ICloudBackupStrategy: String, Codable, Sendable, CaseIterable {
    /// Triggers download of dataless cloud files, backs them up locally, and immediately evicts them to free disk space.
    case downloadAndEvict = "downloadAndEvict"
    /// Saves empty placeholder files with extended metadata attributes to conserve bandwidth and storage.
    case metadataOnly = "metadataOnly"

    /// Corresponding localization key for user interface rendering.
    public var localizationKey: L10n.Key {
        switch self {
        case .downloadAndEvict:
            return .icloudStrategyDownloadAndEvict
        case .metadataOnly:
            return .icloudStrategyMetadataOnly
        }
    }

    /// Localized display title of the strategy.
    public var localizedTitle: String {
        L10n.t(localizationKey)
    }

    /// Localized descriptive explanation of the strategy.
    public var localizedDescription: String {
        switch self {
        case .downloadAndEvict:
            return L10n.t(.icloudStrategyDownloadAndEvictDesc)
        case .metadataOnly:
            return L10n.t(.icloudStrategyMetadataOnlyDesc)
        }
    }
}

/// Strategy for cryptographic / fast hash-based change detection during incremental scans.
public enum HashVerificationMode: String, Codable, Sendable, CaseIterable {
    /// Relies strictly on filesystem modification time (mtime) and file size (fastest).
    case metadataOnly = "metadataOnly"
    /// Evaluates mtime + size, but verifies source content hash when mtime differs to prevent false positive copies (recommended).
    case smartHash = "smartHash"
    /// Evaluates mtime + size and performs fast sampling hash integrity check on identical sizes.
    case thoroughSampling = "thoroughSampling"

    /// Localized display title.
    public var localizedTitle: String {
        switch self {
        case .metadataOnly:
            return L10n.t(.hashModeMetadataOnly)
        case .smartHash:
            return L10n.t(.hashModeSmartHash)
        case .thoroughSampling:
            return L10n.t(.hashModeThoroughSampling)
        }
    }
}

/// Grandfather-Father-Son (GFS) snapshot retention policy configuration.
public struct PruningPolicy: Codable, Sendable, Equatable {
    /// Indicates whether automatic post-backup retention pruning is enabled.
    public var isAutoPruningEnabled: Bool
    /// Maximum number of recent snapshots to retain.
    public var maxSnapshotsToKeep: Int?
    /// Number of days for which daily snapshots are preserved in the GFS rotation.
    public var keepDailyDays: Int?

    /// Initializes a `PruningPolicy` configuration.
    /// - Parameters:
    ///   - isAutoPruningEnabled: True to run pruning automatically after backup.
    ///   - maxSnapshotsToKeep: Maximum snapshot limit cap.
    ///   - keepDailyDays: Number of daily snapshots to preserve.
    public init(
        isAutoPruningEnabled: Bool = false,
        maxSnapshotsToKeep: Int? = 5,
        keepDailyDays: Int? = 30
    ) {
        self.isAutoPruningEnabled = isAutoPruningEnabled
        self.maxSnapshotsToKeep = maxSnapshotsToKeep
        self.keepDailyDays = keepDailyDays
    }

    enum CodingKeys: String, CodingKey {
        case isAutoPruningEnabled, maxSnapshotsToKeep, keepDailyDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isAutoPruningEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAutoPruningEnabled) ?? false
        self.maxSnapshotsToKeep = try container.decodeIfPresent(Int.self, forKey: .maxSnapshotsToKeep) ?? 5
        self.keepDailyDays = try container.decodeIfPresent(Int.self, forKey: .keepDailyDays) ?? 30
    }
}

/// Frequency intervals supported by the automatic backup scheduler.
public enum ScheduleFrequency: String, Codable, Sendable, CaseIterable {
    /// Executes every hour automatically.
    case hourly = "hourly"
    /// Executes every day at a specific configured hour and minute.
    case daily = "daily"
    /// Executes every week on a specific day of the week and hour.
    case weekly = "weekly"
    /// Executes at custom recurring minute intervals.
    case intervalMinutes = "intervalMinutes"

    /// Localized display title.
    public var localizedTitle: String {
        switch self {
        case .hourly: return L10n.t(.scheduleHourly)
        case .daily: return L10n.t(.scheduleDaily)
        case .weekly: return L10n.t(.scheduleWeekly)
        case .intervalMinutes: return L10n.t(.scheduleInterval)
        }
    }
}

/// Automated background scheduling configuration for a backup profile.
public struct BackupSchedule: Codable, Sendable, Equatable {
    /// Whether automated background execution is enabled.
    public var isEnabled: Bool
    /// Selected scheduling frequency.
    public var frequency: ScheduleFrequency
    /// Scheduled hour of day (0..23).
    public var hour: Int
    /// Scheduled minute of hour (0..59).
    public var minute: Int
    /// Scheduled weekday (1 = Sunday, 2 = Monday ... 7 = Saturday).
    public var weekday: Int
    /// Recurring minute interval when using `.intervalMinutes` mode.
    public var intervalMinutes: Int
    /// Timestamp of the last executed backup run.
    public var lastRunDate: Date?
    /// Whether to automatically catch up missed backups upon wake or volume connection.
    public var catchUpIfMissed: Bool

    /// Initializes a `BackupSchedule`.
    /// - Parameters:
    ///   - isEnabled: True if enabled.
    ///   - frequency: Recurrence frequency.
    ///   - hour: Hour of execution.
    ///   - minute: Minute of execution.
    ///   - weekday: Weekday for weekly schedules.
    ///   - intervalMinutes: Minutes for interval schedules.
    ///   - lastRunDate: Last run date.
    ///   - catchUpIfMissed: True to trigger catch-up backups.
    public init(
        isEnabled: Bool = false,
        frequency: ScheduleFrequency = .daily,
        hour: Int = 18,
        minute: Int = 0,
        weekday: Int = 2,
        intervalMinutes: Int = 60,
        lastRunDate: Date? = nil,
        catchUpIfMissed: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
        self.intervalMinutes = intervalMinutes
        self.lastRunDate = lastRunDate
        self.catchUpIfMissed = catchUpIfMissed
    }
}

/// Model representing a user-defined backup profile configuration.
public struct BackupProfile: Identifiable, Codable, Sendable, Equatable {
    /// Default localized profile name.
    public static var defaultProfileName: String {
        L10n.t(.defaultProfileName)
    }

    /// Unique identifier of the profile.
    public let id: UUID
    /// Convenient alias for `id`.
    public var uuid: UUID { id }
    /// User-visible profile display name.
    public var name: String
    /// Source folder URL to be backed up.
    public var sourceURL: URL
    /// Destination root folder URL where snapshots and manifests are stored.
    public var destinationURL: URL
    /// List of file/folder name and path patterns to exclude from backups.
    public var excludePatterns: [String]
    /// Strategy for handling dataless iCloud Drive files.
    public var icloudStrategy: ICloudBackupStrategy
    /// Strategy for fast hash change verification.
    public var hashVerificationMode: HashVerificationMode
    /// Snapshot retention and consolidation policy.
    public var pruningPolicy: PruningPolicy
    /// Background automated scheduling rules.
    public var schedule: BackupSchedule
    /// Whether to respect .nobackup, CACHEDIR.TAG, and .otterkeepignore files.
    public var enableIgnoreFiles: Bool
    /// Whether to automatically honor .gitignore files in repositories.
    public var respectGitIgnore: Bool
    /// Automatically trigger backup when destination volume is mounted.
    public var backupOnVolumeMount: Bool
    /// Automatically unmount/eject the volume upon successful backup completion.
    public var autoEjectOnCompletion: Bool
    /// Outbound webhook remote monitoring configuration (Slack, Discord, Pushover, HTTP POST).
    public var webhookConfig: WebhookConfiguration
    /// Free storage warning threshold in Gigabytes (nil for default 20 GB).
    public var quotaWarningThresholdGB: Int?
    /// Whether storage capacity forecasting and low disk space quota alerts are enabled.
    public var enableQuotaAlerts: Bool
    /// Whether rate-of-change and ransomware anomaly detection is enabled.
    public var enableRateOfChangeGuard: Bool
    /// Maximum allowable percentage of changed files before triggering an anomaly (default: 20.0%).
    public var maxChangeThresholdPercent: Double
    /// Maximum allowable deleted file count before triggering an anomaly (default: 200).
    public var maxDeletedThresholdCount: Int
    /// Whether to actively scan added/modified files for known ransomware extensions.
    public var detectKnownRansomwareExtensions: Bool
    /// Whether to abort the backup operation immediately upon detecting an anomaly.
    public var abortOnAnomaly: Bool
    /// Whether WORM immutability locking (UF_IMMUTABLE / uchg) is enforced on snapshots.
    public var isImmutabilityLockEnabled: Bool
    /// Number of days snapshots remain immutably locked (default: 30 days).
    public var immutabilityLockDays: Int
    /// Whether secondary replication copy jobs are dispatched in parallel with local CoW backups.
    public var isParallelMultiDestinationEnabled: Bool

    /// Initializes a `BackupProfile`.
    /// - Parameters:
    ///   - id: Unique UUID.
    ///   - name: Profile name.
    ///   - sourceURL: Source directory URL.
    ///   - destinationURL: Destination backup directory URL.
    ///   - excludePatterns: Array of exclusion patterns.
    ///   - icloudStrategy: iCloud backup strategy.
    ///   - hashVerificationMode: Hash verification mode (default: `.smartHash`).
    ///   - pruningPolicy: Retention pruning rules.
    ///   - schedule: Automated schedule settings.
    ///   - copyJobConfig: Remote copy job configuration.
    ///   - enableIgnoreFiles: Respect .nobackup and ignore files.
    ///   - respectGitIgnore: Respect repository .gitignore files.
    ///   - backupOnVolumeMount: Trigger on volume mount.
    ///   - autoEjectOnCompletion: Auto-eject volume after backup.
    ///   - webhookConfig: Remote webhook notification configuration.
    ///   - quotaWarningThresholdGB: Low disk space alert threshold in GB.
    ///   - enableQuotaAlerts: Enable capacity forecasting and quota alerts.
    ///   - enableRateOfChangeGuard: Enable rate of change & ransomware guard.
    ///   - maxChangeThresholdPercent: Rate of change threshold percentage.
    ///   - maxDeletedThresholdCount: Mass deletion threshold count.
    ///   - detectKnownRansomwareExtensions: Detect ransomware extensions.
    ///   - abortOnAnomaly: Abort backup if anomaly detected.
    ///   - isImmutabilityLockEnabled: True to lock snapshots with WORM immutability.
    ///   - immutabilityLockDays: Lock duration in days.
    ///   - isParallelMultiDestinationEnabled: True to replicate to targets in parallel.
    public init(
        id: UUID = UUID(),
        name: String,
        sourceURL: URL,
        destinationURL: URL,
        excludePatterns: [String] = [],
        icloudStrategy: ICloudBackupStrategy = .downloadAndEvict,
        hashVerificationMode: HashVerificationMode = .smartHash,
        pruningPolicy: PruningPolicy = PruningPolicy(),
        schedule: BackupSchedule = BackupSchedule(),
        copyJobConfig: BackupCopyJobConfiguration = BackupCopyJobConfiguration(),
        enableIgnoreFiles: Bool = true,
        respectGitIgnore: Bool = false,
        backupOnVolumeMount: Bool = false,
        autoEjectOnCompletion: Bool = false,
        webhookConfig: WebhookConfiguration = WebhookConfiguration(),
        quotaWarningThresholdGB: Int? = 20,
        enableQuotaAlerts: Bool = true,
        enableRateOfChangeGuard: Bool = false,
        maxChangeThresholdPercent: Double = 50.0,
        maxDeletedThresholdCount: Int = 100,
        detectKnownRansomwareExtensions: Bool = true,
        abortOnAnomaly: Bool = false,
        isImmutabilityLockEnabled: Bool = true,
        immutabilityLockDays: Int = 30,
        isParallelMultiDestinationEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.excludePatterns = excludePatterns
        self.icloudStrategy = icloudStrategy
        self.hashVerificationMode = hashVerificationMode
        self.pruningPolicy = pruningPolicy
        self.schedule = schedule
        self.copyJobConfig = copyJobConfig
        self.enableIgnoreFiles = enableIgnoreFiles
        self.respectGitIgnore = respectGitIgnore
        self.backupOnVolumeMount = backupOnVolumeMount
        self.autoEjectOnCompletion = autoEjectOnCompletion
        self.webhookConfig = webhookConfig
        self.quotaWarningThresholdGB = quotaWarningThresholdGB
        self.enableQuotaAlerts = enableQuotaAlerts
        self.enableRateOfChangeGuard = enableRateOfChangeGuard
        self.maxChangeThresholdPercent = maxChangeThresholdPercent
        self.maxDeletedThresholdCount = maxDeletedThresholdCount
        self.detectKnownRansomwareExtensions = detectKnownRansomwareExtensions
        self.abortOnAnomaly = abortOnAnomaly
        self.isImmutabilityLockEnabled = isImmutabilityLockEnabled
        self.immutabilityLockDays = immutabilityLockDays
        self.isParallelMultiDestinationEnabled = isParallelMultiDestinationEnabled
    }

    /// 3-2-1 Remote Backup Copy Job replication configuration.
    public var copyJobConfig: BackupCopyJobConfiguration

    enum CodingKeys: String, CodingKey {
        case id, uuid, name, sourceURL, destinationURL, excludePatterns, icloudStrategy, hashVerificationMode, pruningPolicy, schedule, copyJobConfig
        case enableIgnoreFiles, respectGitIgnore, backupOnVolumeMount, autoEjectOnCompletion
        case webhookConfig, quotaWarningThresholdGB, enableQuotaAlerts
        case enableRateOfChangeGuard, maxChangeThresholdPercent, maxDeletedThresholdCount, detectKnownRansomwareExtensions, abortOnAnomaly
        case isImmutabilityLockEnabled, immutabilityLockDays, isParallelMultiDestinationEnabled
    }

    /// Directory URL holding internal manifest and database artifacts (`<destination>/.otterkeep/`).
    public var manifestDirectoryURL: URL {
        destinationURL.appendingPathComponent(".otterkeep", isDirectory: true)
    }

    /// URL to the active SQLite manifest database (`<destination>/.otterkeep/manifest.sqlite`).
    public var manifestDatabaseURL: URL {
        manifestDirectoryURL.appendingPathComponent("manifest.sqlite")
    }

    /// Standardized filesystem path to the SQLite manifest database.
    public var manifestDatabasePath: String {
        manifestDatabaseURL.standardizedFileURL.path(percentEncoded: false)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(UUID.self, forKey: .id) {
            self.id = id
        } else if let uid = try container.decodeIfPresent(UUID.self, forKey: .uuid) {
            self.id = uid
        } else {
            self.id = UUID()
        }
        self.name = try container.decode(String.self, forKey: .name)
        self.sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        self.destinationURL = try container.decode(URL.self, forKey: .destinationURL)
        self.excludePatterns = try container.decode([String].self, forKey: .excludePatterns)
        
        if let strat = try? container.decode(ICloudBackupStrategy.self, forKey: .icloudStrategy) {
            self.icloudStrategy = strat
        } else if let rawStr = try? container.decode(String.self, forKey: .icloudStrategy) {
            if rawStr.contains("Metadata") {
                self.icloudStrategy = .metadataOnly
            } else {
                self.icloudStrategy = .downloadAndEvict
            }
        } else {
            self.icloudStrategy = .downloadAndEvict
        }

        self.hashVerificationMode = try container.decodeIfPresent(HashVerificationMode.self, forKey: .hashVerificationMode) ?? .smartHash
        self.pruningPolicy = try container.decodeIfPresent(PruningPolicy.self, forKey: .pruningPolicy) ?? PruningPolicy()
        self.schedule = try container.decodeIfPresent(BackupSchedule.self, forKey: .schedule) ?? BackupSchedule()
        self.copyJobConfig = try container.decodeIfPresent(BackupCopyJobConfiguration.self, forKey: .copyJobConfig) ?? BackupCopyJobConfiguration()
        self.enableIgnoreFiles = try container.decodeIfPresent(Bool.self, forKey: .enableIgnoreFiles) ?? true
        self.respectGitIgnore = try container.decodeIfPresent(Bool.self, forKey: .respectGitIgnore) ?? false
        self.backupOnVolumeMount = try container.decodeIfPresent(Bool.self, forKey: .backupOnVolumeMount) ?? false
        self.autoEjectOnCompletion = try container.decodeIfPresent(Bool.self, forKey: .autoEjectOnCompletion) ?? false
        self.webhookConfig = try container.decodeIfPresent(WebhookConfiguration.self, forKey: .webhookConfig) ?? WebhookConfiguration()
        self.quotaWarningThresholdGB = try container.decodeIfPresent(Int.self, forKey: .quotaWarningThresholdGB) ?? 20
        self.enableQuotaAlerts = try container.decodeIfPresent(Bool.self, forKey: .enableQuotaAlerts) ?? true
        self.enableRateOfChangeGuard = try container.decodeIfPresent(Bool.self, forKey: .enableRateOfChangeGuard) ?? false
        self.maxChangeThresholdPercent = try container.decodeIfPresent(Double.self, forKey: .maxChangeThresholdPercent) ?? 50.0
        self.maxDeletedThresholdCount = try container.decodeIfPresent(Int.self, forKey: .maxDeletedThresholdCount) ?? 100
        self.detectKnownRansomwareExtensions = try container.decodeIfPresent(Bool.self, forKey: .detectKnownRansomwareExtensions) ?? true
        self.abortOnAnomaly = try container.decodeIfPresent(Bool.self, forKey: .abortOnAnomaly) ?? false
        self.isImmutabilityLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .isImmutabilityLockEnabled) ?? true
        self.immutabilityLockDays = try container.decodeIfPresent(Int.self, forKey: .immutabilityLockDays) ?? 30
        self.isParallelMultiDestinationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isParallelMultiDestinationEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(destinationURL, forKey: .destinationURL)
        try container.encode(excludePatterns, forKey: .excludePatterns)
        try container.encode(icloudStrategy, forKey: .icloudStrategy)
        try container.encode(hashVerificationMode, forKey: .hashVerificationMode)
        try container.encode(pruningPolicy, forKey: .pruningPolicy)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(copyJobConfig, forKey: .copyJobConfig)
        try container.encode(enableIgnoreFiles, forKey: .enableIgnoreFiles)
        try container.encode(respectGitIgnore, forKey: .respectGitIgnore)
        try container.encode(backupOnVolumeMount, forKey: .backupOnVolumeMount)
        try container.encode(autoEjectOnCompletion, forKey: .autoEjectOnCompletion)
        try container.encode(webhookConfig, forKey: .webhookConfig)
        try container.encode(quotaWarningThresholdGB, forKey: .quotaWarningThresholdGB)
        try container.encode(enableQuotaAlerts, forKey: .enableQuotaAlerts)
        try container.encode(enableRateOfChangeGuard, forKey: .enableRateOfChangeGuard)
        try container.encode(maxChangeThresholdPercent, forKey: .maxChangeThresholdPercent)
        try container.encode(maxDeletedThresholdCount, forKey: .maxDeletedThresholdCount)
        try container.encode(detectKnownRansomwareExtensions, forKey: .detectKnownRansomwareExtensions)
        try container.encode(abortOnAnomaly, forKey: .abortOnAnomaly)
        try container.encode(isImmutabilityLockEnabled, forKey: .isImmutabilityLockEnabled)
        try container.encode(immutabilityLockDays, forKey: .immutabilityLockDays)
        try container.encode(isParallelMultiDestinationEnabled, forKey: .isParallelMultiDestinationEnabled)
    }


    // MARK: - Path Matching & Normalization

    /// Canonicalizes a filesystem path by resolving symlinks, stripping APFS data volume firmlink prefixes,
    /// and mapping iCloud Drive CloudDocs document/desktop representations to standard user paths.
    public static func canonicalizePath(_ inputPath: String) -> String {
        var path = inputPath
        while path.contains("//") {
            path = path.replacingOccurrences(of: "//", with: "/")
        }
        while path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }

        // 1. Strip macOS APFS system/data volume firmlink prefix if present
        let dataPrefix = "/System/Volumes/Data"
        if path.hasPrefix(dataPrefix) {
            path = String(path.dropFirst(dataPrefix.count))
        }

        // 2. Resolve iCloud Drive Mobile Documents symlinks/paths to standard user directories
        var userHome: String
        if let pw = getpwuid(getuid()) {
            userHome = String(cString: pw.pointee.pw_dir)
        } else {
            userHome = FileManager.default.homeDirectoryForCurrentUser.path
        }
        while userHome.hasSuffix("/") && userHome.count > 1 {
            userHome.removeLast()
        }

        let cloudDocsDocs = userHome + "/Library/Mobile Documents/com~apple~CloudDocs/Documents"
        let standardDocs = userHome + "/Documents"
        if path == cloudDocsDocs {
            path = standardDocs
        } else if path.hasPrefix(cloudDocsDocs + "/") {
            path = standardDocs + String(path.dropFirst(cloudDocsDocs.count))
        }

        let cloudDocsDesktop = userHome + "/Library/Mobile Documents/com~apple~CloudDocs/Desktop"
        let standardDesktop = userHome + "/Desktop"
        if path == cloudDocsDesktop {
            path = standardDesktop
        } else if path.hasPrefix(cloudDocsDesktop + "/") {
            path = standardDesktop + String(path.dropFirst(cloudDocsDesktop.count))
        }

        // 3. Attempt filesystem symlink resolution if the path or an existing ancestor exists
        let url = URL(fileURLWithPath: path)
        let resolved = url.resolvingSymlinksInPath().path(percentEncoded: false)
        if !resolved.isEmpty && resolved != path {
            var res = resolved
            if res.hasPrefix(dataPrefix) {
                res = String(res.dropFirst(dataPrefix.count))
            }
            path = res
        }

        while path.contains("//") {
            path = path.replacingOccurrences(of: "//", with: "/")
        }
        while path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }
        return path
    }

    /// Returns the standardized, canonical filesystem path for `sourceURL` without trailing slashes.
    public var normalizedSourcePath: String {
        BackupProfile.canonicalizePath(sourceURL.standardizedFileURL.path(percentEncoded: false))
    }

    /// Checks if a file or directory at the given path belongs to this profile's source directory.
    public func containsPath(_ candidatePath: String) -> Bool {
        let cand = BackupProfile.canonicalizePath(candidatePath)
        let src = normalizedSourcePath
        return cand == src || cand.hasPrefix(src + "/")
    }

    /// Computes the relative path of a candidate file URL or path relative to this profile's source directory.
    public func relativePath(for candidatePath: String) -> String? {
        guard containsPath(candidatePath) else { return nil }
        let cand = BackupProfile.canonicalizePath(candidatePath)
        let src = normalizedSourcePath
        var rel = String(cand.dropFirst(src.count))
        while rel.hasPrefix("/") {
            rel.removeFirst()
        }
        return rel
    }
}

// MARK: - Application DTO Mapping
extension BackupProfile {
    /// Maps domain/core profile to clean architecture Application layer DTO.
    public func toDTO() -> ProfileConfigurationDTO {
        ProfileConfigurationDTO(
            id: id,
            name: name,
            sourcePath: sourceURL.path,
            destinationPath: destinationURL.path,
            excludePatterns: excludePatterns,
            isImmutabilityLockEnabled: isImmutabilityLockEnabled,
            immutabilityLockDays: immutabilityLockDays
        )
    }

    /// Initializes profile from Application layer DTO.
    public init(from dto: ProfileConfigurationDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            sourceURL: URL(fileURLWithPath: dto.sourcePath),
            destinationURL: URL(fileURLWithPath: dto.destinationPath),
            excludePatterns: dto.excludePatterns,
            isImmutabilityLockEnabled: dto.isImmutabilityLockEnabled,
            immutabilityLockDays: dto.immutabilityLockDays
        )
    }
}


