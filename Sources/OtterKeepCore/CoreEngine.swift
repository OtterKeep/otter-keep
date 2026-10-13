import Foundation

/// Core namespace and versioning umbrella for the OtterKeep engine.
public struct CoreEngine: Sendable {
    // MARK: - Version Manifest (generated from version.json by scripts/sync_version.sh)
    // <version-manifest:begin>
    /// Semantic version identifier of the OtterKeep application (main product version).
    public static let version = "1.7.1"

    /// Internal build sequence number.
    public static let buildNumber = "1701"

    /// Subsystem versions:
    public static let storageVersion = "1.3.0"
    public static let databaseVersion = "1.3.1"
    public static let coreVersion = "1.7.1"
    public static let uiVersion = "1.7.1"
    public static let cliVersion = "1.3.1"
    public static let finderSyncVersion = "1.0.1"
    // <version-manifest:end>

    /// Structured dictionary of all subsystem components and their respective SemVer versions.
    public static var componentVersions: [String: String] {
        [
            "OtterKeepStorage": storageVersion,
            "OtterKeepDatabase": databaseVersion,
            "OtterKeepCore": coreVersion,
            "OtterKeepUI": uiVersion,
            "OtterKeepCLI": cliVersion,
            "OtterKeepFinderSyncExtension": finderSyncVersion
        ]
    }

    /// Formatted single-line summary of all component versions.
    public static var componentVersionsFormatted: String {
        "Storage: v\(storageVersion), Database: v\(databaseVersion), Core: v\(coreVersion), UI: v\(uiVersion), CLI: v\(cliVersion)"
    }

    /// Application display name.
    public static let appName = "OtterKeep"

    /// Main macOS bundle identifier.
    public static let bundleIdentifier = "com.otterkeep.desktop"

    /// Initializes a `CoreEngine` instance.
    public init() {}
}

