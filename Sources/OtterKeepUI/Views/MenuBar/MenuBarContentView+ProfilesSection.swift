import SwiftUI
import AppKit
import OtterKeepCore
import OtterKeepStorage

extension MenuBarContentView {
    // MARK: - Profiles Section
    var profilesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(L10n.t(.menuBarProfilesTitle))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.caption)
                        .foregroundStyle(OtterTheme.oceanicTeal)
                }

                Spacer()

                if !appState.profiles.isEmpty {
                    Button {
                        appState.startBackupAll(mode: .incremental)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 9))
                            Text(L10n.t(.menuBarBackupAll))
                                .font(.caption2.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OtterTheme.otterAmber)
                    .controlSize(.mini)
                }
            }

            if appState.profiles.isEmpty {
                Text(L10n.t(.noProfileSelectedTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else if appState.profiles.count <= 3 {
                VStack(spacing: 4) {
                    ForEach(appState.profiles) { profile in
                        profileRow(for: profile)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(appState.profiles) { profile in
                            profileRow(for: profile)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private func profileRow(for profile: BackupProfile) -> some View {
        let isRunning = appState.isBackupRunning(for: profile.id)
        let statusInfo = appState.lastStatusInfo(for: profile)

        return HStack(spacing: 8) {
            if isRunning {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(statusInfo.statusColor)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                if isRunning {
                    let prog = appState.progressState(for: profile.id)
                    Text(L10n.t(prog.phase.localizedKey))
                        .font(.caption2)
                        .foregroundStyle(OtterTheme.otterAmber)
                        .lineLimit(1)
                } else if profile.schedule.isEnabled {
                    Text(L10n.t(.menuBarNextRun) + " " + appState.nextScheduledRunDescription(for: profile))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(statusInfo.displayDetailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appState.selectProfile(id: profile.id)
                openMainWindow()
            }

            Spacer()

            if isRunning {
                Button {
                    appState.cancelBackup(for: profile.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .tint(OtterTheme.statusError)
                .controlSize(.mini)
                .help(L10n.t(.stopBackupButton))
            } else {
                Button {
                    appState.startBackup(for: profile, mode: .incremental)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(L10n.t(.menuBarBackupProfile))

                // Profile action menu
                Menu {
                    Button {
                        appState.startBackup(for: profile, mode: .incremental)
                    } label: {
                        Label(L10n.t(.menuBarBackupProfile), systemImage: "play.circle")
                    }
                    .disabled(isRunning)

                    Button {
                        appState.startBackup(for: profile, mode: .full)
                    } label: {
                        Label(L10n.t(.menuBarFullBackup), systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(isRunning)

                    Button {
                        appState.selectProfile(id: profile.id)
                        appState.performDryRun(mode: .incremental)
                        openMainWindow()
                    } label: {
                        Label(L10n.t(.menuBarSimulateDryRun), systemImage: "wand.and.stars")
                    }
                    .disabled(isRunning)

                    Divider()

                    Button {
                        appState.selectProfile(id: profile.id)
                        openRestoreExplorer()
                    } label: {
                        Label(L10n.t(.menuBarTimeMachine), systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([profile.destinationURL])
                    } label: {
                        Label(L10n.t(.menuBarRevealDestination), systemImage: "arrow.up.forward.app")
                    }

                    Button {
                        appState.selectProfile(id: profile.id)
                        appState.activeProfileTab = .rulesAndMaintenance
                        openMainWindow()
                    } label: {
                        Label(L10n.t(.menuBarOpenRules), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button {
                appState.startBackup(for: profile, mode: .incremental)
            } label: {
                Label(L10n.t(.menuBarBackupProfile), systemImage: "play.circle")
            }
            .disabled(isRunning)

            Button {
                appState.startBackup(for: profile, mode: .full)
            } label: {
                Label(L10n.t(.menuBarFullBackup), systemImage: "arrow.clockwise.circle")
            }
            .disabled(isRunning)

            Button {
                appState.selectProfile(id: profile.id)
                appState.performDryRun(mode: .incremental)
                openMainWindow()
            } label: {
                Label(L10n.t(.menuBarSimulateDryRun), systemImage: "wand.and.stars")
            }
            .disabled(isRunning)

            Divider()

            Button {
                appState.selectProfile(id: profile.id)
                openRestoreExplorer()
            } label: {
                Label(L10n.t(.menuBarTimeMachine), systemImage: "clock.arrow.circlepath")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([profile.destinationURL])
            } label: {
                Label(L10n.t(.menuBarRevealDestination), systemImage: "arrow.up.forward.app")
            }

            Button {
                appState.selectProfile(id: profile.id)
                appState.activeProfileTab = .rulesAndMaintenance
                openMainWindow()
            } label: {
                Label(L10n.t(.menuBarOpenRules), systemImage: "slider.horizontal.3")
            }
        }
    }
}
