import Foundation

/// Permission and system registration status for OtterKeep Finder Integration.
public struct FinderPermissionStatus: Sendable, Equatable {
    /// Indicates whether the FinderSync extension is registered with macOS PluginKit.
    public let isExtensionRegistered: Bool
    /// Indicates whether the FinderSync extension is enabled (user election `use`) in macOS.
    public let isExtensionEnabled: Bool
    /// List of configured backup profile source paths that lack read/access permissions.
    public let inaccessibleSourcePaths: [String]
    /// Indicates whether full disk access is likely granted.
    public let hasFullDiskAccess: Bool

    /// `true` if all permissions and extension requirements are fulfilled.
    public var isAllGranted: Bool {
        isExtensionRegistered && isExtensionEnabled && inaccessibleSourcePaths.isEmpty
    }
}

/// Utility manager for validating and prompting for macOS permissions required by the Finder Sync integration.
public final class FinderPermissionManager: @unchecked Sendable {
    public static let shared = FinderPermissionManager()

    public static let extensionBundleId = "com.otterkeep.OtterKeepApp.FinderSync"

    private let settingsOpener: FinderSettingsOpening

    /// Creates the manager.
    /// - Parameter settingsOpener: Platform System Settings opener; defaults to the AppKit-backed opener.
    private init(settingsOpener: FinderSettingsOpening = SystemFinderSettingsOpener()) {
        self.settingsOpener = settingsOpener
    }

    /// Evaluates the complete permission status for the Finder extension and configured profile directories.
    public func evaluateStatus(for profiles: [BackupProfile]) -> FinderPermissionStatus {
        let (isRegistered, isEnabled) = checkPluginKitStatus()
        let inaccessible = checkDirectoryAccess(for: profiles)
        let fda = checkFullDiskAccess()

        return FinderPermissionStatus(
            isExtensionRegistered: isRegistered,
            isExtensionEnabled: isEnabled,
            inaccessibleSourcePaths: inaccessible,
            hasFullDiskAccess: fda
        )
    }

    /// Queries `pluginkit` to verify whether the Finder Sync extension is registered and enabled in macOS.
    public func checkPluginKitStatus() -> (isRegistered: Bool, isEnabled: Bool) {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-i", Self.extensionBundleId]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if output.contains(Self.extensionBundleId) {
                // In pluginkit output, "+    <bundleId>" indicates enabled/use election
                let isEnabled = output.contains("+    \(Self.extensionBundleId)") || output.contains("+ \(Self.extensionBundleId)")
                return (isRegistered: true, isEnabled: isEnabled)
            } else {
                return (isRegistered: false, isEnabled: false)
            }
        } catch {
            return (isRegistered: false, isEnabled: false)
        }
    }

    /// Tests read and traverse access to all configured profile source directories.
    public func checkDirectoryAccess(for profiles: [BackupProfile]) -> [String] {
        var inaccessible: [String] = []
        let fm = FileManager.default

        for profile in profiles {
            let path = profile.sourceURL.standardizedFileURL.path
            guard fm.fileExists(atPath: path) else {
                // Missing folder might be an unmounted disk or deleted path
                inaccessible.append(path)
                continue
            }

            if !fm.isReadableFile(atPath: path) {
                inaccessible.append(path)
                continue
            }

            // Probe directory listing to detect TCC / Operation Not Permitted
            do {
                _ = try fm.contentsOfDirectory(atPath: path)
            } catch {
                inaccessible.append(path)
            }
        }

        return inaccessible
    }

    /// Heuristic check for macOS Full Disk Access (reading protected system containers).
    public func checkFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let safariURL = home.appendingPathComponent("Library/Safari")
        if FileManager.default.fileExists(atPath: safariURL.path) {
            return (try? FileManager.default.contentsOfDirectory(atPath: safariURL.path)) != nil
        }
        return true
    }

    // MARK: - Navigation to System Settings

    /// Opens macOS System Settings directly to the Extensions panel.
    @discardableResult
    public func openSystemExtensionSettings() -> Bool {
        let candidateURLs = [
            URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Extensions"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security")
        ].compactMap { $0 }

        for url in candidateURLs {
            if settingsOpener.openSettingsURL(url) {
                return true
            }
        }
        return false
    }

    /// Opens macOS System Settings directly to the Full Disk Access panel.
    @discardableResult
    public func openFullDiskAccessSettings() -> Bool {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            return settingsOpener.openSettingsURL(url)
        }
        return false
    }

    /// Restarts the macOS Finder process so newly enabled or configured extensions take immediate effect.
    public func restartFinder() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
    }
}
