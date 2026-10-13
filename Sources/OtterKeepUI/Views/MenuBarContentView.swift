import SwiftUI
import AppKit
import OtterKeepCore
import OtterKeepStorage

/// MenuBar popup window interface presenting live backup status, all configured profiles, quick trigger actions, and system shortcuts.
public struct MenuBarContentView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerView

            if isAnyOperationRunning {
                runningOperationBanner
            }

            if let update = appState.softwareUpdateAvailableInfo {
                updateAvailableBanner(update: update)
            }

            Divider()

            // Profiles list & trigger all
            profilesSection

            Divider()

            // Apple Photos Backup Card
            photosBackupCard

            // Destination Storage Glance Card (if available)
            storageGlanceCard

            Divider()

            // Bottom action controls
            footerControls
        }
        .padding(12)
        .frame(width: 320)
        .preferredColorScheme(appState.currentTheme.colorScheme)
    }

    var isAnyOperationRunning: Bool {
        appState.isBackupRunning || appState.isPhotosBackupRunning || appState.isReplicationRunning
    }
}
