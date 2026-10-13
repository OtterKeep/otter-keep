import SwiftUI
import AppKit
import OtterKeepCore

extension SettingsView {
    var softwareUpdatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.title2)
                        .foregroundStyle(OtterTheme.oceanicTeal)
                    Text(L10n.t(.settingsUpdatesSection))
                        .font(.title2.bold())
                }

                Spacer()

                Text(String(format: L10n.t(.settingsCurrentVersionFormat), SoftwareUpdateCoordinator.shared.currentVersion, SoftwareUpdateCoordinator.shared.currentBuild))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(L10n.t(.settingsUpdatesDesc))
                .font(.body)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { appState.automaticallyChecksForUpdates },
                set: { appState.automaticallyChecksForUpdates = $0 }
            )) {
                Text(L10n.t(.settingsAutoUpdateToggle))
                    .font(.body.weight(.medium))
            }
            .toggleStyle(.switch)
            .padding(.vertical, 2)

            HStack(spacing: 12) {
                Button {
                    appState.checkForSoftwareUpdates()
                } label: {
                    HStack(spacing: 6) {
                        if appState.isCheckingForSoftwareUpdates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(L10n.t(.settingsCheckForUpdatesButton))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(appState.isCheckingForSoftwareUpdates)

                if let status = appState.softwareUpdateStatusMessage {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(appState.softwareUpdateAvailableInfo != nil ? OtterTheme.statusSuccess : .secondary)
                }
            }

            if let update = appState.softwareUpdateAvailableInfo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("OtterKeep v\(update.version)")
                            .font(.headline)
                        Spacer()
                        Text("Build \(update.buildNumber)")
                            .font(.subheadline.bold().monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OtterTheme.statusSuccess.opacity(0.15), in: Capsule())
                            .foregroundStyle(OtterTheme.statusSuccess)
                    }
                    if !update.releaseNotes.isEmpty {
                        Text(update.releaseNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(L10n.t(.settingsDownloadInBrowser)) {
                        NSWorkspace.shared.open(update.downloadURL)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OtterTheme.statusSuccess.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .otterCard(padding: 20)
    }

    var aboutSection: some View {
        HStack(spacing: 16) {
            OtterKeepLogoView(size: 52, withGlow: true, withBorder: true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("OtterKeep")
                        .font(.headline.bold())

                    Text("v\(CoreEngine.version) (Build \(CoreEngine.buildNumber))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(OtterTheme.oceanicTeal.opacity(0.15), in: Capsule())
                        .foregroundStyle(OtterTheme.oceanicTeal)
                }

                Text("„Keep what you love close to your chest.”")
                    .font(.caption.italic())
                    .foregroundStyle(OtterTheme.otterAmber)

                Text("Subsystems: Storage v\(CoreEngine.storageVersion) • DB v\(CoreEngine.databaseVersion) • Core v\(CoreEngine.coreVersion) • UI v\(CoreEngine.uiVersion) • CLI v\(CoreEngine.cliVersion)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)

            }

            Spacer()

            Button {
                AboutWindowController.shared.show()
            } label: {
                Label(L10n.t(.aboutWindowTitle), systemImage: "info.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .otterCard(padding: 16)
    }
}
