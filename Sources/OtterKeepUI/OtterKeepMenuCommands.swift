import SwiftUI
import AppKit
import OtterKeepCore

/// Full macOS native menu bar commands, standard keyboard shortcuts, and menu hierarchies for OtterKeep.
public struct OtterKeepMenuCommands: Commands {
    private let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some Commands {
        // MARK: - App Menu (OtterKeep)
        CommandGroup(replacing: .appInfo) {
            Button(L10n.t(.aboutWindowTitle)) {
                AboutWindowController.shared.show()
            }

            Button(L10n.t(.menuCheckForUpdates)) {
                appState.checkForSoftwareUpdates(silent: false)
            }
            .disabled(appState.isCheckingForSoftwareUpdates)
        }

        CommandGroup(replacing: .appSettings) {
            Button(L10n.t(.menuPreferences)) {
                appState.showPreferencesModal = true
                WindowManager.showAndFocusMainWindow()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button(L10n.t(.aboutWindowTitle)) {
                AboutWindowController.shared.show()
            }
        }

        // MARK: - File (Fájl)
        CommandGroup(replacing: .newItem) {
            Button(L10n.t(.menuNewProfile)) {
                appState.resetNewProfileDraft()
                appState.showNewProfileSheet = true
                WindowManager.showAndFocusMainWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.t(.menuRenameProfile)) {
                if let prof = appState.selectedProfile {
                    appState.renameProfileName = prof.name
                    appState.showRenameProfileSheet = true
                    WindowManager.showAndFocusMainWindow()
                }
            }
            .disabled(appState.selectedProfile == nil)

            Divider()

            Button(L10n.t(.menuExportConfig)) {
                appState.exportConfiguration()
            }
            .keyboardShortcut("e", modifiers: .command)

            Button(L10n.t(.menuImportConfig)) {
                appState.importConfiguration()
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button(L10n.t(.menuCloseWindow)) {
                if let keyWindow = NSApp.keyWindow {
                    keyWindow.orderOut(nil)
                } else {
                    NSApp.mainWindow?.orderOut(nil)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        // MARK: - Mentés & Műveletek (Backup & Actions)
        CommandMenu(L10n.t(.menuBackupActions)) {
            Button(L10n.t(.menuRunBackupSelected)) {
                appState.startBackup()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(appState.selectedProfile.map { appState.isBackupRunning(for: $0.id) } ?? true)

            Button(L10n.t(.menuRunAllBackups)) {
                appState.startBackupAll()
            }
            .keyboardShortcut("b", modifiers: [.shift, .command])
            .disabled(appState.profiles.isEmpty)

            Button(L10n.t(.menuRunPhotosBackup)) {
                appState.startPhotosBackup()
            }
            .keyboardShortcut("p", modifiers: [.option, .command])
            .disabled(appState.isPhotosBackupRunning)

            Divider()

            Button(L10n.t(.menuDryRunBackup)) {
                appState.performDryRun()
                WindowManager.showAndFocusMainWindow()
            }
            .keyboardShortcut("d", modifiers: [.option, .command])
            .disabled(appState.selectedProfile.map { appState.isBackupRunning(for: $0.id) } ?? true || appState.isDryRunRunning)

            Button(L10n.t(.menuCancelBackup)) {
                appState.cancelBackup()
                appState.cancelPhotosBackup()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!appState.isBackupRunning && !appState.isPhotosBackupRunning && !appState.isReplicationRunning)

            Divider()

            Button(L10n.t(.menuBackupInspector)) {
                appState.showInspectorModal = true
                WindowManager.showAndFocusMainWindow()
            }
            .keyboardShortcut("i", modifiers: [.option, .command])
        }

        // MARK: - View (Nézet)
        CommandMenu(L10n.t(.menuView)) {
            Button(L10n.t(.menuViewOverview)) {
                if let id = appState.selectedProfileId ?? appState.profiles.first?.id {
                    appState.selectProfile(id: id)
                    appState.activeProfileTab = .overview
                    appState.activeNavigation = .profile(id)
                    WindowManager.showAndFocusMainWindow()
                }
            }
            .keyboardShortcut("1", modifiers: .command)

            Button(L10n.t(.menuViewTimeMachine)) {
                if let id = appState.selectedProfileId ?? appState.profiles.first?.id {
                    appState.selectProfile(id: id)
                    appState.activeProfileTab = .timeMachine
                    appState.activeNavigation = .profile(id)
                    WindowManager.showAndFocusMainWindow()
                }
            }
            .keyboardShortcut("2", modifiers: .command)

            Button(L10n.t(.profileSettingsTitle)) {
                appState.showProfileSettingsModal = true
                WindowManager.showAndFocusMainWindow()
            }
            .keyboardShortcut("3", modifiers: .command)

            Button(L10n.t(.menuViewPhotos)) {
                appState.activeNavigation = .photos
                WindowManager.showAndFocusMainWindow()
            }
            .keyboardShortcut("4", modifiers: .command)

            Button(L10n.t(.menuSystemLogs)) {
                appState.showSystemLogsModal = true
                WindowManager.showAndFocusMainWindow()
            }
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button(L10n.t(.menuToggleTheme)) {
                switch appState.currentTheme {
                case .system: appState.currentTheme = .light
                case .light: appState.currentTheme = .dark
                case .dark: appState.currentTheme = .system
                }
            }
            .keyboardShortcut("t", modifiers: .command)

            Button(L10n.t(.menuRefreshData)) {
                appState.loadSnapshots(force: true)
                appState.loadPhotosSnapshots(force: true)
                appState.refreshLogs()
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        // MARK: - Window (Ablak)
        CommandGroup(after: .windowList) {
            Button(L10n.t(.menuMainWindow)) {
                WindowManager.showAndFocusMainWindow()
            }
            .keyboardShortcut("0", modifiers: [.option, .command])
        }

        // MARK: - Help (Súgó)
        CommandGroup(replacing: .help) {
            Button(L10n.t(.menuDocumentation)) {
                if let url = URL(string: "https://github.com/OtterKeep/otter-keep#readme") {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("?", modifiers: .command)

            Button(L10n.t(.menuReleaseNotes)) {
                if let url = URL(string: "https://github.com/OtterKeep/otter-keep/releases") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button(L10n.t(.menuRevealLogs)) {
                let logsDir = FileManager.default.fileExists(atPath: LogManager.shared.debugLogsDirectory.path)
                    ? LogManager.shared.debugLogsDirectory
                    : LogManager.shared.logDirectory
                NSWorkspace.shared.activateFileViewerSelecting([logsDir])
            }
            .keyboardShortcut("l", modifiers: [.shift, .command])

            Button(L10n.t(.menuSaveSupportBundle)) {
                Task {
                    if let zipURL = try? await SanctuarySupportBundleExporter.shared.exportSupportBundle() {
                        NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                    }
                }
            }

            Divider()

            Button(L10n.t(.menuReportIssue)) {
                if let url = URL(string: "https://github.com/OtterKeep/otter-keep/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        // MARK: - Native macOS Sidebar Toggle Commands
        SidebarCommands()

        // MARK: - Standard Text Editing Commands
        TextEditingCommands()
    }
}
