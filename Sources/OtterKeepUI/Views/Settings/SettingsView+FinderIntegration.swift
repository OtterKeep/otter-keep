import SwiftUI
import AppKit
import OtterKeepCore

extension SettingsView {
    private var finderIntegrationBinding: Binding<Bool> {
        Binding(
            get: { appState.isFinderIntegrationEnabled },
            set: { appState.isFinderIntegrationEnabled = $0 }
        )
    }

    var finderIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundStyle(OtterTheme.otterAmber)
                    Text(L10n.t(.finderExtensionSettingsTitle))
                        .font(.title2.bold())
                }

                Spacer()

                // Global Status Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isFinderIntegrationEnabled ? OtterTheme.statusSuccess : .secondary)
                        .frame(width: 8, height: 8)
                    Text(appState.isFinderIntegrationEnabled ? L10n.t(.finderExtensionActive) : L10n.t(.finderExtensionDisabled))
                        .font(.subheadline.bold())
                        .foregroundStyle(appState.isFinderIntegrationEnabled ? OtterTheme.statusSuccess : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (appState.isFinderIntegrationEnabled ? OtterTheme.statusSuccess : Color.secondary).opacity(0.12),
                    in: Capsule()
                )
            }

            Text(L10n.t(.finderExtensionSettingsDesc))
                .font(.body)
                .foregroundStyle(.secondary)

            // Master Toggle Switch
            Toggle(isOn: finderIntegrationBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.finderExtensionToggle))
                        .font(.body.weight(.medium))
                    Text(L10n.t(.finderExtensionToggleDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.vertical, 4)

            // Permission & Extension Diagnostics Panel
            if appState.isFinderIntegrationEnabled {
                if let status = appState.finderPermissionStatus {
                    if !status.isExtensionEnabled {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.t(.finderExtensionNotEnabledSystem))
                                    .font(.callout.bold())
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    Button {
                                        FinderPermissionManager.shared.openSystemExtensionSettings()
                                    } label: {
                                        Label(L10n.t(.finderExtensionOpenSettings), systemImage: "gearshape")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)

                                    Button {
                                        appState.refreshFinderPermissionStatus()
                                    } label: {
                                        Label(L10n.t(.refreshStatus), systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    } else if !status.inaccessibleSourcePaths.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.t(.finderExtensionInaccessibleFolders))
                                    .font(.callout.bold())
                                ForEach(status.inaccessibleSourcePaths, id: \.self) { p in
                                    Text("• \(p)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Button {
                                        FinderPermissionManager.shared.openFullDiskAccessSettings()
                                    } label: {
                                        Label(L10n.t(.finderExtensionOpenFDA), systemImage: "lock.open")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)

                                    Button {
                                        appState.refreshFinderPermissionStatus()
                                    } label: {
                                        Label(L10n.t(.refreshStatus), systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(OtterTheme.statusSuccess)
                            Text(L10n.t(.finderExtensionAllPermissionsGranted))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                FinderPermissionManager.shared.restartFinder()
                            } label: {
                                Label(L10n.t(.finderExtensionRestartFinder), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(OtterTheme.statusSuccess.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t(.finderExtensionMonitoredFolders))
                    .font(.body.weight(.medium))
                    .foregroundStyle(appState.isFinderIntegrationEnabled ? .primary : .secondary)

                ForEach(appState.profiles) { prof in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(appState.isFinderIntegrationEnabled ? .blue : .secondary)
                        Text(prof.name)
                            .font(.callout.bold())
                            .foregroundStyle(appState.isFinderIntegrationEnabled ? .primary : .secondary)
                        Text("(\(prof.sourceURL.path))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .opacity(appState.isFinderIntegrationEnabled ? 1.0 : 0.6)

            Text(L10n.t(.finderExtensionEnableHint))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}
