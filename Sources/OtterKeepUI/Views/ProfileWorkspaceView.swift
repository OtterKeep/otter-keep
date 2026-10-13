import SwiftUI
import AppKit
import OtterKeepCore

/// Unified workspace for an individual backup profile, featuring a top segmented navigation bar
/// between Overview (live telemetry & pipeline), Time Machine (restore explorer), and Rules & Maintenance.
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
            switch appState.activeProfileTab {
            case .overview:
                MainDashboardView(appState: appState)
            case .timeMachine:
                RestoreExplorerView(appState: appState)
            case .rulesAndMaintenance:
                ProfileRulesAndMaintenanceView(appState: appState, profile: profile)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(cowMode == .nonAPFS ? OtterTheme.statusWarning : OtterTheme.statusGreen)

                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusInfo.statusColor)
                                .frame(width: 5, height: 5)
                            Text(statusInfo.displayDetailText)
                        }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Centered Segmented Workspace Tabs
            Picker("", selection: activeTabBinding) {
                ForEach([ProfileWorkspaceTab.overview, ProfileWorkspaceTab.timeMachine]) { tab in
                    Label(tab.localizedTitle, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .frame(maxWidth: 320)

            Spacer()

            // Profile Configuration & Quick Action Buttons
            HStack(spacing: 8) {
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

                Divider()
                    .frame(height: 18)

                // Dry-Run Button
                Button {
                    appState.performDryRun()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appState.isDryRunRunning ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                            .symbolEffect(.rotate, isActive: appState.isDryRunRunning)
                        Text(appState.isDryRunRunning ? L10n.t(.analyzingProgress) : L10n.t(.quickDryRunAction))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut("d", modifiers: .command)
                .disabled(appState.isBackupRunning(for: profile.id) || appState.isDryRunRunning)

                // Backup Now / Stop Button
                if appState.isBackupRunning(for: profile.id) {
                    Button(role: .destructive) {
                        appState.cancelBackup(for: profile.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                            Text(L10n.t(.stopBackupButton))
                        }
                        .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OtterTheme.statusError)
                    .controlSize(.regular)
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button {
                        appState.startBackup(for: profile)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text(L10n.t(.quickBackupAction))
                        }
                        .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OtterTheme.otterAmber)
                    .controlSize(.regular)
                    .keyboardShortcut("b", modifiers: .command)
                    .disabled(appState.isDryRunRunning)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background {
            // Invisible keyboard shortcut targets for ⌘1, ⌘2 tab switching
            Group {
                Button("") { appState.activeProfileTab = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { appState.activeProfileTab = .timeMachine }
                    .keyboardShortcut("2", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .sheet(isPresented: Binding(
            get: { appState.showProfileSettingsModal },
            set: { appState.showProfileSettingsModal = $0 }
        )) {
            ProfileSettingsModalView(appState: appState, profile: profile)
        }
        .confirmationDialog(
            L10n.t(.deleteProfileConfirmTitle),
            isPresented: Binding(
                get: { appState.showDeleteProfileConfirmation },
                set: { appState.showDeleteProfileConfirmation = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.t(.deleteProfileButton), role: .destructive) {
                let targetId = appState.profilePendingDeletion?.id ?? profile.id
                appState.deleteProfile(id: targetId)
                appState.profilePendingDeletion = nil
            }
            Button(L10n.t(.cancel), role: .cancel) {
                appState.profilePendingDeletion = nil
            }
        } message: {
            Text(L10n.t(.deleteProfileConfirmMessage))
        }
    }
}
