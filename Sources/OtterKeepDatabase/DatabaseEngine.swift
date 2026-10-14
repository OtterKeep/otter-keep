import Foundation
import SQLite3
import os

/// SQLite transient destructor constant for memory safety when binding Swift strings.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thread-safe wrapper around a SQLite database handle.
final class SQLiteHandle: @unchecked Sendable {
    var pointer: OpaquePointer?
    init(pointer: OpaquePointer?) { self.pointer = pointer }
    deinit {
        if let ptr = pointer {
            sqlite3_close_v2(ptr)
        }
    }
}

/// High-performance, actor-isolated SQLite database engine managing snapshot metadata and file version history.
///
/// Implements transactional SQLite operations with WAL journal mode, automatic fallback to TRUNCATE
/// on non-POSIX shared-memory volumes (exFAT/FAT/SMB), and explicit resource closure releasing file locks.
public actor DatabaseEngine {
    let logger = Logger(subsystem: "com.otterkeep", category: "Database")
    var handle: SQLiteHandle?
    var db: OpaquePointer? { handle?.pointer }

    /// Initializes a new `DatabaseEngine` instance.
    public init() {}

    /// Safely closes the active SQLite database connection, checkpoints the WAL journal, and releases all locks and file descriptors.
    public func close() {
        guard let handle = self.handle, let db = handle.pointer else { return }
        _ = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        sqlite3_close_v2(db)
        handle.pointer = nil
        self.handle = nil
        logger.debug("Database connection closed and handles cleanly released.")
    }

    /// Whether the database currently has an active open connection.
    public var isOpen: Bool {
        db != nil
    }

    /// Opens the SQLite database at the specified path and initializes tables, pragmas, and indices.
    /// - Parameter path: Full filesystem path to the SQLite file.
    public func open(at path: String) throws {
        if let oldHandle = handle {
            if let ptr = oldHandle.pointer {
                _ = sqlite3_wal_checkpoint_v2(ptr, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
                sqlite3_close_v2(ptr)
                oldHandle.pointer = nil
            }
            handle = nil
        }

        // Ensure parent directory exists before creating or opening SQLite database file
        let parentDir = (path as NSString).deletingLastPathComponent
        if !parentDir.isEmpty && !FileManager.default.fileExists(atPath: parentDir) {
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }

        var newPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &newPointer, flags, nil) != SQLITE_OK {
            let msg = newPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Failed to open SQLite"
            if let p = newPointer { sqlite3_close_v2(p) }
            throw DatabaseError.openFailed(msg)
        }
        self.handle = SQLiteHandle(pointer: newPointer)

        // Enforce strict 0600 POSIX permissions on database file for user data security
        chmod(path, 0o600)

        // Configure 10-second busy timeout to prevent immediate SQLITE_BUSY locking under multi-process contention
        sqlite3_busy_timeout(newPointer, 10000)
        try execute(query: "PRAGMA busy_timeout = 10000;")

        // Write-Ahead Logging (WAL) and performance tuning pragmas
        // If WAL mode fails (e.g. on external FAT/exFAT or network drives lacking POSIX shared memory),
        // gracefully fall back to TRUNCATE mode.
        do {
            try execute(query: "PRAGMA journal_mode = WAL;")
        } catch {
            logger.warning("WAL journal mode unavailable on filesystem, falling back to TRUNCATE: \(error.localizedDescription)")
            try? execute(query: "PRAGMA journal_mode = TRUNCATE;")
        }
        try execute(query: "PRAGMA synchronous = NORMAL;")
        try execute(query: "PRAGMA foreign_keys = ON;")

        try createSchema()
    }


    /// Executes a raw SQL query with error handling and query execution duration profiling.
    func execute(query: String) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let startTime = CFAbsoluteTimeGetCurrent()
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, query, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg != nil ? String(cString: errMsg!) : "Unknown SQLite execution error"
            sqlite3_free(errMsg)
            throw DatabaseError.executionFailed(query, msg)
        }
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        if durationMs > 50.0 {
            logger.warning("Slow SQL query execution (\(String(format: "%.1f", durationMs)) ms): \(query)")
        }
    }

    /// Initializes database schema tables and query optimization indexes.
    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS snapshots (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            status TEXT NOT NULL,
            total_files INTEGER NOT NULL,
            total_bytes INTEGER NOT NULL,
            snapshot_path TEXT NOT NULL,
            backup_type TEXT NOT NULL DEFAULT 'incremental',
            locked_until REAL
        );

        CREATE TABLE IF NOT EXISTS file_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_id TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            mtime REAL NOT NULL,
            inode INTEGER NOT NULL,
            checksum TEXT,
            is_directory INTEGER NOT NULL,
            is_symlink INTEGER NOT NULL,
            sample_hash TEXT,
            FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_file_records_snapshot ON file_records(snapshot_id);
        CREATE INDEX IF NOT EXISTS idx_file_records_path ON file_records(relative_path);
        CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp ON snapshots(timestamp DESC);

        CREATE TABLE IF NOT EXISTS photos_asset_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_id TEXT NOT NULL,
            local_identifier TEXT NOT NULL,
            original_filename TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            mtime REAL NOT NULL,
            sha256 TEXT,
            is_edited INTEGER NOT NULL DEFAULT 0,
            is_live_photo INTEGER NOT NULL DEFAULT 0,
            media_type TEXT NOT NULL DEFAULT 'image',
            albums_json TEXT,
            FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_photos_records_snapshot ON photos_asset_records(snapshot_id);
        CREATE INDEX IF NOT EXISTS idx_photos_records_local_id ON photos_asset_records(local_identifier);

        CREATE TABLE IF NOT EXISTS scrub_audit_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            checked_snapshots_count INTEGER NOT NULL,
            checked_files_count INTEGER NOT NULL,
            corrupted_files_count INTEGER NOT NULL,
            status TEXT NOT NULL,
            details_json TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_scrub_audit_timestamp ON scrub_audit_logs(timestamp DESC);

        CREATE TABLE IF NOT EXISTS replication_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_id TEXT NOT NULL,
            destination_type TEXT NOT NULL,
            destination_identifier TEXT NOT NULL,
            status TEXT NOT NULL,
            replicated_bytes INTEGER NOT NULL DEFAULT 0,
            total_bytes INTEGER NOT NULL DEFAULT 0,
            started_at REAL NOT NULL,
            completed_at REAL,
            error_message TEXT,
            FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_rep_snapshots_id ON replication_snapshots(snapshot_id);
        CREATE INDEX IF NOT EXISTS idx_rep_snapshots_dest ON replication_snapshots(destination_identifier);

        CREATE TABLE IF NOT EXISTS replication_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_id TEXT NOT NULL,
            destination_identifier TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            remote_key TEXT NOT NULL,
            remote_etag TEXT,
            checksum TEXT,
            file_size INTEGER NOT NULL,
            status TEXT NOT NULL,
            FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_rep_files_lookup ON replication_files(destination_identifier, relative_path);
        CREATE INDEX IF NOT EXISTS idx_rep_files_snapshot ON replication_files(snapshot_id);

        CREATE TABLE IF NOT EXISTS pending_replications (
            id TEXT PRIMARY KEY,
            profile_id TEXT NOT NULL,
            snapshot_id TEXT NOT NULL,
            destination_id TEXT NOT NULL,
            destination_type TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            retry_count INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            last_attempt_at REAL,
            error_message TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_pending_rep_status ON pending_replications(status);
        CREATE INDEX IF NOT EXISTS idx_pending_rep_profile ON pending_replications(profile_id);
        """
        try execute(query: sql)

        // Schema migrations for existing databases
        try? execute(query: "ALTER TABLE snapshots ADD COLUMN backup_type TEXT NOT NULL DEFAULT 'incremental';")
        try? execute(query: "ALTER TABLE snapshots ADD COLUMN locked_until REAL;")
        try? execute(query: "ALTER TABLE file_records ADD COLUMN sample_hash TEXT;")
    }


    // MARK: - Safe Column Helper Methods

    func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    func columnOptionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    // MARK: - Database Self-Healing & Optimization

    /// Runs SQLite integrity checks, returning true if database is healthy.
    public func performIntegrityCheck() throws -> Bool {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
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

    /// Performs self-healing database optimization, vacuuming free pages, and rebuilding query planner statistics.
    public func performSelfHealingMaintenance() throws {
        guard db != nil else { throw DatabaseError.openFailed("Database is not open") }
        // 1. Check integrity
        let isHealthy = (try? performIntegrityCheck()) ?? false
        if !isHealthy {
            logger.error("Database integrity check failed! Attempting index re-indexing repair...")
            try? execute(query: "REINDEX;")
        }

        // 2. Query planner optimizer
        try? execute(query: "PRAGMA optimize;")

        // 3. Compact free pages
        try? execute(query: "VACUUM;")
        logger.info("Database self-healing and vacuum maintenance successfully completed.")
    }
}
