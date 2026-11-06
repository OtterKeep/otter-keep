import SwiftUI
import AppKit
import OtterKeepCore

/// Unified workspace for an individual backup profile, featuring a top segmented navigation bar
/// between Overview (live telemetry & pipeline) and Time Machine (restore explorer).
///
/// Rules, automation and maintenance are intentionally *not* a tab here — they open from the
/// Profile Settings button, so configuration never competes with the daily monitoring surface.
public struct ProfileWorkspaceView: View {
    public let profile: BackupProfile
    public let appState: AppState

    public init(profile: BackupProfile, appState: AppState) {
        self.profile = profile
        self.appState = appState
    }

    private var activeTabBinding: Binding<ProfileWorkspaceTab> {
        Binding(
            get: { appState.activeProfileTab },
            set: { appState.activeProfileTab = $0 }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Modern Navigation & Action Bar
            workspaceHeaderBar

            Divider()

            // Tab Content
            Group {
                switch appState.activeProfileTab {
                case .overview:
                    MainDashboardView(appState: appState)
                case .timeMachine:
                    RestoreExplorerView(appState: appState)
                }
            }
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(OtterTheme.smoothEase, value: appState.activeProfileTab)
    }

    // MARK: - Modern Workspace Header Bar
    private var workspaceHeaderBar: some View {
        HStack(spacing: 16) {
            // Profile Title, APFS Badge, and Last Backup Status
            HStack(spacing: 8) {
                let health = appState.profileHealthStatus(for: profile)
                Image(systemName: health.systemImage)
                    .font(.title3)
                    .foregroundStyle(health.color)
                    .symbolEffect(.rotate, isActive: health == .running)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline.bold())

                    let cowMode = appState.volumeEvaluation?.cowMode ?? .intraVolumeCoW
                    let statusInfo = appState.lastStatusInfo(for: profile)
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: cowMode == .nonAPFS ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                            Text(L10n.t(cowMode.badgeKey))
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(cowMode == .nonAPFS ? OtterTheme.statusWarning : OtterTheme.statusGreen)

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusInfo.statusColor)
                                .frame(width: 5, height: 5)
                            Text(statusInfo.displayDetailText)
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 12)

            // Centered Segmented Workspace Tabs
            Picker("", selection: activeTabBinding) {
                ForEach(ProfileWorkspaceTab.allCases) { tab in
                    Label(tab.localizedTitle, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .labelsHidden()
            .frame(minWidth: 240, idealWidth: 340, maxWidth: 420)
            .layoutPriority(1)

            Spacer(minLength: 12)

            // Profile Configuration & Quick Action Buttons
            HStack(spacing: 8) {
                // Delete Profile Button (only if multiple profiles exist)
                if appState.profiles.count > 1 {
                    Button(role: .destructive) {
                        appState.profilePendingDeletion = profile
                        appState.showDeleteProfileConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(OtterTheme.statusError)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(L10n.t(.deleteProfileButton))
                    .disabled(appState.isBackupRunning(for: profile.id))
                }

                // Profile Settings Button
                Button {
                    appState.showProfileSettingsModal = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                        Text(L10n.t(.profileSettingsButton))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help(L10n.t(.profileSettingsTitle))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background {
            // Invisible keyboard shortcut targets for ⌘1 / ⌘2 tab switching
            Group {
                Button("") { appState.activeProfileTab = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { appState.activeProfileTab = .timeMachine }
                    .keyboardShortcut("2", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
}
