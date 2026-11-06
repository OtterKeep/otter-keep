import SwiftUI
import AppKit
import OtterKeepCore

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

            // Scrollable middle so the footer stays reachable on short screens or with many profiles.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    // Profiles list & trigger all
                    profilesSection

                    Divider()

                    // Apple Photos Backup Card
                    photosBackupCard

                    // Destination Storage Glance Card (if available)
                    storageGlanceCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            // Bottom action controls
            footerControls
        }
        .padding(12)
        .frame(minWidth: 320, idealWidth: 320, maxWidth: 320)
        .frame(maxHeight: 560)
        .preferredColorScheme(appState.currentTheme.colorScheme)
    }

    var isAnyOperationRunning: Bool {
        appState.isBackupRunning || appState.isPhotosBackupRunning || appState.isReplicationRunning
    }
}
