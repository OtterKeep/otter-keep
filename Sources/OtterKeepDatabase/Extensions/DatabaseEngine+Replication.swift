import Foundation
import SQLite3
import os

extension DatabaseEngine {
    // MARK: - Pending Replication Operations

    /// Inserts a pending replication task into the queue.
    public func insertPendingReplication(_ record: PendingReplicationRecord) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        INSERT OR REPLACE INTO pending_replications (id, profile_id, snapshot_id, destination_id, destination_type, status, retry_count, created_at, last_attempt_at, error_message)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, record.profileId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, record.snapshotId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, record.destinationId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, record.destinationType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, record.status, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 7, Int32(record.retryCount))
        sqlite3_bind_double(stmt, 8, record.createdAt.timeIntervalSince1970)
        if let last = record.lastAttemptAt {
            sqlite3_bind_double(stmt, 9, last.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        if let err = record.errorMessage {
            sqlite3_bind_text(stmt, 10, err, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 10)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Lists pending replication tasks with optional status and profile filtering.
    public func listPendingReplications(status: String? = nil, profileId: UUID? = nil) throws -> [PendingReplicationRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        var conditions: [String] = []
        if let st = status {
            conditions.append("status = '\(st)'")
        }
        if let prof = profileId {
            conditions.append("profile_id = '\(prof.uuidString)'")
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let query = "SELECT id, profile_id, snapshot_id, destination_id, destination_type, status, retry_count, created_at, last_attempt_at, error_message FROM pending_replications \(whereClause) ORDER BY created_at ASC;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [PendingReplicationRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnText(stmt, 0)
            let profId = UUID(uuidString: columnText(stmt, 1)) ?? UUID()
            let snapId = columnText(stmt, 2)
            let destId = UUID(uuidString: columnText(stmt, 3)) ?? UUID()
            let destType = columnText(stmt, 4)
            let itemStatus = columnText(stmt, 5)
            let retries = Int(sqlite3_column_int(stmt, 6))
            let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            let lastAttempt: Date? = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)) : nil
            let errMsg = columnOptionalText(stmt, 9)

            results.append(PendingReplicationRecord(
                id: id,
                profileId: profId,
                snapshotId: snapId,
                destinationId: destId,
                destinationType: destType,
                status: itemStatus,
                retryCount: retries,
                createdAt: created,
                lastAttemptAt: lastAttempt,
                errorMessage: errMsg
            ))
        }
        return results
    }

    /// Updates status and error information for a pending replication task.
    public func updatePendingReplicationStatus(id: String, status: String, errorMessage: String? = nil, incrementRetry: Bool = false) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let now = Date().timeIntervalSince1970
        let retryUpdate = incrementRetry ? "retry_count = retry_count + 1," : ""
        let query = "UPDATE pending_replications SET status = ?, \(retryUpdate) last_attempt_at = ?, error_message = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, status, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, now)
        if let err = errorMessage {
            sqlite3_bind_text(stmt, 3, err, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_text(stmt, 4, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Removes a completed or cancelled pending replication task.
    public func deletePendingReplication(id: String) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = "DELETE FROM pending_replications WHERE id = ?;"
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


    // MARK: - 3-2-1 Replication Operations

    /// Records or updates a snapshot replication status record.
    public func recordReplicationSnapshot(_ record: ReplicationSnapshotRecord) throws -> Int64 {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        INSERT INTO replication_snapshots (snapshot_id, destination_type, destination_identifier, status, replicated_bytes, total_bytes, started_at, completed_at, error_message)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.snapshotId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, record.destinationType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, record.destinationIdentifier, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, record.status, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 5, record.replicatedBytes)
        sqlite3_bind_int64(stmt, 6, record.totalBytes)
        sqlite3_bind_double(stmt, 7, record.startedAt.timeIntervalSince1970)
        if let completedAt = record.completedAt {
            sqlite3_bind_double(stmt, 8, completedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        if let errMsg = record.errorMessage {
            sqlite3_bind_text(stmt, 9, errMsg, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 9)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        return sqlite3_last_insert_rowid(db)
    }

    /// Updates status and metrics for an existing snapshot replication run.
    public func updateReplicationSnapshot(
        snapshotId: String,
        destinationIdentifier: String,
        status: String,
        replicatedBytes: Int64,
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        UPDATE replication_snapshots
        SET status = ?, replicated_bytes = ?, completed_at = ?, error_message = ?
        WHERE snapshot_id = ? AND destination_identifier = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, status, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, replicatedBytes)
        if let completedAt = completedAt {
            sqlite3_bind_double(stmt, 3, completedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        if let errMsg = errorMessage {
            sqlite3_bind_text(stmt, 4, errMsg, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_text(stmt, 5, snapshotId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, destinationIdentifier, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Fetches all replication records for a specific snapshot.
    public func fetchReplicationSnapshots(for snapshotId: String) throws -> [ReplicationSnapshotRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT id, snapshot_id, destination_type, destination_identifier, status, replicated_bytes, total_bytes, started_at, completed_at, error_message
        FROM replication_snapshots
        WHERE snapshot_id = ?
        ORDER BY started_at DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, snapshotId, -1, SQLITE_TRANSIENT)

        var records: [ReplicationSnapshotRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let completedAtTime = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? sqlite3_column_double(stmt, 8) : nil
            let rec = ReplicationSnapshotRecord(
                id: sqlite3_column_int64(stmt, 0),
                snapshotId: columnText(stmt, 1),
                destinationType: columnText(stmt, 2),
                destinationIdentifier: columnText(stmt, 3),
                status: columnText(stmt, 4),
                replicatedBytes: sqlite3_column_int64(stmt, 5),
                totalBytes: sqlite3_column_int64(stmt, 6),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                completedAt: completedAtTime != nil ? Date(timeIntervalSince1970: completedAtTime!) : nil,
                errorMessage: columnOptionalText(stmt, 9)
            )
            records.append(rec)
        }
        return records
    }

    /// Records an individual replicated file record.
    public func recordReplicationFile(_ record: ReplicationFileRecord) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        INSERT INTO replication_files (snapshot_id, destination_identifier, relative_path, remote_key, remote_etag, checksum, file_size, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.snapshotId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, record.destinationIdentifier, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, record.relativePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, record.remoteKey, -1, SQLITE_TRANSIENT)
        if let etag = record.remoteETag {
            sqlite3_bind_text(stmt, 5, etag, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        if let chk = record.checksum {
            sqlite3_bind_text(stmt, 6, chk, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_int64(stmt, 7, record.fileSize)
        sqlite3_bind_text(stmt, 8, record.status, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Checks whether a file with matching relative path, checksum, and size is already synced to a remote destination.
    public func isReplicationFileSynced(
        destinationIdentifier: String,
        relativePath: String,
        checksum: String?,
        fileSize: Int64
    ) throws -> (isSynced: Bool, remoteKey: String?, remoteETag: String?) {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query: String
        if let chk = checksum, !chk.isEmpty {
            query = """
            SELECT remote_key, remote_etag
            FROM replication_files
            WHERE destination_identifier = ? AND relative_path = ? AND checksum = ? AND file_size = ? AND status = 'replicated'
            ORDER BY id DESC LIMIT 1;
            """
        } else {
            query = """
            SELECT remote_key, remote_etag
            FROM replication_files
            WHERE destination_identifier = ? AND relative_path = ? AND file_size = ? AND status = 'replicated'
            ORDER BY id DESC LIMIT 1;
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, destinationIdentifier, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, relativePath, -1, SQLITE_TRANSIENT)
        if let chk = checksum, !chk.isEmpty {
            sqlite3_bind_text(stmt, 3, chk, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, fileSize)
        } else {
            sqlite3_bind_int64(stmt, 3, fileSize)
        }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let key = columnText(stmt, 0)
            let etag = columnOptionalText(stmt, 1)
            return (true, key, etag)
        }
        return (false, nil, nil)
    }
}
