import AppIntents
import Foundation
import OtterKeepDomain
import OtterKeepStorage
import OtterKeepDatabase

/// AppIntent enabling macOS Shortcuts and Siri to trigger background backups silently.
public struct StartBackupIntent: AppIntent, Sendable {
    public static let title: LocalizedStringResource = "Start OtterKeep Backup"
    public static let description = IntentDescription("Starts a silent background backup for the specified OtterKeep profile.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Profile")
    public var profile: ProfileAppEntity?

    public init() {}

    public init(profile: ProfileAppEntity?) {
        self.profile = profile
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let profiles = ProfileStore.shared.loadProfiles()
        guard !profiles.isEmpty else {
            return .result(dialog: "No backup profiles configured in OtterKeep.")
        }

        let targetProfile: BackupProfile
        if let requested = profile, let match = profiles.first(where: { $0.id.uuidString == requested.id }) {
            targetProfile = match
        } else if let first = profiles.first {
            targetProfile = first
        } else {
            return .result(dialog: "Could not resolve a valid backup profile.")
        }

        // Execute silently in background via BackupSessionCoordinator
        let storage = DefaultFileSystemProvider()
        let database = DatabaseEngine()
        let retentionManager = RetentionManager(storage: storage, database: database)
        let coordinator = BackupSessionCoordinator(
            storage: storage,
            database: database,
            retentionManager: retentionManager,
            volumeEjector: SystemVolumeEjector()
        )

        do {
            _ = try await coordinator.performBackup(profile: targetProfile, mode: .incremental)
            var updated = targetProfile
            updated.schedule.lastRunDate = Date()
            try? ProfileStore.shared.updateProfile(updated)

            let duration = (await coordinator.lastSessionSummary)?.durationSeconds ?? 1.0
            let copiedCount = (await coordinator.lastSessionSummary)?.copiedCount ?? 0

            NotificationDeliveryService.shared.notifyBackupCompleted(
                profileName: targetProfile.name,
                status: "Success",
                copiedCount: copiedCount,
                durationSec: duration
            )

            return .result(dialog: "Backup for '\(targetProfile.name)' completed successfully.")
        } catch {
            NotificationDeliveryService.shared.notifyBackupFailed(
                profileName: targetProfile.name,
                errorMessage: error.localizedDescription
            )
            return .result(dialog: "Backup failed for '\(targetProfile.name)': \(error.localizedDescription)")
        }
    }
}
