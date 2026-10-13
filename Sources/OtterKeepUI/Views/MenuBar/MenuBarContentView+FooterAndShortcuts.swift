import SwiftUI
import AppKit
import OtterKeepCore
import OtterKeepStorage

extension MenuBarContentView {
    // MARK: - Footer Controls
    var footerControls: some View {
        HStack(spacing: 8) {
            Button {
                openMainWindow()
            } label: {
                Label(L10n.t(.menuBarOpenApp), systemImage: "macwindow")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Spacer()

            // Check for Updates button
            Button {
                appState.checkForSoftwareUpdates(silent: false)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .rotationEffect(appState.isCheckingForSoftwareUpdates ? .degrees(360) : .zero)
                    .animation(appState.isCheckingForSoftwareUpdates ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: appState.isCheckingForSoftwareUpdates)
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarCheckUpdates))

            Button {
                AboutWindowController.shared.show()
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t(.aboutWindowTitle))

            Button {
                openLogs()
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarOpenLogs))

            Divider()
                .frame(height: 12)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.caption)
                    .foregroundStyle(OtterTheme.statusError)
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarQuit))
        }
        .padding(.top, 2)
    }

    func openMainWindow() {
        WindowManager.showAndFocusMainWindow()
    }

    func openRestoreExplorer() {
        if let sel = appState.selectedProfileId ?? appState.profiles.first?.id {
            appState.selectProfile(id: sel)
            appState.activeProfileTab = .timeMachine
        }
        WindowManager.showAndFocusMainWindow()
    }

    func openSettings() {
        appState.activeNavigation = .settings
        WindowManager.showAndFocusMainWindow()
    }

    private func openLogs() {
        appState.activeNavigation = .logs
        WindowManager.showAndFocusMainWindow()
    }

    func cycleTheme() {
        switch appState.currentTheme {
        case .system:
            appState.currentTheme = .light
        case .light:
            appState.currentTheme = .dark
        case .dark:
            appState.currentTheme = .system
        }
    }
}
