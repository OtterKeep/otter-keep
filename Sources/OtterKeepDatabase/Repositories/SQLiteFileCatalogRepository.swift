import Foundation
import OtterKeepDomain
import OtterKeepApplication

/// SQLite infrastructure repository implementing `FileCatalogRepositoryProtocol`.
public final class SQLiteFileCatalogRepository: FileCatalogRepositoryProtocol, Sendable {
    private let databasePath: String

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    private func withDatabase<T: Sendable>(_ action: (DatabaseEngine) async throws -> T) async throws -> T {
        let db = DatabaseEngine()
        try await db.open(at: databasePath)
        do {
            let result = try await action(db)
            await db.close()
            return result
        } catch {
            await db.close()
            throw error
        }
    }

    public func listFiles(forSnapshotId snapshotId: String) async throws -> [FileCatalogRecord] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }
        return try await withDatabase { db in
            try await db.listFiles(forSnapshotId: snapshotId)
        }
    }

    public func listVersions(ofRelativePath relativePath: String) async throws -> [(snapshot: SnapshotRecord, file: FileCatalogRecord)] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }
        return try await withDatabase { db in
            try await db.listVersions(ofRelativePath: relativePath)
        }
    }

    public func insertBatch(_ records: [FileCatalogRecord]) async throws {
        try await withDatabase { db in
            try await db.insertFileRecordsBatch(records)
        }
    }

    public func searchGlobal(query: String) async throws -> [GlobalSearchResult] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }
        return try await withDatabase { db in
            try await db.searchFilesAcrossSnapshots(query: query)
        }
    }
}
