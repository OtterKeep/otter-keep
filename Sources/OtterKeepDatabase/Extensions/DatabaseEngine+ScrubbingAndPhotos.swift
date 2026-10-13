import Foundation
import SQLite3
import os

extension DatabaseEngine {
    // MARK: - Data Scrubbing Audit Operations

    /// Inserts a new scrubbing audit log record into SQLite.
    /// - Parameter record: The scrub audit result to persist.
    public func insertScrubAudit(_ record: ScrubAuditRecord) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        INSERT INTO scrub_audit_logs (timestamp, checked_snapshots_count, checked_files_count, corrupted_files_count, status, details_json)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, record.timestamp.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 2, Int64(record.checkedSnapshotsCount))
        sqlite3_bind_int64(stmt, 3, Int64(record.checkedFilesCount))
        sqlite3_bind_int64(stmt, 4, Int64(record.corruptedFilesCount))
        sqlite3_bind_text(stmt, 5, record.status, -1, SQLITE_TRANSIENT)
        if let json = record.detailsJson {
            sqlite3_bind_text(stmt, 6, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Lists past scrubbing audit records in reverse chronological order.
    /// - Parameter limit: Maximum entries to return.
    /// - Returns: Array of `ScrubAuditRecord` items.
    public func listScrubAudits(limit: Int = 50) throws -> [ScrubAuditRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT id, timestamp, checked_snapshots_count, checked_files_count, corrupted_files_count, status, details_json
        FROM scrub_audit_logs ORDER BY timestamp DESC LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(limit))

        var results: [ScrubAuditRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let ts = sqlite3_column_double(stmt, 1)
            let checkedSnaps = Int(sqlite3_column_int64(stmt, 2))
            let checkedFiles = Int(sqlite3_column_int64(stmt, 3))
            let corruptedFiles = Int(sqlite3_column_int64(stmt, 4))
            let status = columnText(stmt, 5)
            let details = columnOptionalText(stmt, 6)

            results.append(ScrubAuditRecord(
                id: id,
                timestamp: Date(timeIntervalSince1970: ts),
                checkedSnapshotsCount: checkedSnaps,
                checkedFilesCount: checkedFiles,
                corruptedFilesCount: corruptedFiles,
                status: status,
                detailsJson: details
            ))
        }
        return results
    }

    /// Searches distinct relative paths across all snapshots matching an optional substring query.
    /// - Parameters:
    ///   - query: Substring filter pattern (empty string matches all).
    ///   - limit: Maximum number of paths to return.
    /// - Returns: Array of distinct relative file paths.
    public func searchDistinctRelativePaths(matching query: String = "", limit: Int = 100) throws -> [String] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let sql: String
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sql = "SELECT DISTINCT relative_path FROM file_records ORDER BY relative_path ASC LIMIT ?;"
        } else {
            sql = "SELECT DISTINCT relative_path FROM file_records WHERE relative_path LIKE ? ORDER BY relative_path ASC LIMIT ?;"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sql, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        if trimmed.isEmpty {
            sqlite3_bind_int(stmt, 1, Int32(limit))
        } else {
            let pattern = "%\(trimmed)%"
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }

        var paths: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = columnText(stmt, 0)
            paths.append(path)
        }
        return paths
    }

    /// Performs a high-performance cross-snapshot search across all indexed catalog records.
    /// - Parameters:
    ///   - query: Substring or filename pattern to search for.
    ///   - limit: Maximum number of search results to return (default: 100).
    /// - Returns: Array of `GlobalSearchResult` records.
    public func searchFilesAcrossSnapshots(
        query: String,
        limit: Int = 100
    ) throws -> [GlobalSearchResult] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql: String
        if trimmed.isEmpty {
            sql = """
            SELECT fr.snapshot_id, s.timestamp, s.snapshot_path, fr.relative_path, fr.file_size, fr.mtime, COALESCE(fr.checksum, '')
            FROM file_records fr
            JOIN snapshots s ON s.id = fr.snapshot_id
            WHERE fr.is_directory = 0
            ORDER BY s.timestamp DESC, fr.relative_path ASC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT fr.snapshot_id, s.timestamp, s.snapshot_path, fr.relative_path, fr.file_size, fr.mtime, COALESCE(fr.checksum, '')
            FROM file_records fr
            JOIN snapshots s ON s.id = fr.snapshot_id
            WHERE fr.is_directory = 0 AND fr.relative_path LIKE ?
            ORDER BY s.timestamp DESC, fr.relative_path ASC
            LIMIT ?;
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sql, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        if trimmed.isEmpty {
            sqlite3_bind_int(stmt, 1, Int32(limit))
        } else {
            let pattern = "%\(trimmed)%"
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }

        var results: [GlobalSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sId = columnText(stmt, 0)
            let ts = sqlite3_column_double(stmt, 1)
            let snapPath = columnText(stmt, 2)
            let path = columnText(stmt, 3)
            let size = sqlite3_column_int64(stmt, 4)
            let mtime = sqlite3_column_double(stmt, 5)
            let sha = columnText(stmt, 6)

            results.append(GlobalSearchResult(
                snapshotId: sId,
                snapshotTimestamp: Date(timeIntervalSince1970: ts),
                snapshotPath: snapPath,
                relativePath: path,
                fileSize: size,
                modificationDate: Date(timeIntervalSince1970: mtime),
                sha256: sha
            ))
        }
        return results
    }

    // MARK: - Photos Asset Batch Insertion & Queries

    /// Inserts an array of Photos asset records inside an atomic SQLite transaction.
    /// - Parameter records: Array of `PhotosAssetRecord` entries.
    public func insertPhotosAssetRecordsBatch(_ records: [PhotosAssetRecord]) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        guard !records.isEmpty else { return }

        try execute(query: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let query = """
            INSERT INTO photos_asset_records (
                snapshot_id, local_identifier, original_filename, relative_path,
                file_size, mtime, sha256, is_edited, is_live_photo, media_type, albums_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            for rec in records {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_text(stmt, 1, rec.snapshotId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, rec.localIdentifier, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, rec.originalFilename, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, rec.relativePath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 5, rec.fileSize)
                sqlite3_bind_double(stmt, 6, rec.modificationTime.timeIntervalSince1970)
                if let sha = rec.sha256 {
                    sqlite3_bind_text(stmt, 7, sha, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                sqlite3_bind_int(stmt, 8, rec.isEdited ? 1 : 0)
                sqlite3_bind_int(stmt, 9, rec.isLivePhoto ? 1 : 0)
                sqlite3_bind_text(stmt, 10, rec.mediaType, -1, SQLITE_TRANSIENT)
                if let albums = rec.albumsJson {
                    sqlite3_bind_text(stmt, 11, albums, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 11)
                }

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
                }
            }
            try execute(query: "COMMIT;")
        } catch {
            try? execute(query: "ROLLBACK;")
            throw error
        }
    }

    /// Fetches all Photos asset records for a specific snapshot identifier.
    /// - Parameter snapshotId: The snapshot ID.
    /// - Returns: Array of `PhotosAssetRecord`.
    public func fetchPhotosAssetRecords(for snapshotId: String) throws -> [PhotosAssetRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT id, snapshot_id, local_identifier, original_filename, relative_path,
               file_size, mtime, sha256, is_edited, is_live_photo, media_type, albums_json
        FROM photos_asset_records
        WHERE snapshot_id = ?
        ORDER BY relative_path ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, snapshotId, -1, SQLITE_TRANSIENT)

        var records: [PhotosAssetRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rec = PhotosAssetRecord(
                id: sqlite3_column_int64(stmt, 0),
                snapshotId: columnText(stmt, 1),
                localIdentifier: columnText(stmt, 2),
                originalFilename: columnText(stmt, 3),
                relativePath: columnText(stmt, 4),
                fileSize: sqlite3_column_int64(stmt, 5),
                modificationTime: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                sha256: columnOptionalText(stmt, 7),
                isEdited: sqlite3_column_int(stmt, 8) == 1,
                isLivePhoto: sqlite3_column_int(stmt, 9) == 1,
                mediaType: columnText(stmt, 10),
                albumsJson: columnOptionalText(stmt, 11)
            )
            records.append(rec)
        }
        return records
    }

    /// Lists all snapshots (alias for listSnapshots).
    public func fetchSnapshots() throws -> [SnapshotRecord] {
        try listSnapshots()
    }

    /// Fetches the most recent snapshot record if available.
    public func fetchLatestSnapshot() throws -> SnapshotRecord? {
        try listSnapshots().first
    }

    /// Fetches the most recent Photos asset records across the latest snapshot.
    /// - Returns: Dictionary mapping localIdentifier to `PhotosAssetRecord`.
    public func fetchLatestPhotosAssetIndex() throws -> [String: PhotosAssetRecord] {
        guard db != nil else { throw DatabaseError.openFailed("Database is not open") }
        guard let latestSnap = try fetchLatestSnapshot() else { return [:] }

        let records = try fetchPhotosAssetRecords(for: latestSnap.id)
        var dict: [String: PhotosAssetRecord] = [:]
        for r in records {
            dict[r.localIdentifier] = r
        }
        return dict
    }


}
