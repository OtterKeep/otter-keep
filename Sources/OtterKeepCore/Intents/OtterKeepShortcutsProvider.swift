import AppIntents

/// Registers default App Shortcuts available automatically in macOS Shortcuts and Spotlight.
public struct OtterKeepShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartBackupIntent(),
            phrases: [
                "Start \(.applicationName) backup",
                "Back up with \(.applicationName)",
                "Run \(.applicationName) backup"
            ],
            shortTitle: "Start Backup",
            systemImageName: "arrow.clockwise.circle.fill"
        )
        AppShortcut(
            intent: GetBackupStatusIntent(),
            phrases: [
                "Get \(.applicationName) status",
                "Check \(.applicationName) backup status"
            ],
            shortTitle: "Backup Status",
            systemImageName: "shield.checkmark.fill"
        )
    }
}
