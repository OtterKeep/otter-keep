import Foundation
import SQLite3
import os
import OtterKeepDomain

/// Profile row stored in the central SQLite database.
public struct CentralProfileRecord: Sendable, Equatable {
    public let id: String
    public let name: String
    public let jsonData: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, name: String, jsonData: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.jsonData = jsonData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Thread-safe central SQLite database manager residing in the user profile's hidden directory (`~/.otterkeep/central.sqlite`).
///
/// Stores:
/// 1. Backup profile configurations (`profiles` table), making local configuration central, durable, and queryable.
/// 2. Offline snapshot and file catalog metadata (`cached_snapshots`, `cached_file_records`), allowing the UI
///    and services to inspect backup history and browse file timelines even when the target destination drive is unmounted/detached.
public final class CentralDatabase: @unchecked Sendable {
    /// Shared singleton instance pointing to `~/.otterkeep/central.sqlite`.
    public static let shared = CentralDatabase()

    private let logger = Logger(subsystem: "com.otterkeep", category: "CentralDatabase")
    private let lock = NSLock()
    private var handle: SQLiteHandle?
    private var db: OpaquePointer? { handle?.pointer }

    /// Filesystem path to the central database file.
    public let databasePath: String

    /// Default base storage directory (`~/.otterkeep/`).
    public static var defaultStorageDirectory: URL {
        let home: URL
        if let pw = getpwuid(getuid()) {
            home = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        return home.appendingPathComponent(".otterkeep", isDirectory: true)
    }

    /// Default database URL (`~/.otterkeep/central.sqlite`).
    public static var defaultDatabaseURL: URL {
        defaultStorageDirectory.appendingPathComponent("central.sqlite")
    }

    /// Initializes a `CentralDatabase` instance.
    /// - Parameter databasePath: Optional custom path (defaults to `~/.otterkeep/central.sqlite`).
    public init(databasePath: String? = nil) {
        self.databasePath = databasePath ?? Self.defaultDatabaseURL.path(percentEncoded: false)
    }

    deinit {
        close()
    }

    /// Safely closes the database connection and checkpoints WAL.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard let handle = self.handle, let db = handle.pointer else { return }
        _ = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        sqlite3_close_v2(db)
        handle.pointer = nil
        self.handle = nil
        logger.debug("CentralDatabase connection closed.")
    }

    /// Opens the central database connection and ensures tables and indexes exist.
    private func ensureConnectedUnlocked() throws {
        if db != nil { return }

        let parentDir = (databasePath as NSString).deletingLastPathComponent
        if !parentDir.isEmpty && !FileManager.default.fileExists(atPath: parentDir) {
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            // Ensure 0700 permissions on directory
            chmod(parentDir, 0o700)
        }

        var newPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databasePath, &newPointer, flags, nil) != SQLITE_OK {
            let msg = newPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Failed to open SQLite"
            if let p = newPointer { sqlite3_close_v2(p) }
            throw DatabaseError.openFailed(msg)
        }
        self.handle = SQLiteHandle(pointer: newPointer)

        // Strict 0600 POSIX permissions on database file
        chmod(databasePath, 0o600)

        sqlite3_busy_timeout(newPointer, 10000)
        try executeUnlocked(query: "PRAGMA busy_timeout = 10000;")
        do {
            try executeUnlocked(query: "PRAGMA journal_mode = WAL;")
        } catch {
            try? executeUnlocked(query: "PRAGMA journal_mode = TRUNCATE;")
        }
        try executeUnlocked(query: "PRAGMA synchronous = NORMAL;")
        try executeUnlocked(query: "PRAGMA foreign_keys = ON;")

        try createSchemaUnlocked()
    }

    private func executeUnlocked(query: String) throws {
        guard let db = db else { throw DatabaseError.openFailed("CentralDatabase is not open") }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, query, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg != nil ? String(cString: errMsg!) : "Unknown execution error"
            sqlite3_free(errMsg)
            throw DatabaseError.executionFailed(query, msg)
        }
    }

    private func createSchemaUnlocked() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS profiles (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            json_data TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_profiles_updated ON profiles(updated_at DESC);

        CREATE TABLE IF NOT EXISTS cached_snapshots (
            id TEXT NOT NULL,
            profile_id TEXT NOT NULL,
            timestamp REAL NOT NULL,
            status TEXT NOT NULL,
            total_files INTEGER NOT NULL,
            total_bytes INTEGER NOT NULL,
            snapshot_path TEXT NOT NULL,
            backup_type TEXT NOT NULL DEFAULT 'incremental',
            locked_until REAL,
            PRIMARY KEY (profile_id, id)
        );

        CREATE INDEX IF NOT EXISTS idx_cached_snaps_prof ON cached_snapshots(profile_id, timestamp DESC);

        CREATE TABLE IF NOT EXISTS cached_file_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_id TEXT NOT NULL,
            snapshot_id TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            mtime REAL NOT NULL,
            inode INTEGER NOT NULL,
            checksum TEXT,
            is_directory INTEGER NOT NULL,
            is_symlink INTEGER NOT NULL,
            sample_hash TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_cached_files_prof_snap ON cached_file_records(profile_id, snapshot_id);
        CREATE INDEX IF NOT EXISTS idx_cached_files_prof_path ON cached_file_records(profile_id, relative_path);
        """
        try executeUnlocked(query: sql)
    }

    // MARK: - Profile Storage

    /// Loads all profile records stored in the central database, sorted by last update date ascending.
    public func loadProfileRecords() throws -> [CentralProfileRecord] {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return [] }
        let query = "SELECT id, name, json_data, created_at, updated_at FROM profiles ORDER BY updated_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [CentralProfileRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnText(stmt, 0)
            let name = columnText(stmt, 1)
            let jsonData = columnText(stmt, 2)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            results.append(CentralProfileRecord(id: id, name: name, jsonData: jsonData, createdAt: createdAt, updatedAt: updatedAt))
        }
        return results
    }

    /// Persists or updates an array of profile records in the central database inside an atomic transaction.
    public func saveProfileRecords(_ records: [CentralProfileRecord]) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return }
        try executeUnlocked(query: "BEGIN TRANSACTION;")
        do {
            let query = """
            INSERT INTO profiles (id, name, json_data, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                json_data = excluded.json_data,
                updated_at = excluded.updated_at;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            for record in records {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_text(stmt, 1, record.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, record.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, record.jsonData, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 4, record.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 5, record.updatedAt.timeIntervalSince1970)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DatabaseError.stepFailed("saveProfileRecords", String(cString: sqlite3_errmsg(db)))
                }
            }
            try executeUnlocked(query: "COMMIT;")
        } catch {
            try? executeUnlocked(query: "ROLLBACK;")
            throw error
        }
    }

    /// Replaces the entire profile catalog with a new list of records atomically.
    public func replaceAllProfileRecords(_ records: [CentralProfileRecord]) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return }
        try executeUnlocked(query: "BEGIN TRANSACTION;")
        do {
            try executeUnlocked(query: "DELETE FROM profiles;")
            let query = "INSERT INTO profiles (id, name, json_data, created_at, updated_at) VALUES (?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            for record in records {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_text(stmt, 1, record.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, record.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, record.jsonData, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 4, record.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 5, record.updatedAt.timeIntervalSince1970)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DatabaseError.stepFailed("replaceAllProfileRecords", String(cString: sqlite3_errmsg(db)))
                }
            }
            try executeUnlocked(query: "COMMIT;")
        } catch {
            try? executeUnlocked(query: "ROLLBACK;")
            throw error
        }
    }

    /// Deletes a profile record and all its associated cached snapshots and file catalogs.
    public func deleteProfileRecord(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return }
        try executeUnlocked(query: "BEGIN TRANSACTION;")
        do {
            let deleteProfile = "DELETE FROM profiles WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteProfile, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            let deleteSnaps = "DELETE FROM cached_snapshots WHERE profile_id = ?;"
            if sqlite3_prepare_v2(db, deleteSnaps, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            let deleteFiles = "DELETE FROM cached_file_records WHERE profile_id = ?;"
            if sqlite3_prepare_v2(db, deleteFiles, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            try executeUnlocked(query: "COMMIT;")
        } catch {
            try? executeUnlocked(query: "ROLLBACK;")
            throw error
        }
    }

    // MARK: - Snapshot & Catalog Caching (Offline Inspection)

    /// Synchronizes a list of snapshot records for a profile into the local cache.
    public func cacheSnapshots(_ snapshots: [SnapshotRecord], forProfileId profileId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return }
        try executeUnlocked(query: "BEGIN TRANSACTION;")
        do {
            let query = """
            INSERT INTO cached_snapshots (id, profile_id, timestamp, status, total_files, total_bytes, snapshot_path, backup_type, locked_until)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(profile_id, id) DO UPDATE SET
                timestamp = excluded.timestamp,
                status = excluded.status,
                total_files = excluded.total_files,
                total_bytes = excluded.total_bytes,
                snapshot_path = excluded.snapshot_path,
                backup_type = excluded.backup_type,
                locked_until = excluded.locked_until;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            for snap in snapshots {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_text(stmt, 1, snap.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, profileId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 3, snap.timestamp.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 4, snap.status, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 5, snap.totalFiles)
                sqlite3_bind_int64(stmt, 6, snap.totalBytes)
                sqlite3_bind_text(stmt, 7, snap.snapshotPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 8, snap.backupType, -1, SQLITE_TRANSIENT)
                if let lock = snap.lockedUntil {
                    sqlite3_bind_double(stmt, 9, lock.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(stmt, 9)
                }

                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DatabaseError.stepFailed("cacheSnapshots", String(cString: sqlite3_errmsg(db)))
                }
            }
            try executeUnlocked(query: "COMMIT;")
        } catch {
            try? executeUnlocked(query: "ROLLBACK;")
            throw error
        }
    }

    /// Caches a single snapshot along with its file catalog records for offline inspection.
    public func cacheSnapshotWithFiles(_ snapshot: SnapshotRecord, files: [FileCatalogRecord], forProfileId profileId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return }
        try executeUnlocked(query: "BEGIN TRANSACTION;")
        do {
            // 1. Insert snapshot
            let snapQuery = """
            INSERT INTO cached_snapshots (id, profile_id, timestamp, status, total_files, total_bytes, snapshot_path, backup_type, locked_until)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(profile_id, id) DO UPDATE SET
                timestamp = excluded.timestamp,
                status = excluded.status,
                total_files = excluded.total_files,
                total_bytes = excluded.total_bytes,
                snapshot_path = excluded.snapshot_path,
                backup_type = excluded.backup_type,
                locked_until = excluded.locked_until;
            """
            var snapStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, snapQuery, -1, &snapStmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(snapQuery, String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_bind_text(snapStmt, 1, snapshot.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(snapStmt, 2, profileId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(snapStmt, 3, snapshot.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(snapStmt, 4, snapshot.status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(snapStmt, 5, snapshot.totalFiles)
            sqlite3_bind_int64(snapStmt, 6, snapshot.totalBytes)
            sqlite3_bind_text(snapStmt, 7, snapshot.snapshotPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(snapStmt, 8, snapshot.backupType, -1, SQLITE_TRANSIENT)
            if let lock = snapshot.lockedUntil {
                sqlite3_bind_double(snapStmt, 9, lock.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(snapStmt, 9)
            }
            if sqlite3_step(snapStmt) != SQLITE_DONE {
                sqlite3_finalize(snapStmt)
                throw DatabaseError.stepFailed("cacheSnapshotWithFiles.snap", String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_finalize(snapStmt)

            // 2. Remove existing cached files for this snapshot to avoid duplicate rows
            let deleteFilesQuery = "DELETE FROM cached_file_records WHERE profile_id = ? AND snapshot_id = ?;"
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteFilesQuery, -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delStmt, 1, profileId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(delStmt, 2, snapshot.id, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(delStmt)
                sqlite3_finalize(delStmt)
            }

            // 3. Insert file records
            let fileQuery = """
            INSERT INTO cached_file_records (
                profile_id, snapshot_id, relative_path, file_size, mtime, inode,
                checksum, is_directory, is_symlink, sample_hash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var fileStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, fileQuery, -1, &fileStmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(fileQuery, String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(fileStmt) }

            for f in files {
                sqlite3_reset(fileStmt)
                sqlite3_clear_bindings(fileStmt)

                sqlite3_bind_text(fileStmt, 1, profileId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(fileStmt, 2, snapshot.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(fileStmt, 3, f.relativePath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(fileStmt, 4, f.fileSize)
                sqlite3_bind_double(fileStmt, 5, f.modificationTime.timeIntervalSince1970)
                sqlite3_bind_int64(fileStmt, 6, Int64(f.inode))

                if let c = f.checksum {
                    sqlite3_bind_text(fileStmt, 7, c, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(fileStmt, 7)
                }

                sqlite3_bind_int(fileStmt, 8, f.isDirectory ? 1 : 0)
                sqlite3_bind_int(fileStmt, 9, f.isSymlink ? 1 : 0)

                if let sh = f.sampleHash {
                    sqlite3_bind_text(fileStmt, 10, sh, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(fileStmt, 10)
                }

                if sqlite3_step(fileStmt) != SQLITE_DONE {
                    throw DatabaseError.stepFailed("cacheSnapshotWithFiles.files", String(cString: sqlite3_errmsg(db)))
                }
            }

            try executeUnlocked(query: "COMMIT;")
        } catch {
            try? executeUnlocked(query: "ROLLBACK;")
            throw error
        }
    }

    /// Lists all cached snapshots for a given profile, ordered by timestamp descending.
    public func listCachedSnapshots(forProfileId profileId: String) throws -> [SnapshotRecord] {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return [] }
        let query = """
        SELECT id, timestamp, status, total_files, total_bytes, snapshot_path, backup_type, locked_until
        FROM cached_snapshots
        WHERE profile_id = ?
        ORDER BY timestamp DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, profileId, -1, SQLITE_TRANSIENT)

        var records: [SnapshotRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnText(stmt, 0)
            let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let st = columnText(stmt, 2)
            let tf = sqlite3_column_int64(stmt, 3)
            let tb = sqlite3_column_int64(stmt, 4)
            let sp = columnText(stmt, 5)
            let bt = columnText(stmt, 6)
            var lockDate: Date? = nil
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
                lockDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            }
            records.append(SnapshotRecord(
                id: id,
                timestamp: ts,
                status: st,
                totalFiles: tf,
                totalBytes: tb,
                snapshotPath: sp,
                backupType: bt.isEmpty ? "incremental" : bt,
                lockedUntil: lockDate
            ))
        }
        return records
    }

    /// Retrieves a specific cached snapshot by ID.
    public func getCachedSnapshot(id: String, forProfileId profileId: String) throws -> SnapshotRecord? {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return nil }
        let query = """
        SELECT id, timestamp, status, total_files, total_bytes, snapshot_path, backup_type, locked_until
        FROM cached_snapshots
        WHERE profile_id = ? AND id = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, profileId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let snapId = columnText(stmt, 0)
            let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let st = columnText(stmt, 2)
            let tf = sqlite3_column_int64(stmt, 3)
            let tb = sqlite3_column_int64(stmt, 4)
            let sp = columnText(stmt, 5)
            let bt = columnText(stmt, 6)
            var lockDate: Date? = nil
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
                lockDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            }
            return SnapshotRecord(
                id: snapId,
                timestamp: ts,
                status: st,
                totalFiles: tf,
                totalBytes: tb,
                snapshotPath: sp,
                backupType: bt.isEmpty ? "incremental" : bt,
                lockedUntil: lockDate
            )
        }
        return nil
    }

    /// Deletes a specific snapshot and its file records from the offline cache.
    public func deleteCachedSnapshot(id: String, forProfileId profileId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return }
        try executeUnlocked(query: "BEGIN TRANSACTION;")
        do {
            let delSnap = "DELETE FROM cached_snapshots WHERE profile_id = ? AND id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, delSnap, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, profileId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            let delFiles = "DELETE FROM cached_file_records WHERE profile_id = ? AND snapshot_id = ?;"
            if sqlite3_prepare_v2(db, delFiles, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, profileId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            try executeUnlocked(query: "COMMIT;")
        } catch {
            try? executeUnlocked(query: "ROLLBACK;")
            throw error
        }
    }

    /// Lists all cached file catalog records for a given snapshot.
    public func listCachedFiles(forSnapshotId snapshotId: String, profileId: String) throws -> [FileCatalogRecord] {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return [] }
        let query = """
        SELECT id, snapshot_id, relative_path, file_size, mtime, inode, checksum, is_directory, is_symlink, sample_hash
        FROM cached_file_records
        WHERE profile_id = ? AND snapshot_id = ?
        ORDER BY relative_path ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, profileId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, snapshotId, -1, SQLITE_TRANSIENT)

        var records: [FileCatalogRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(stmt, 0)
            let snapId = columnText(stmt, 1)
            let path = columnText(stmt, 2)
            let size = sqlite3_column_int64(stmt, 3)
            let mtime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            let inode = UInt64(sqlite3_column_int64(stmt, 5))
            let checksum = columnOptionalText(stmt, 6)
            let isDir = sqlite3_column_int(stmt, 7) == 1
            let isSym = sqlite3_column_int(stmt, 8) == 1
            let sampleHash = columnOptionalText(stmt, 9)

            records.append(FileCatalogRecord(
                id: rowId,
                snapshotId: snapId,
                relativePath: path,
                fileSize: size,
                modificationTime: mtime,
                inode: inode,
                checksum: checksum,
                sampleHash: sampleHash,
                isDirectory: isDir,
                isSymlink: isSym
            ))
        }
        return records
    }

    /// Lists all point-in-time cached versions of a file across snapshots for a profile.
    public func listCachedVersions(ofRelativePath relativePath: String, profileId: String) throws -> [(snapshot: SnapshotRecord, file: FileCatalogRecord)] {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return [] }
        let query = """
        SELECT
            s.id, s.timestamp, s.status, s.total_files, s.total_bytes, s.snapshot_path, s.backup_type, s.locked_until,
            f.id, f.relative_path, f.file_size, f.mtime, f.inode, f.checksum, f.is_directory, f.is_symlink, f.sample_hash
        FROM cached_file_records f
        JOIN cached_snapshots s ON f.profile_id = s.profile_id AND f.snapshot_id = s.id
        WHERE f.profile_id = ? AND f.relative_path = ?
        ORDER BY s.timestamp DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, profileId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, relativePath, -1, SQLITE_TRANSIENT)

        var versions: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let snapId = columnText(stmt, 0)
            let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let st = columnText(stmt, 2)
            let tf = sqlite3_column_int64(stmt, 3)
            let tb = sqlite3_column_int64(stmt, 4)
            let sp = columnText(stmt, 5)
            let bt = columnText(stmt, 6)
            var lockDate: Date? = nil
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
                lockDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            }
            let snap = SnapshotRecord(
                id: snapId,
                timestamp: ts,
                status: st,
                totalFiles: tf,
                totalBytes: tb,
                snapshotPath: sp,
                backupType: bt.isEmpty ? "incremental" : bt,
                lockedUntil: lockDate
            )

            let fileId = sqlite3_column_int64(stmt, 8)
            let path = columnText(stmt, 9)
            let size = sqlite3_column_int64(stmt, 10)
            let mtime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 11))
            let inode = UInt64(sqlite3_column_int64(stmt, 12))
            let checksum = columnOptionalText(stmt, 13)
            let isDir = sqlite3_column_int(stmt, 14) == 1
            let isSym = sqlite3_column_int(stmt, 15) == 1
            let sampleHash = columnOptionalText(stmt, 16)

            let file = FileCatalogRecord(
                id: fileId,
                snapshotId: snapId,
                relativePath: path,
                fileSize: size,
                modificationTime: mtime,
                inode: inode,
                checksum: checksum,
                sampleHash: sampleHash,
                isDirectory: isDir,
                isSymlink: isSym
            )
            versions.append((snapshot: snap, file: file))
        }
        return versions
    }

    /// Searches distinct relative paths matching query for a profile.
    public func searchCachedRelativePaths(matching query: String, profileId: String) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let db = db else { return [] }
        let sql: String
        let sanitized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty {
            sql = "SELECT DISTINCT relative_path FROM cached_file_records WHERE profile_id = ? ORDER BY relative_path ASC LIMIT 2000;"
        } else {
            sql = "SELECT DISTINCT relative_path FROM cached_file_records WHERE profile_id = ? AND relative_path LIKE ? ORDER BY relative_path ASC LIMIT 2000;"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sql, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, profileId, -1, SQLITE_TRANSIENT)
        if !sanitized.isEmpty {
            let pattern = "%\(sanitized)%"
            sqlite3_bind_text(stmt, 2, pattern, -1, SQLITE_TRANSIENT)
        }

        var paths: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            paths.append(columnText(stmt, 0))
        }
        return paths
    }

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    private func columnOptionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    // MARK: - Self-Healing & Maintenance

    /// Checks the structural integrity of the central SQLite database.
    public func performIntegrityCheck() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()
        return performIntegrityCheckUnlocked()
    }

    private func performIntegrityCheckUnlocked() -> Bool {
        guard let db = db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check;", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            if let result = sqlite3_column_text(stmt, 0) {
                let status = String(cString: result)
                return status.lowercased() == "ok"
            }
        }
        return false
    }

    /// Performs self-healing optimization, rebuilding indexes if corrupted and compacting database with VACUUM.
    public func performSelfHealingMaintenance() throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnectedUnlocked()

        guard let _ = db else { return }
        let healthy = performIntegrityCheckUnlocked()
        if !healthy {
            logger.error("Central database corruption suspected! Executing REINDEX repair...")
            try? executeUnlocked(query: "REINDEX;")
        }

        try? executeUnlocked(query: "PRAGMA optimize;")
        try? executeUnlocked(query: "VACUUM;")
        logger.info("Central database self-healing maintenance and VACUUM completed.")
    }
}
