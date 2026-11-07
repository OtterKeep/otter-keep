import AppIntents

/// Declares the App Intents package boundary for OtterKeepCore to enable discovery by the host app.
public struct OtterKeepCorePackage: AppIntentsPackage {
    public init() {}
}

/// Registers default App Shortcuts available automatically in macOS Shortcuts and Spotlight.
public struct OtterKeepShortcutsProvider: AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor {
        .orange
    }

    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartBackupIntent(),
            phrases: [
                "Start \(.applicationName) backup",
                "Back up with \(.applicationName)",
                "Run \(.applicationName) backup",
                "Indíts \(.applicationName) mentést",
                "Készíts \(.applicationName) biztonsági mentést",
            ],
            shortTitle: "Start Backup",
            systemImageName: "arrow.clockwise.circle.fill"
        )
        AppShortcut(
            intent: GetBackupStatusIntent(),
            phrases: [
                "Get \(.applicationName) status",
                "Check \(.applicationName) backup status",
                "\(.applicationName) állapot lekérdezése",
                "Ellenőrizd a \(.applicationName) mentési állapotot",
            ],
            shortTitle: "Backup Status",
            systemImageName: "shield.checkmark.fill"
        )
    }
}
