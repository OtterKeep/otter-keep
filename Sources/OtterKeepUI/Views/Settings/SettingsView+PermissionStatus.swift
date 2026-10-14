import SwiftUI
import AppKit
import OtterKeepCore

extension SettingsView {
    // MARK: - Permission Status HUD
    var permissionStatusHUD: some View {
        let status = appState.finderPermissionStatus ?? FinderPermissionManager.shared.evaluateStatus(for: appState.profiles)
        let hasFDA = status.hasFullDiskAccess
        let isFinderEnabled = status.isExtensionEnabled

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle((hasFDA && isFinderEnabled) ? OtterTheme.statusSuccess : OtterTheme.otterAmber)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.permissionStatusTitle))
                        .font(.headline.bold())
                    Text(L10n.t(.finderExtensionSettingsDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appState.refreshFinderPermissionStatus()
                } label: {
                    Label(L10n.t(.refreshStatus), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    // FDA Status Card
                    HStack(spacing: 10) {
                        Circle()
                            .fill(hasFDA ? OtterTheme.statusSuccess : OtterTheme.statusWarning)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(hasFDA ? L10n.t(.permissionFDAGranted) : L10n.t(.permissionFDAMissing))
                                .font(.callout.weight(.medium))
                            Text(hasFDA ? L10n.t(.settingsFdaActiveSubtitle) : L10n.t(.settingsFdaRequiredSubtitle))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !hasFDA {
                            Button {
                                FinderPermissionManager.shared.openFullDiskAccessSettings()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "gearshape")
                                    Text(L10n.t(.permissionOpenSettings))
                                }
                                .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(hasFDA ? OtterTheme.statusSuccess.opacity(0.08) : OtterTheme.statusWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                    // Finder Extension Status Card
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isFinderEnabled ? OtterTheme.statusSuccess : .secondary)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(isFinderEnabled ? L10n.t(.permissionFinderActive) : L10n.t(.permissionFinderInactive))
                                .font(.callout.weight(.medium))
                            Text(isFinderEnabled ? L10n.t(.settingsFinderActiveSubtitle) : L10n.t(.settingsFinderInactiveSubtitle))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !isFinderEnabled {
                            Button {
                                FinderPermissionManager.shared.openSystemExtensionSettings()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "gearshape")
                                    Text(L10n.t(.permissionOpenSettings))
                                }
                                .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(isFinderEnabled ? OtterTheme.statusSuccess.opacity(0.08) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                    // Background Daemon Service (SMAppService) Card
                    let daemonStatus = DaemonServiceManager.shared.serviceStatus
                    let isDaemonActive = daemonStatus == .enabled
                    let isRequiresApproval = daemonStatus == .requiresApproval

                    HStack(spacing: 10) {
                        Circle()
                            .fill(isDaemonActive ? OtterTheme.statusSuccess : (isRequiresApproval ? OtterTheme.statusWarning : .secondary))
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(isDaemonActive ? L10n.t(.daemonStatusActive) : (isRequiresApproval ? L10n.t(.daemonStatusRequiresApproval) : L10n.t(.daemonStatusNotFound)))
                                .font(.callout.weight(.medium))
                            Text(L10n.t(.daemonStatusHeader))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isRequiresApproval {
                            Button {
                                DaemonServiceManager.shared.openSystemSettingsLoginItems()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "gearshape")
                                    Text(L10n.t(.daemonOpenSystemSettings))
                                }
                                .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(OtterTheme.statusWarning)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(isDaemonActive ? OtterTheme.statusSuccess.opacity(0.08) : (isRequiresApproval ? OtterTheme.statusWarning.opacity(0.1) : Color.primary.opacity(0.04)), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .otterCard(padding: 16)
    }
}
