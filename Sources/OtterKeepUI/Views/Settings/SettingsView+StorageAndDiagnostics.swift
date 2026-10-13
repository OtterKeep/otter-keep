import SwiftUI
import AppKit
import OtterKeepCore

extension SettingsView {
    var persistentFilesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text(L10n.t(.settingsStorageSection))
                    .font(.title2.bold())
            }

            // Profiles file
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.settingsProfilesPathLabel))
                        .font(.body.weight(.medium))
                    Text(ProfileStore.shared.profilesFileURL.path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(L10n.t(.settingsOpenFolder)) {
                    NSWorkspace.shared.activateFileViewerSelecting([ProfileStore.shared.profilesFileURL])
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Divider()

            // Apple Photos configuration file
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.settingsPhotosConfigTitle))
                        .font(.body.weight(.medium))
                    Text(PhotosProfileStore.shared.configFileURL.path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(L10n.t(.settingsOpenFolder)) {
                    NSWorkspace.shared.activateFileViewerSelecting([PhotosProfileStore.shared.configFileURL])
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Divider()

            // Persistent log file
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.settingsLogsPathLabel))
                        .font(.body.weight(.medium))
                    Text(LogManager.shared.logFileURL.path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(L10n.t(.settingsOpenFolder)) {
                    NSWorkspace.shared.activateFileViewerSelecting([LogManager.shared.logFileURL])
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var debugLoggingBinding: Binding<Bool> {
        Binding(
            get: { appState.isDebugFileLoggingEnabled },
            set: { appState.isDebugFileLoggingEnabled = $0 }
        )
    }

    var debugLoggingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "ladybug.fill")
                        .font(.title2)
                        .foregroundStyle(OtterTheme.otterAmber)
                    Text(L10n.t(.settingsDebugLoggingTitle))
                        .font(.title2.bold())
                }

                Spacer()

                // Status Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isDebugFileLoggingEnabled ? OtterTheme.statusSuccess : .secondary)
                        .frame(width: 8, height: 8)
                    Text(appState.isDebugFileLoggingEnabled ? L10n.t(.settingsDebugLoggingActive) : L10n.t(.settingsDebugLoggingInactive))
                        .font(.subheadline.bold())
                        .foregroundStyle(appState.isDebugFileLoggingEnabled ? OtterTheme.statusSuccess : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (appState.isDebugFileLoggingEnabled ? OtterTheme.statusSuccess : Color.secondary).opacity(0.12),
                    in: Capsule()
                )
            }

            Text(L10n.t(.settingsDebugLoggingDesc))
                .font(.body)
                .foregroundStyle(.secondary)

            Toggle(isOn: debugLoggingBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.settingsDebugLoggingToggle))
                        .font(.body.weight(.medium))
                }
            }
            .toggleStyle(.switch)
            .padding(.vertical, 2)

            if appState.isDebugFileLoggingEnabled, let logURL = (appState.currentDebugLogFileURL ?? LogManager.shared.currentDebugLogFileURL) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t(.settingsDebugLoggingPathLabel))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(logURL.path(percentEncoded: false))
                                .font(.callout.monospaced())
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([logURL])
                        } label: {
                            Label(L10n.t(.settingsOpenFolder), systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            appState.copyDebugLogPath()
                        } label: {
                            Label(L10n.t(.settingsDebugCopyPath), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            NSWorkspace.shared.open(LogManager.shared.debugLogsDirectory)
                        } label: {
                            Label(L10n.t(.settingsDebugOpenLogsFolder), systemImage: "folder.badge.gearshape")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }

            // Privacy notice
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(OtterTheme.oceanicTeal)
                    .font(.callout)
                Text(L10n.t(.settingsDebugLoggingPrivacyNotice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}
