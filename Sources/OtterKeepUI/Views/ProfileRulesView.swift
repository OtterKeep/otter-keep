import SwiftUI
import AppKit
import OtterKeepStorage
import OtterKeepCore

/// Dedicated view for managing profile rules, directories, exclusions, iCloud, and backup schedules.
public struct ProfileRulesView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    var excludePatternBinding: Binding<String> {
        Binding(
            get: { appState.newExcludePattern },
            set: { appState.newExcludePattern = $0 }
        )
    }

    var showDestinationEditorBinding: Binding<Bool> {
        Binding(
            get: { appState.showRemoteDestinationEditorSheet },
            set: { appState.showRemoteDestinationEditorSheet = $0 }
        )
    }

    public var body: some View {
        ScrollView {
            content
                .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: showDestinationEditorBinding) {
            RemoteDestinationEditorModalView(appState: appState)
        }
    }

    public var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let profile = appState.selectedProfile {
                let isLocked = appState.isBackupRunning(for: profile.id)

                if isLocked {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title3)
                            .foregroundStyle(OtterTheme.otterAmber)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.profileLockedBannerTitle))
                                .font(.subheadline.bold())
                                .foregroundStyle(OtterTheme.otterAmber)
                            Text(L10n.t(.profileLockedBannerMessage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .otterCard(padding: OtterTheme.spacing12)
                }

                Group {
                    // 1. Directory Overview Header
                    folderSummaryHeader(profile: profile)

                    // 2. iCloud Storage Strategy
                    icloudStrategySection(profile: profile)

                    // 3. Exclusion Rules (Tag cloud + Quick presets)
                    exclusionRulesSection(profile: profile)

                    // 4. Automatic Scheduling
                    scheduleSection(profile: profile)

                    // 5. External Drive Automation
                    externalDriveSection(profile: profile)

                    // 6. 3-2-1 Backup Copy Job & Remote Targets
                    backupCopyJobSection(profile: profile)

                    // 7. Wi-Fi SSID & Metered Hotspot Protection
                    WiFiProtectionCardView(appState: appState, profile: profile)

                    // 8. Outbound Webhook Remote Monitoring (Slack, Discord, Pushover)
                    WebhookSettingsCardView(appState: appState, profile: profile)

                    // 9. Ransomware & Rate-of-Change Anomaly Guard
                    ransomwareGuardSection(profile: profile)
                }
                .disabled(isLocked)
            } else {

                ContentUnavailableView(
                    L10n.t(.noProfileSelectedTitle),
                    systemImage: "folder.badge.questionmark",
                    description: Text(L10n.t(.noProfileSelectedDesc))
                )
            }
        }
    }

}
