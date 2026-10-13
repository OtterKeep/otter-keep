import Foundation
import os
import OtterKeepDomain
import OtterKeepApplication
import OtterKeepStorage
import OtterKeepDatabase

/// Central domain service managing snapshot catalog operations, version histories, and immutability locks.
///
/// Encapsulates SQLite database connection lifecycles and provides clean repository port access.
public final class SnapshotCatalogService: Sendable {
    /// Shared singleton instance.
    public static let shared = SnapshotCatalogService()

    private let logger = Logger(subsystem: "com.otterkeep", category: "SnapshotCatalogService")

    public init() {}

    /// Factory creating a `SnapshotRepositoryProtocol` port instance for the given backup profile.
    public func snapshotRepository(for profile: BackupProfile) -> SnapshotRepositoryProtocol {
        SQLiteSnapshotRepository(databasePath: profile.manifestDatabasePath)
    }

    /// Factory creating a `FileCatalogRepositoryProtocol` port instance for the given backup profile.
    public func fileCatalogRepository(for profile: BackupProfile) -> FileCatalogRepositoryProtocol {
        SQLiteFileCatalogRepository(databasePath: profile.manifestDatabasePath)
    }

    /// Executes an async block against an open `DatabaseEngine` connection, guaranteeing that
    /// `await db.close()` is always executed upon completion or error.
    private func withDatabase<T: Sendable>(
        for profile: BackupProfile,
        allowMissing: Bool = false,
        defaultValue: T? = nil,
        action: (DatabaseEngine) async throws -> T
    ) async throws -> T {
        if !FileManager.default.fileExists(atPath: profile.manifestDatabasePath) {
            if allowMissing, let def = defaultValue {
                return def
            }
        }
        let db = DatabaseEngine()
        try await db.open(at: profile.manifestDatabasePath)
        do {
            let result = try await action(db)
            await db.close()
            return result
        } catch {
            await db.close()
            throw error
        }
    }

    /// Lists all snapshots recorded in the profile's SQLite manifest catalog, falling back to the central database offline cache if the destination volume is detached.
    /// - Parameter profile: The target backup profile.
    /// - Returns: Array of snapshot records sorted by timestamp descending.
    public func listSnapshots(for profile: BackupProfile) async throws -> [SnapshotRecord] {
        if FileManager.default.fileExists(atPath: profile.manifestDatabasePath) {
            let snaps = try await ListSnapshotsUseCase(repository: snapshotRepository(for: profile)).execute()
            try? CentralDatabase.shared.cacheSnapshots(snaps, forProfileId: profile.id.uuidString)
            return snaps
        } else {
            return try CentralDatabase.shared.listCachedSnapshots(forProfileId: profile.id.uuidString)
        }
    }

    /// Retrieves a specific snapshot record by its unique ID.
    /// - Parameters:
    ///   - id: Unique snapshot identifier.
    ///   - profile: The target backup profile.
    /// - Returns: The matching `SnapshotRecord`, or `nil` if not found.
    public func getSnapshot(id: String, in profile: BackupProfile) async throws -> SnapshotRecord? {
        if FileManager.default.fileExists(atPath: profile.manifestDatabasePath) {
            return try await snapshotRepository(for: profile).getSnapshot(id: id)
        } else {
            return try CentralDatabase.shared.getCachedSnapshot(id: id, forProfileId: profile.id.uuidString)
        }
    }

    /// Lists all file catalog records associated with a specific snapshot.
    /// - Parameters:
    ///   - snapshotId: Unique snapshot identifier.
    ///   - profile: The target backup profile.
    /// - Returns: Array of indexed `FileCatalogRecord` entries.
    public func listFiles(forSnapshotId snapshotId: String, in profile: BackupProfile) async throws -> [FileCatalogRecord] {
        if FileManager.default.fileExists(atPath: profile.manifestDatabasePath) {
            return try await fileCatalogRepository(for: profile).listFiles(forSnapshotId: snapshotId)
        } else {
            return try CentralDatabase.shared.listCachedFiles(forSnapshotId: snapshotId, profileId: profile.id.uuidString)
        }
    }

    /// Queries the point-in-time version history for a specific relative file path across all snapshots.
    /// - Parameters:
    ///   - relativePath: Target relative file path.
    ///   - profile: The target backup profile.
    /// - Returns: Array of snapshot and file record pairs.
    public func listFileVersions(
        relativePath: String,
        in profile: BackupProfile
    ) async throws -> [(snapshot: SnapshotRecord, file: FileCatalogRecord)] {
        if FileManager.default.fileExists(atPath: profile.manifestDatabasePath) {
            return try await fileCatalogRepository(for: profile).listVersions(ofRelativePath: relativePath)
        } else {
            return try CentralDatabase.shared.listCachedVersions(ofRelativePath: relativePath, profileId: profile.id.uuidString)
        }
    }

    /// Updates the WORM immutability lock date on a snapshot record and sets or clears BSD file flags.
    /// - Parameters:
    ///   - id: Unique snapshot identifier.
    ///   - lockedUntil: New expiration date, or `nil` to unlock.
    ///   - profile: The target backup profile.
    ///   - storage: Filesystem provider used to set or clear BSD file immutability flags.
    public func updateSnapshotLock(
        id: String,
        lockedUntil: Date?,
        in profile: BackupProfile,
        storage: FileSystemProvider = DefaultFileSystemProvider()
    ) async throws {
        let repo = snapshotRepository(for: profile)
        try await repo.updateSnapshotLockedUntil(id: id, lockedUntil: lockedUntil)

        let snapshots = try await repo.listSnapshots()
        if let snap = snapshots.first(where: { $0.id == id }) {
            let snapURL = profile.destinationURL.appendingPathComponent(snap.snapshotPath)
            let isLockActive = (lockedUntil != nil && lockedUntil! > Date())
            try? storage.setImmutable(at: snapURL, immutable: isLockActive, recursive: true)
        }
    }

    /// Performs differential analysis between two snapshots in the profile's catalog.
    /// - Parameters:
    ///   - targetSnapshotId: Target snapshot identifier.
    ///   - baseSnapshotId: Optional base snapshot identifier to compare against.
    ///   - profile: Target backup profile.
    /// - Returns: A comprehensive `SnapshotDiffReport`.
    public func diffSnapshots(
        targetSnapshotId: String,
        baseSnapshotId: String?,
        in profile: BackupProfile
    ) async throws -> SnapshotDiffReport {
        try await withDatabase(for: profile) { db in
            try await SnapshotDiffEngine.shared.diff(
                database: db,
                targetSnapshotId: targetSnapshotId,
                baseSnapshotId: baseSnapshotId
            )
        }
    }

    /// Compares two file versions line-by-line using `TextDiffEngine`.
    /// - Parameters:
    ///   - leftURL: Left (base) file URL.
    ///   - rightURL: Right (target) file URL.
    ///   - relativePath: Display relative path.
    /// - Returns: A `FileComparisonResult`.
    public func diffFiles(
        leftURL: URL,
        rightURL: URL,
        relativePath: String
    ) throws -> FileComparisonResult {
        try TextDiffEngine().diffFiles(leftURL: leftURL, rightURL: rightURL, relativePath: relativePath)
    }
}
