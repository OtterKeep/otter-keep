import Foundation

/// Thread-safe scheduler managing periodic background backups, external volume mount triggers, and missed run catch-up execution.
public final class BackupScheduler: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = BackupScheduler()

    /// Callback closure signature for backup triggers.
    public typealias BackupTriggerHandler = @Sendable (BackupProfile, _ isCatchUp: Bool) async -> Void
    /// Callback closure signature for Photos backup triggers.
    public typealias PhotosBackupTriggerHandler = @Sendable (PhotosBackupConfiguration, _ isCatchUp: Bool) async -> Void

    private let lock = NSLock()
    private var isRunning = false
    private var timerTask: Task<Void, Never>?
    private var activeProfileIdsRunning = Set<UUID>()
    private var isPhotosBackupRunning = false
    private var activeFSEventWatchers: [UUID: FSEventWatcher] = [:]
    public var onTriggerBackup: BackupTriggerHandler?
    public var onTriggerPhotosBackup: PhotosBackupTriggerHandler?

    private init() {
        // Monitor external disk volume mount events
        VolumeMonitor.shared.addHandler { [weak self] mountedURL in
            guard let self = self else { return }
            Task {
                await self.handleVolumeMounted(mountedURL)
            }
        }
    }

    deinit {
        stop()
    }

    /// Starts the background scheduler loop.
    /// - Parameters:
    ///   - triggerHandler: Asynchronous handler invoked when a profile is due for backup.
    ///   - photosTriggerHandler: Optional asynchronous handler for Photos backup.
    public func start(
        triggerHandler: @escaping BackupTriggerHandler,
        photosTriggerHandler: PhotosBackupTriggerHandler? = nil
    ) {
        lock.lock()
        self.onTriggerBackup = triggerHandler
        if let pHandler = photosTriggerHandler {
            self.onTriggerPhotosBackup = pHandler
        }
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        lock.unlock()

        syncContinuousWatchers()

        timerTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30-second interval
                guard let self = self else { break }
                await self.evaluateSchedules()
                self.syncContinuousWatchers()
            }
        }
    }

    /// Stops the background scheduler loop.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        isRunning = false
        timerTask?.cancel()
        timerTask = nil

        for (_, watcher) in activeFSEventWatchers {
            watcher.stop()
        }
        activeFSEventWatchers.removeAll()
    }

    /// Handles external volume mount events, checking for missed backups for profiles stored on that volume.
    /// - Parameter mountedURL: URL of the newly mounted volume.
    public func handleVolumeMounted(_ mountedURL: URL?) async {
        let profiles = ProfileStore.shared.loadProfiles()
        let now = Date()

        for profile in profiles where profile.schedule.isEnabled {
            let destPath = profile.destinationURL.standardizedFileURL.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: destPath) {
                if isRunMissed(schedule: profile.schedule, now: now) {
                    LogManager.shared.log(
                        "Backup destination disk became available for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]. Triggering catch-up backup...",
                        level: .info,
                        category: "Scheduler"
                    )
                    await triggerBackupSafely(for: profile, isCatchUp: true)
                }
            }
        }

        // Photos backup volume check
        let photosConfig = PhotosProfileStore.shared.loadConfiguration()
        if photosConfig.isEnabled && photosConfig.schedule.isEnabled {
            let destPath = photosConfig.destinationURL.standardizedFileURL.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: destPath) {
                if isRunMissed(schedule: photosConfig.schedule, now: now) {
                    LogManager.shared.log("Photos backup destination disk became available. Triggering catch-up Photos backup...", level: .info, category: "Scheduler")
                    await triggerPhotosBackupSafely(for: photosConfig, isCatchUp: true)
                }
            }
        }
    }

    /// Checks all enabled profiles on app startup and triggers catch-up backups if missed.
    public func checkAndRunCatchUpBackups() async {
        let profiles = ProfileStore.shared.loadProfiles()
        let now = Date()

        for profile in profiles where profile.schedule.isEnabled && profile.schedule.catchUpIfMissed {
            let destPath = profile.destinationURL.standardizedFileURL.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: destPath) else {
                if let lastRun = profile.schedule.lastRunDate {
                    let daysSince = Calendar.current.dateComponents([.day], from: lastRun, to: now).day ?? 0
                    if daysSince >= 7 {
                        NotificationDeliveryService.shared.notifyStaleBackup(
                            profileName: profile.name,
                            daysInactive: daysSince,
                            driveName: profile.destinationURL.lastPathComponent
                        )
                    }
                }
                LogManager.shared.log("Skipping catch-up backup for profile '\(profile.name)': destination disk is not mounted.", level: .debug, category: "Scheduler")
                continue
            }

            if isRunMissed(schedule: profile.schedule, now: now) {
                LogManager.shared.log(
                    "Catch-up backup initiated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)] because scheduled run was missed.",
                    level: .info,
                    category: "Scheduler"
                )
                NotificationDeliveryService.shared.notifyMissedBackup(profileName: profile.name)
                await triggerBackupSafely(for: profile, isCatchUp: true)
            }
        }

        let photosConfig = PhotosProfileStore.shared.loadConfiguration()
        if photosConfig.isEnabled && photosConfig.schedule.isEnabled && photosConfig.schedule.catchUpIfMissed {
            let destPath = photosConfig.destinationURL.standardizedFileURL.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: destPath) && isRunMissed(schedule: photosConfig.schedule, now: now) {
                LogManager.shared.log("Catch-up Photos backup initiated because scheduled run was missed.", level: .info, category: "Scheduler")
                NotificationDeliveryService.shared.notifyMissedBackup(profileName: "Apple Photos")
                await triggerPhotosBackupSafely(for: photosConfig, isCatchUp: true)
            }
        }
    }

    /// Evaluates all profile schedules against current system time.
    public func evaluateSchedules() async {
        let profiles = ProfileStore.shared.loadProfiles()
        let now = Date()
        LogManager.shared.log("Scheduler evaluation cycle: checking \(profiles.count) configured profiles", level: .debug, category: "Scheduler")

        for profile in profiles where profile.schedule.isEnabled {
            let destPath = profile.destinationURL.standardizedFileURL.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: destPath) else {
                continue
            }

            let refDate = profile.schedule.lastRunDate ?? Date(timeIntervalSinceNow: -60)
            let nextRun = calculateNextRunDate(for: profile.schedule, referenceDate: refDate)
            if now >= nextRun {
                LogManager.shared.log("Scheduled backup time reached for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]", level: .info, category: "Scheduler")
                await triggerBackupSafely(for: profile, isCatchUp: false)
            }
        }

        let photosConfig = PhotosProfileStore.shared.loadConfiguration()
        if photosConfig.isEnabled && photosConfig.schedule.isEnabled {
            let destPath = photosConfig.destinationURL.standardizedFileURL.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: destPath) {
                let refDate = photosConfig.schedule.lastRunDate ?? Date(timeIntervalSinceNow: -60)
                let nextRun = calculateNextRunDate(for: photosConfig.schedule, referenceDate: refDate)
                if now >= nextRun {
                    LogManager.shared.log("Scheduled backup time reached for Apple Photos backup", level: .info, category: "Scheduler")
                    await triggerPhotosBackupSafely(for: photosConfig, isCatchUp: false)
                }
            }
        }
    }

    private func markProfileRunning(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if activeProfileIdsRunning.contains(id) {
            return false
        }
        activeProfileIdsRunning.insert(id)
        return true
    }

    private func markProfileFinished(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        activeProfileIdsRunning.remove(id)
    }

    private func getTriggerHandler() -> BackupTriggerHandler? {
        lock.lock()
        defer { lock.unlock() }
        return onTriggerBackup
    }

    private func getPhotosTriggerHandler() -> PhotosBackupTriggerHandler? {
        lock.lock()
        defer { lock.unlock() }
        return onTriggerPhotosBackup
    }

    private func triggerBackupSafely(for profile: BackupProfile, isCatchUp: Bool) async {
        guard markProfileRunning(profile.id) else { return }
        defer { markProfileFinished(profile.id) }

        if let handler = getTriggerHandler() {
            await handler(profile, isCatchUp)
        }
    }

    private func markPhotosRunning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isPhotosBackupRunning {
            return false
        }
        isPhotosBackupRunning = true
        return true
    }

    private func markPhotosFinished() {
        lock.lock()
        defer { lock.unlock() }
        isPhotosBackupRunning = false
    }

    private func triggerPhotosBackupSafely(for config: PhotosBackupConfiguration, isCatchUp: Bool) async {
        guard markPhotosRunning() else { return }
        defer { markPhotosFinished() }

        if let handler = getPhotosTriggerHandler() {
            await handler(config, isCatchUp)
        }
    }

    /// Evaluates whether a scheduled backup was missed.
    /// - Parameters:
    ///   - schedule: Backup schedule configuration.
    ///   - now: Reference time.
    /// - Returns: True if missed.
    public func isRunMissed(schedule: BackupSchedule, now: Date = Date()) -> Bool {
        guard schedule.isEnabled, schedule.catchUpIfMissed else { return false }
        guard let lastRun = schedule.lastRunDate else {
            return true
        }

        let expectedRun = calculateNextRunDate(for: schedule, referenceDate: lastRun)
        return expectedRun < now && now.timeIntervalSince(expectedRun) > 120
    }

    /// Calculates the next execution timestamp following a given reference date.
    /// - Parameters:
    ///   - schedule: Target schedule configuration.
    ///   - referenceDate: Reference timestamp.
    /// - Returns: Next scheduled run date.
    public func calculateNextRunDate(for schedule: BackupSchedule, referenceDate: Date = Date()) -> Date {
        let calendar = Calendar.current

        switch schedule.frequency {
        case .hourly:
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: referenceDate) ?? referenceDate.addingTimeInterval(3600)
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: nextHour)
            return calendar.date(from: comps) ?? nextHour

        case .intervalMinutes:
            let interval = max(1, schedule.intervalMinutes)
            return referenceDate.addingTimeInterval(Double(interval * 60))

        case .daily:
            var comps = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            comps.hour = schedule.hour
            comps.minute = schedule.minute
            comps.second = 0

            guard let candidate = calendar.date(from: comps) else {
                return referenceDate.addingTimeInterval(86400)
            }
            if candidate > referenceDate {
                return candidate
            } else {
                return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(86400)
            }

        case .weekly:
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
            comps.weekday = schedule.weekday
            comps.hour = schedule.hour
            comps.minute = schedule.minute
            comps.second = 0

            guard let candidate = calendar.date(from: comps) else {
                return referenceDate.addingTimeInterval(7 * 86400)
            }
            if candidate > referenceDate {
                return candidate
            } else {
                return calendar.date(byAdding: .weekOfYear, value: 1, to: candidate) ?? candidate.addingTimeInterval(7 * 86400)
            }
        }
    }

    /// Synchronizes active real-time continuous FSEventWatchers with configured backup profiles.
    public func syncContinuousWatchers() {
        let profiles = ProfileStore.shared.loadProfiles()
        lock.lock()
        defer { lock.unlock() }

        let currentIds = Set(activeFSEventWatchers.keys)
        let continuousProfiles = profiles.filter { $0.executionMode.isContinuous }
        let wantedIds = Set(continuousProfiles.map(\.id))

        // Stop watchers for profiles no longer set to continuous or deleted
        for id in currentIds.subtracting(wantedIds) {
            activeFSEventWatchers[id]?.stop()
            activeFSEventWatchers.removeValue(forKey: id)
            LogManager.shared.log("Stopped real-time FSEventWatcher for profile UUID \(id)", level: .debug, category: "Scheduler")
        }

        // Start watchers for newly continuous profiles
        for profile in continuousProfiles where activeFSEventWatchers[profile.id] == nil {
            let sourcePath = profile.sourceURL.standardizedFileURL.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: sourcePath) else { continue }

            let watcher = FSEventWatcher(
                watchedPath: sourcePath,
                excludePatterns: profile.excludePatterns,
                debouncingSeconds: profile.executionMode.debouncingSeconds
            ) { [weak self] _ in
                guard let self = self else { return }
                Task {
                    LogManager.shared.log("Real-time filesystem change triggered backup for profile '\(profile.name)'", level: .info, category: "Scheduler")
                    await self.triggerBackupSafely(for: profile, isCatchUp: false)
                }
            }
            watcher.start()
            activeFSEventWatchers[profile.id] = watcher
            LogManager.shared.log("Started real-time FSEventWatcher for profile '\(profile.name)' [\(sourcePath)]", level: .info, category: "Scheduler")
        }
    }
}
