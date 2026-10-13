import Foundation
import SQLite3
import os

extension DatabaseEngine {
    // MARK: - Snapshot Operations

    /// Inserts or replaces a snapshot record in the database.
    /// - Parameter record: The snapshot record to persist.
    public func insertSnapshot(_ record: SnapshotRecord) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        INSERT OR REPLACE INTO snapshots (id, timestamp, status, total_files, total_bytes, snapshot_path, backup_type, locked_until)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, record.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, record.status, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, record.totalFiles)
        sqlite3_bind_int64(stmt, 5, record.totalBytes)
        sqlite3_bind_text(stmt, 6, record.snapshotPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, record.backupType, -1, SQLITE_TRANSIENT)
        if let lockedUntil = record.lockedUntil {
            sqlite3_bind_double(stmt, 8, lockedUntil.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 8)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Lists all snapshots ordered by creation timestamp in descending order.
    /// - Returns: Array of `SnapshotRecord` objects.
    public func listSnapshots() throws -> [SnapshotRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = "SELECT id, timestamp, status, total_files, total_bytes, snapshot_path, backup_type, locked_until FROM snapshots ORDER BY timestamp DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [SnapshotRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnText(stmt, 0)
            let ts = sqlite3_column_double(stmt, 1)
            let status = columnText(stmt, 2)
            let totalFiles = sqlite3_column_int64(stmt, 3)
            let totalBytes = sqlite3_column_int64(stmt, 4)
            let path = columnText(stmt, 5)
            var bType = columnText(stmt, 6)
            if bType.isEmpty { bType = "incremental" }

            let lockedUntil: Date?
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
                lockedUntil = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            } else {
                lockedUntil = nil
            }

            results.append(SnapshotRecord(
                id: id,
                timestamp: Date(timeIntervalSince1970: ts),
                status: status,
                totalFiles: totalFiles,
                totalBytes: totalBytes,
                snapshotPath: path,
                backupType: bType,
                lockedUntil: lockedUntil
            ))
        }
        return results
    }

    /// Updates the immutability lock expiration date for a snapshot.
    /// - Parameters:
    ///   - id: Snapshot identifier.
    ///   - lockedUntil: Expiration date or nil to unlock.
    public func updateSnapshotLockedUntil(id: String, lockedUntil: Date?) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = "UPDATE snapshots SET locked_until = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        if let lock = lockedUntil {
            sqlite3_bind_double(stmt, 1, lock.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Deletes a snapshot record by ID, automatically cascading deletion to associated file records.
    /// - Parameter id: Snapshot ID.
    public func deleteSnapshot(id: String) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = "DELETE FROM snapshots WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }


}
