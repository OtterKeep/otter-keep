import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension AppState {
    // MARK: - Configuration Export & Import

    /// Programmatically exports all profiles, settings, and photos configuration to a specified URL.
    @MainActor
    public func exportConfiguration(to url: URL) throws {
        try ProfileStore.shared.exportConfiguration(
            to: url,
            profiles: self.profiles,
            settings: LocalizationManager.shared.settings,
            photosConfig: self.photosConfig
        )
        LogManager.shared.log("Configuration exported successfully to: '\(url.path)'", level: .info, category: "Config")
        refreshLogs()
    }

    /// Programmatically imports configuration archive from a specified URL.
    @MainActor
    public func importConfiguration(from url: URL) throws {
        let archive = try ProfileStore.shared.importConfiguration(from: url)
        self.profiles = archive.profiles
        if let firstId = archive.profiles.first?.id {
            self.selectedProfileId = firstId
            self.activeNavigation = .profile(firstId)
        }
        self.currentTheme = archive.settings.themeMode
        self.currentLanguage = archive.settings.language
        self.launchAtLoginEnabled = archive.settings.launchAtLogin
        self.startMinimized = archive.settings.startMinimized
        self.isDebugFileLoggingEnabled = archive.settings.debugFileLoggingEnabled
        self.isFinderIntegrationEnabled = archive.settings.finderIntegrationEnabled
        if let photos = archive.photosConfig {
            self.photosConfig = photos
        }
        refreshVolumeEvaluation()
        loadSnapshots(force: true)
        loadPhotosSnapshots(force: true)
        LogManager.shared.log("Configuration imported successfully from: '\(url.path)' (\(archive.profiles.count) profile(s))", level: .info, category: "Config")
        refreshLogs()
    }

    /// Interactive NSSavePanel prompt for exporting configuration to JSON.
    @MainActor
    public func exportConfiguration() {
        let panel = NSSavePanel()
        panel.title = L10n.t(.exportConfigTitle)
        panel.prompt = L10n.t(.save)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        panel.nameFieldStringValue = "OtterKeep-Config-\(dateStr).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let targetWindow = NSApp.keyWindow?.attachedSheet ?? NSApp.keyWindow ?? NSApp.mainWindow

        let runExport: (URL) -> Void = { [weak self] url in
            guard let self = self else { return }
            do {
                try self.exportConfiguration(to: url)
                self.showSuccess(L10n.t(.exportConfigSuccessMessage))
            } catch {
                self.showError(L10n.format(.exportConfigErrorMessage, error.localizedDescription))
            }
        }

        if let window = targetWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    runExport(url)
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                runExport(url)
            }
        }
    }

    /// Interactive NSOpenPanel prompt for importing configuration from JSON.
    @MainActor
    public func importConfiguration() {
        let panel = NSOpenPanel()
        panel.title = L10n.t(.importConfigTitle)
        panel.prompt = L10n.t(.confirm)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let targetWindow = NSApp.keyWindow?.attachedSheet ?? NSApp.keyWindow ?? NSApp.mainWindow

        let runImport: (URL) -> Void = { [weak self] url in
            guard let self = self else { return }
            do {
                try self.importConfiguration(from: url)
                self.showSuccess(L10n.t(.importConfigSuccessMessage))
            } catch {
                self.showError(L10n.format(.importConfigErrorMessage, error.localizedDescription))
            }
        }

        if let window = targetWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    runImport(url)
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                runImport(url)
            }
        }
    }
}

// MARK: - Rule321Compliance Presentation Extensions

extension Rule321Compliance {
    public var badgeText: String {
        switch self {
        case .compliant: return L10n.t(.rule321StatusCompliant)
        case .partial: return L10n.t(.rule321StatusPartial)
        case .localOnly: return L10n.t(.rule321StatusLocalOnly)
        }
    }

    public var color: Color {
        switch self {
        case .compliant: return OtterTheme.oceanicTeal
        case .partial: return OtterTheme.statusWarning
        case .localOnly: return OtterTheme.otterAmber
        }
    }
}

