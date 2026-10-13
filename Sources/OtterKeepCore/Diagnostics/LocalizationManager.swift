import Foundation

/// Thread-safe manager handling user preferences and language selection persisted in `~/.otterkeep/settings.json`.
public final class LocalizationManager: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = LocalizationManager()

    private let lock = NSLock()
    private let fileManager = FileManager.default

    /// Real user home directory URL resolved via POSIX getpwuid to avoid sandbox redirection discrepancies.
    public var realUserHome: URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    /// URL to the `settings.json` file.
    public var settingsFileURL: URL {
        realUserHome.appendingPathComponent(".otterkeep/settings.json")
    }

    /// Sandboxed container settings JSON path.
    public var containerSettingsFileURL: URL {
        realUserHome.appendingPathComponent("Library/Containers/com.otterkeep.OtterKeepApp.FinderSync/Data/.otterkeep/settings.json")
    }

    private var currentSettings: AppSettings

    private init() {
        let home: URL
        if let pw = getpwuid(getuid()) {
            home = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }

        var loaded: AppSettings?
        let candidateURLs = [
            home.appendingPathComponent(".otterkeep/settings.json"),
            home.appendingPathComponent("Library/Containers/com.otterkeep.OtterKeepApp.FinderSync/Data/.otterkeep/settings.json"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".otterkeep/settings.json")
        ]

        for url in candidateURLs {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                loaded = decoded
                break
            }
        }
        self.currentSettings = loaded ?? AppSettings()
    }

    /// Gets or sets current application settings thread-safely.
    public var settings: AppSettings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentSettings
        }
        set {
            lock.lock()
            currentSettings = newValue
            saveSettingsUnlocked()
            lock.unlock()
        }
    }

    /// Gets or sets the configured application language.
    public var currentLanguage: AppLanguage {
        get { settings.language }
        set {
            lock.lock()
            currentSettings.language = newValue
            saveSettingsUnlocked()
            lock.unlock()
        }
    }

    /// Gets or sets the configured application theme appearance mode.
    public var currentTheme: AppThemeMode {
        get { settings.themeMode }
        set {
            lock.lock()
            currentSettings.themeMode = newValue
            saveSettingsUnlocked()
            lock.unlock()
        }
    }

    /// Gets or sets whether the application starts minimized with only the menu bar icon visible.
    public var startMinimized: Bool {
        get { settings.startMinimized }
        set {
            lock.lock()
            currentSettings.startMinimized = newValue
            saveSettingsUnlocked()
            lock.unlock()
        }
    }

    /// Resolves the effective active language, resolving `.system` to either `.hungarian` or `.english`.
    public var effectiveLanguage: AppLanguage {
        let lang = currentLanguage
        if lang != .system { return lang }
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferred.hasPrefix("hu") ? .hungarian : .english
    }

    private func saveSettingsUnlocked() {
        let dir = settingsFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(currentSettings) {
            try? data.write(to: settingsFileURL, options: .atomic)

            let containerDir = containerSettingsFileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: containerDir.path) {
                try? fileManager.createDirectory(at: containerDir, withIntermediateDirectories: true)
            }
            try? data.write(to: containerSettingsFileURL, options: .atomic)
        }
    }
}

