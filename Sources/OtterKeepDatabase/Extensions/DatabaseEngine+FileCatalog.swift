import Foundation
import SQLite3
import os

extension DatabaseEngine {
    // MARK: - File Catalog Batch Insertion

    /// Inserts an array of file catalog records inside an atomic SQLite transaction.
    /// - Parameter records: Array of `FileCatalogRecord` entries.
    public func insertFileRecordsBatch(_ records: [FileCatalogRecord]) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        guard !records.isEmpty else { return }

        try execute(query: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let query = """
            INSERT INTO file_records (snapshot_id, relative_path, file_size, mtime, inode, checksum, is_directory, is_symlink, sample_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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
                sqlite3_bind_text(stmt, 2, rec.relativePath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 3, rec.fileSize)
                sqlite3_bind_double(stmt, 4, rec.modificationTime.timeIntervalSince1970)
                sqlite3_bind_int64(stmt, 5, Int64(bitPattern: rec.inode))
                if let checksum = rec.checksum {
                    sqlite3_bind_text(stmt, 6, checksum, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                sqlite3_bind_int(stmt, 7, rec.isDirectory ? 1 : 0)
                sqlite3_bind_int(stmt, 8, rec.isSymlink ? 1 : 0)
                if let sHash = rec.sampleHash {
                    sqlite3_bind_text(stmt, 9, sHash, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 9)
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

    /// Lists all file catalog records associated with a snapshot ID.
    /// - Parameter snapshotId: The snapshot identifier.
    /// - Returns: Array of `FileCatalogRecord` entries sorted by relative path.
    public func listFiles(forSnapshotId snapshotId: String) throws -> [FileCatalogRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT id, snapshot_id, relative_path, file_size, mtime, inode, checksum, is_directory, is_symlink, sample_hash
        FROM file_records WHERE snapshot_id = ? ORDER BY relative_path ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, snapshotId, -1, SQLITE_TRANSIENT)

        var records: [FileCatalogRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let sId = columnText(stmt, 1)
            let path = columnText(stmt, 2)
            let size = sqlite3_column_int64(stmt, 3)
            let mtime = sqlite3_column_double(stmt, 4)
            let inode = UInt64(bitPattern: sqlite3_column_int64(stmt, 5))
            let checksumText = columnOptionalText(stmt, 6)
            let isDir = sqlite3_column_int(stmt, 7) == 1
            let isLnk = sqlite3_column_int(stmt, 8) == 1
            let sampleHashText = columnOptionalText(stmt, 9)

            records.append(FileCatalogRecord(
                id: id,
                snapshotId: sId,
                relativePath: path,
                fileSize: size,
                modificationTime: Date(timeIntervalSince1970: mtime),
                inode: inode,
                checksum: checksumText,
                sampleHash: sampleHashText,
                isDirectory: isDir,
                isSymlink: isLnk
            ))
        }
        return records
    }

    /// Finds all historical catalog records for a specific relative file path.
    /// - Parameter relativePath: The relative path to query.
    /// - Returns: Array of `FileCatalogRecord` entries in reverse chronological order.
    public func findFileVersions(relativePath: String) throws -> [FileCatalogRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT fr.id, fr.snapshot_id, fr.relative_path, fr.file_size, fr.mtime, fr.inode, fr.checksum, fr.is_directory, fr.is_symlink, fr.sample_hash
        FROM file_records fr
        JOIN snapshots s ON s.id = fr.snapshot_id
        WHERE fr.relative_path = ?
        ORDER BY s.timestamp DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, relativePath, -1, SQLITE_TRANSIENT)

        var records: [FileCatalogRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let sId = columnText(stmt, 1)
            let path = columnText(stmt, 2)
            let size = sqlite3_column_int64(stmt, 3)
            let mtime = sqlite3_column_double(stmt, 4)
            let inode = UInt64(bitPattern: sqlite3_column_int64(stmt, 5))
            let checksumText = columnOptionalText(stmt, 6)
            let isDir = sqlite3_column_int(stmt, 7) == 1
            let isLnk = sqlite3_column_int(stmt, 8) == 1
            let sampleHashText = columnOptionalText(stmt, 9)

            records.append(FileCatalogRecord(
                id: id,
                snapshotId: sId,
                relativePath: path,
                fileSize: size,
                modificationTime: Date(timeIntervalSince1970: mtime),
                inode: inode,
                checksum: checksumText,
                sampleHash: sampleHashText,
                isDirectory: isDir,
                isSymlink: isLnk
            ))
        }
        return records
    }

    /// Queries all historical versions of a relative path along with their corresponding snapshot manifests.
    /// - Parameter path: The relative file path.
    /// - Returns: Array of snapshot and file record tuples sorted from newest to oldest.
    public func listVersions(ofRelativePath path: String) throws -> [(snapshot: SnapshotRecord, file: FileCatalogRecord)] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT
            s.id, s.timestamp, s.status, s.total_files, s.total_bytes, s.snapshot_path, s.backup_type,
            fr.id, fr.snapshot_id, fr.relative_path, fr.file_size, fr.mtime, fr.inode, fr.checksum, fr.is_directory, fr.is_symlink, fr.sample_hash
        FROM file_records fr
        JOIN snapshots s ON s.id = fr.snapshot_id
        WHERE fr.relative_path = ?
        ORDER BY s.timestamp DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)

        var results: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let snapId = columnText(stmt, 0)
            let snapTimestamp = sqlite3_column_double(stmt, 1)
            let snapStatus = columnText(stmt, 2)
            let snapTotalFiles = sqlite3_column_int64(stmt, 3)
            let snapTotalBytes = sqlite3_column_int64(stmt, 4)
            let snapPath = columnText(stmt, 5)
            var snapBackupType = columnText(stmt, 6)
            if snapBackupType.isEmpty { snapBackupType = "incremental" }

            let snapshot = SnapshotRecord(
                id: snapId,
                timestamp: Date(timeIntervalSince1970: snapTimestamp),
                status: snapStatus,
                totalFiles: snapTotalFiles,
                totalBytes: snapTotalBytes,
                snapshotPath: snapPath,
                backupType: snapBackupType
            )

            let fileId = sqlite3_column_int64(stmt, 7)
            let fileSnapId = columnText(stmt, 8)
            let filePath = columnText(stmt, 9)
            let fileSize = sqlite3_column_int64(stmt, 10)
            let fileMtime = sqlite3_column_double(stmt, 11)
            let fileInode = UInt64(bitPattern: sqlite3_column_int64(stmt, 12))
            let checksumText = columnOptionalText(stmt, 13)
            let isDir = sqlite3_column_int(stmt, 14) == 1
            let isLnk = sqlite3_column_int(stmt, 15) == 1
            let sampleHashText = columnOptionalText(stmt, 16)

            let fileRecord = FileCatalogRecord(
                id: fileId,
                snapshotId: fileSnapId,
                relativePath: filePath,
                fileSize: fileSize,
                modificationTime: Date(timeIntervalSince1970: fileMtime),
                inode: fileInode,
                checksum: checksumText,
                sampleHash: sampleHashText,
                isDirectory: isDir,
                isSymlink: isLnk
            )

            results.append((snapshot: snapshot, file: fileRecord))
        }
        return results
    }


}
