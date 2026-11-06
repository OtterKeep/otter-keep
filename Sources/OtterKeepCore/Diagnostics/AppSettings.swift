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
    /// Whether biometric authentication (Touch ID / passcode) is enabled.
    public var isBiometricsEnabled: Bool
    /// Require biometric verification before restoring files or folders.
    public var requireBiometricsForRestore: Bool
    /// Require biometric verification before permanently deleting a backup profile.
    public var requireBiometricsForProfileDeletion: Bool
    /// Require biometric verification before revealing encryption keys or passphrases.
    public var requireBiometricsForKeyReveal: Bool
    /// Require hardware Secure Enclave protection when storing passphrases in the Keychain.
    public var useSecureEnclaveForKeychain: Bool

    /// Initializes an `AppSettings` record.
    /// - Parameters:
    ///   - language: Selected language (default: `.system`).
    ///   - launchAtLogin: Whether Launch at Login is enabled (default: `false`).
    ///   - startMinimized: Whether the app starts minimized to menu bar (default: `false`).
    ///   - debugFileLoggingEnabled: Whether debug file logging is enabled (default: `false`).
    ///   - finderIntegrationEnabled: Whether Finder integration is enabled (default: `true`).
    ///   - themeMode: Selected appearance theme (default: `.system`).
    ///   - isBiometricsEnabled: Whether biometric authentication is enabled (default: `false`).
    ///   - requireBiometricsForRestore: Require biometrics on restore (default: `true`).
    ///   - requireBiometricsForProfileDeletion: Require biometrics on profile delete (default: `true`).
    ///   - requireBiometricsForKeyReveal: Require biometrics on key reveal (default: `true`).
    ///   - useSecureEnclaveForKeychain: Use hardware Secure Enclave for keys (default: `false`).
    public init(
        language: AppLanguage = .system,
        launchAtLogin: Bool = false,
        startMinimized: Bool = false,
        debugFileLoggingEnabled: Bool = false,
        finderIntegrationEnabled: Bool = true,
        themeMode: AppThemeMode = .system,
        isBiometricsEnabled: Bool = false,
        requireBiometricsForRestore: Bool = true,
        requireBiometricsForProfileDeletion: Bool = true,
        requireBiometricsForKeyReveal: Bool = true,
        useSecureEnclaveForKeychain: Bool = false
    ) {
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.startMinimized = startMinimized
        self.debugFileLoggingEnabled = debugFileLoggingEnabled
        self.finderIntegrationEnabled = finderIntegrationEnabled
        self.themeMode = themeMode
        self.isBiometricsEnabled = isBiometricsEnabled
        self.requireBiometricsForRestore = requireBiometricsForRestore
        self.requireBiometricsForProfileDeletion = requireBiometricsForProfileDeletion
        self.requireBiometricsForKeyReveal = requireBiometricsForKeyReveal
        self.useSecureEnclaveForKeychain = useSecureEnclaveForKeychain
    }

    enum CodingKeys: String, CodingKey {
        case language
        case launchAtLogin
        case startMinimized
        case debugFileLoggingEnabled
        case finderIntegrationEnabled
        case themeMode
        case isBiometricsEnabled
        case requireBiometricsForRestore
        case requireBiometricsForProfileDeletion
        case requireBiometricsForKeyReveal
        case useSecureEnclaveForKeychain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.startMinimized = try container.decodeIfPresent(Bool.self, forKey: .startMinimized) ?? false
        self.debugFileLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugFileLoggingEnabled) ?? false
        self.finderIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .finderIntegrationEnabled) ?? true
        self.themeMode = try container.decodeIfPresent(AppThemeMode.self, forKey: .themeMode) ?? .system
        self.isBiometricsEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBiometricsEnabled) ?? false
        self.requireBiometricsForRestore = try container.decodeIfPresent(Bool.self, forKey: .requireBiometricsForRestore) ?? true
        self.requireBiometricsForProfileDeletion = try container.decodeIfPresent(Bool.self, forKey: .requireBiometricsForProfileDeletion) ?? true
        self.requireBiometricsForKeyReveal = try container.decodeIfPresent(Bool.self, forKey: .requireBiometricsForKeyReveal) ?? true
        self.useSecureEnclaveForKeychain = try container.decodeIfPresent(Bool.self, forKey: .useSecureEnclaveForKeychain) ?? false
    }
}

