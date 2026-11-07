import AppIntents
import Foundation
import OtterKeepDomain

/// AppIntent enabling macOS Shortcuts and Siri to check the health and date of the latest backup.
public struct GetBackupStatusIntent: AppIntent, Sendable {
    public static let title: LocalizedStringResource = "Get Backup Status"
    public static let description = IntentDescription("Retrieves the status and timestamp of the latest OtterKeep backup.")
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
        } else {
            targetProfile = profiles[0]
        }

        if let lastRun = targetProfile.schedule.lastRunDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: lastRun, relativeTo: Date())
            return .result(dialog: "Latest backup for '\(targetProfile.name)' was \(relative).")
        } else {
            return .result(dialog: "No previous backups recorded for '\(targetProfile.name)'.")
        }
    }
}
