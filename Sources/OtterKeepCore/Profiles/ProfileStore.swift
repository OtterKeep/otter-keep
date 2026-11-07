import Foundation
import OtterKeepDatabase

/// Thread-safe persistence store managing backup profile configurations stored in `~/.otterkeep/profiles.json`.
public final class ProfileStore: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = ProfileStore()

    private let lock = NSLock()
    private let fileManager = FileManager.default

    /// Real user home directory URL resolved via POSIX getpwuid to avoid sandbox redirection discrepancies.
    public var realUserHome: URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    /// Base storage directory (`~/.otterkeep/`).
    public var storageDirectory: URL {
        realUserHome.appendingPathComponent(".otterkeep", isDirectory: true)
    }

    /// Full path to the `profiles.json` configuration file.
    public var profilesFileURL: URL {
        storageDirectory.appendingPathComponent("profiles.json")
    }

    private let centralDatabase: CentralDatabase

    /// Full path to the central SQLite database (`~/.otterkeep/central.sqlite`).
    public var centralDatabasePath: String {
        centralDatabase.databasePath
    }

    private init(centralDatabase: CentralDatabase = .shared) {
        self.centralDatabase = centralDatabase
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        let dir = storageDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Enforce strict 0700 permissions on ~/.otterkeep/
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }

    /// Loads all configured backup profiles from the central SQLite database or disk. If no profiles exist, creates and persists a default initial profile.
    /// - Returns: Array of `BackupProfile` instances.
    public func loadProfiles() -> [BackupProfile] {
        lock.lock()
        defer { lock.unlock() }

        createDirectoryIfNeeded()
        return loadProfilesUnlocked()
    }

    /// Resolves a backup profile by its name or UUID string (case-insensitive).
    /// - Parameter query: Profile name or UUID string.
    /// - Returns: The matching `BackupProfile`, or `nil` if not found.
    public func findProfile(namedOrId query: String) -> BackupProfile? {
        let profiles = loadProfiles()
        let lowerQuery = query.lowercased()
        return profiles.first {
            $0.name.lowercased() == lowerQuery || $0.id.uuidString.lowercased() == lowerQuery
        }
    }

    /// Persists an array of backup profiles to disk and the central database atomically.
    /// - Parameter profiles: Array of profiles to write.
    public func saveProfiles(_ profiles: [BackupProfile]) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveProfilesUnlocked(profiles)
    }

    private func saveProfilesUnlocked(_ profiles: [BackupProfile]) throws {
        createDirectoryIfNeeded()

        // 1. Persist to Central SQLite Database
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var records: [CentralProfileRecord] = []
        for profile in profiles {
            if let data = try? encoder.encode(profile),
               let jsonStr = String(data: data, encoding: .utf8) {
                records.append(CentralProfileRecord(
                    id: profile.id.uuidString,
                    name: profile.name,
                    jsonData: jsonStr,
                    createdAt: Date(),
                    updatedAt: Date()
                ))
            }
        }
        try centralDatabase.replaceAllProfileRecords(records)

        // 2. Persist to profiles.json for JSON portability and legacy/FinderSync support
        let data = try encoder.encode(profiles)
        try data.write(to: profilesFileURL, options: .atomic)
        // Enforce strict 0600 permissions on profiles.json
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profilesFileURL.path)

        // Mirror to sandboxed FinderSync AppExtension container
        let realHome: URL
        if let pw = getpwuid(getuid()) {
            realHome = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        } else {
            realHome = fileManager.homeDirectoryForCurrentUser
        }
        let containerDir = realHome
            .appendingPathComponent("Library/Containers/com.otterkeep.OtterKeepApp.FinderSync/Data/.otterkeep", isDirectory: true)
        if !fileManager.fileExists(atPath: containerDir.path) {
            try? fileManager.createDirectory(at: containerDir, withIntermediateDirectories: true)
        }
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: containerDir.path)
        let containerFile = containerDir.appendingPathComponent("profiles.json")
        try? data.write(to: containerFile, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: containerFile.path)

        // Broadcast profile change to FinderSync extension
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.otterkeep.finderIntegrationChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// Updates an existing profile by ID or appends it if not present.
    /// - Parameter profile: The profile to update or add.
    public func updateProfile(_ profile: BackupProfile) throws {
        lock.lock()
        defer { lock.unlock() }

        var current = loadProfilesUnlocked()
        if let idx = current.firstIndex(where: { $0.id == profile.id }) {
            current[idx] = profile
        } else {
            current.append(profile)
        }
        try saveProfilesUnlocked(current)
    }

    /// Deletes a profile by ID, ensuring at least one profile remains in the list.
    /// - Parameter id: Unique profile UUID.
    public func deleteProfile(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        var current = loadProfilesUnlocked()
        guard current.count > 1 else { return }
        if let removed = current.first(where: { $0.id == id }) {
            KeychainManager.deletePassphrase(for: id)
            KeychainManager.deleteSecret(for: id.uuidString)
            KeychainManager.deleteSecret(for: "s3_\(id.uuidString)")
            KeychainManager.deleteSecret(for: "smb_\(id.uuidString)")
            KeychainManager.deleteSecret(for: "webdav_\(id.uuidString)")
            KeychainManager.deleteSecret(for: "sftp_\(id.uuidString)")
            KeychainManager.deleteSecret(for: "webhook_\(id.uuidString)")
            for dest in removed.copyJobConfig.destinations {
                KeychainManager.deleteSecret(for: dest.id.uuidString)
                KeychainManager.deleteSecret(for: "s3_\(dest.id.uuidString)")
                KeychainManager.deleteSecret(for: "smb_\(dest.id.uuidString)")
                KeychainManager.deleteSecret(for: "webdav_\(dest.id.uuidString)")
                KeychainManager.deleteSecret(for: "sftp_\(dest.id.uuidString)")
            }
        }
        try? centralDatabase.deleteProfileRecord(id: id.uuidString)
        current.removeAll(where: { $0.id == id })
        try saveProfilesUnlocked(current)
    }

    private func loadProfilesUnlocked() -> [BackupProfile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Primary Store: Central SQLite Database
        if let dbRecords = try? centralDatabase.loadProfileRecords(), !dbRecords.isEmpty {
            var loaded: [BackupProfile] = []
            for rec in dbRecords {
                if let data = rec.jsonData.data(using: .utf8),
                   let prof = try? decoder.decode(BackupProfile.self, from: data) {
                    loaded.append(prof)
                }
            }
            if !loaded.isEmpty {
                return loaded
            }
        }

        // 2. Fallback / Migration: Legacy profiles.json files
        var candidateFiles: [URL] = [profilesFileURL]
        if let pw = getpwuid(getuid()) {
            let realHome = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
            let realPath = realHome.appendingPathComponent(".otterkeep/profiles.json")
            if !candidateFiles.contains(realPath) {
                candidateFiles.insert(realPath, at: 0)
            }
            let realContainerPath = realHome
                .appendingPathComponent("Library/Containers/com.otterkeep.OtterKeepApp.FinderSync/Data/.otterkeep/profiles.json")
            if !candidateFiles.contains(realContainerPath) {
                candidateFiles.append(realContainerPath)
            }
        }
        let currentHomeContainer = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".otterkeep/profiles.json")
        if !candidateFiles.contains(currentHomeContainer) {
            candidateFiles.append(currentHomeContainer)
        }

        for file in candidateFiles {
            if fileManager.fileExists(atPath: file.path),
               let data = try? Data(contentsOf: file) {
                if let list = try? decoder.decode([BackupProfile].self, from: data), !list.isEmpty {
                    // Automatically migrate legacy profiles into Central Database
                    try? saveProfilesUnlocked(list)
                    return list
                }
            }
        }

        let initialProfile = createDefaultInitialProfile()
        try? saveProfilesUnlocked([initialProfile])
        return [initialProfile]
    }

    /// Creates a default initial profile pointing to standard user Documents and a local backup destination.
    /// - Returns: A standard `BackupProfile`.
    public func createDefaultInitialProfile() -> BackupProfile {
        let home = realUserHome
        return BackupProfile(
            name: BackupProfile.defaultProfileName,
            sourceURL: home.appendingPathComponent("Documents"),
            destinationURL: home.appendingPathComponent("OtterKeep_Backups"),
            excludePatterns: ["*.tmp", ".DS_Store", "node_modules", "DerivedData"]
        )
    }

    // MARK: - Configuration Export & Import

    /// Exports all configured profiles and settings to a JSON archive file at the specified URL.
    /// - Parameters:
    ///   - destinationURL: Destination file URL.
    ///   - profiles: Optional profile list override (defaults to loaded profiles).
    ///   - settings: Optional settings override (defaults to current settings).
    ///   - photosConfig: Optional photos configuration override.
    public func exportConfiguration(
        to destinationURL: URL,
        profiles: [BackupProfile]? = nil,
        settings: AppSettings? = nil,
        photosConfig: PhotosBackupConfiguration? = nil
    ) throws {
        let effectiveProfiles = profiles ?? loadProfiles()
        let effectiveSettings = settings ?? LocalizationManager.shared.settings
        let effectivePhotos = photosConfig ?? PhotosProfileStore.shared.loadConfiguration()
        try ConfigurationBackupManager.shared.exportConfiguration(
            to: destinationURL,
            profiles: effectiveProfiles,
            settings: effectiveSettings,
            photosConfig: effectivePhotos
        )
    }

    /// Imports a validated configuration archive from a JSON file, atomically updating profiles and settings with rollback protection.
    /// - Parameter sourceURL: Source JSON file URL.
    /// - Returns: The imported and validated `ConfigurationExportArchive`.
    @discardableResult
    public func importConfiguration(
        from sourceURL: URL
    ) throws -> ConfigurationExportArchive {
        let archive = try ConfigurationBackupManager.shared.parseArchive(from: sourceURL)

        lock.lock()
        defer { lock.unlock() }

        let backupProfiles = loadProfilesUnlocked()
        let backupSettings = LocalizationManager.shared.settings
        let backupPhotos = PhotosProfileStore.shared.loadConfiguration()

        do {
            try saveProfilesUnlocked(archive.profiles)
            LocalizationManager.shared.settings = archive.settings
            if let photos = archive.photosConfig {
                try PhotosProfileStore.shared.saveConfiguration(photos)
            }
            return archive
        } catch {
            // Rollback on failure
            try? saveProfilesUnlocked(backupProfiles)
            LocalizationManager.shared.settings = backupSettings
            try? PhotosProfileStore.shared.saveConfiguration(backupPhotos)
            throw error
        }
    }
}
