import Foundation

/// Supported user interface application languages.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    /// Follows the operating system's preferred language settings.
    case system = "system"
    /// Hungarian language.
    case hungarian = "hu"
    /// English language.
    case english = "en"

    /// Localized display name for language selection menus.
    public var displayName: String {
        switch self {
        case .system:
            let osIsHu = Locale.preferredLanguages.first?.hasPrefix("hu") ?? false
            return osIsHu ? "Rendszer nyelve (Magyar)" : "System Default (English)"
        case .hungarian:
            return "Magyar (Hungarian)"
        case .english:
            return "English"
        }
    }
}

/// Persistent user settings configuration.
public struct AppSettings: Codable, Sendable, Equatable {
    /// Selected interface language.
    public var language: AppLanguage
    /// Whether the application is configured to launch automatically at login.
    public var launchAtLogin: Bool
    /// Whether the application should start minimized with only the menu bar icon visible.
    public var startMinimized: Bool
    /// Whether debug diagnostic file logging (.log) is enabled.
    public var debugFileLoggingEnabled: Bool
    /// Whether Finder context menu integration is enabled.
    public var finderIntegrationEnabled: Bool
    /// Selected application theme appearance mode.
    public var themeMode: AppThemeMode

    /// Initializes an `AppSettings` record.
    /// - Parameters:
    ///   - language: Selected language (default: `.system`).
    ///   - launchAtLogin: Whether Launch at Login is enabled (default: `false`).
    ///   - startMinimized: Whether the app starts minimized to menu bar (default: `false`).
    ///   - debugFileLoggingEnabled: Whether debug file logging is enabled (default: `false`).
    ///   - finderIntegrationEnabled: Whether Finder integration is enabled (default: `true`).
    ///   - themeMode: Selected appearance theme (default: `.system`).
    public init(
        language: AppLanguage = .system,
        launchAtLogin: Bool = false,
        startMinimized: Bool = false,
        debugFileLoggingEnabled: Bool = false,
        finderIntegrationEnabled: Bool = true,
        themeMode: AppThemeMode = .system
    ) {
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.startMinimized = startMinimized
        self.debugFileLoggingEnabled = debugFileLoggingEnabled
        self.finderIntegrationEnabled = finderIntegrationEnabled
        self.themeMode = themeMode
    }

    enum CodingKeys: String, CodingKey {
        case language
        case launchAtLogin
        case startMinimized
        case debugFileLoggingEnabled
        case finderIntegrationEnabled
        case themeMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.startMinimized = try container.decodeIfPresent(Bool.self, forKey: .startMinimized) ?? false
        self.debugFileLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugFileLoggingEnabled) ?? false
        self.finderIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .finderIntegrationEnabled) ?? true
        self.themeMode = try container.decodeIfPresent(AppThemeMode.self, forKey: .themeMode) ?? .system
    }
}

