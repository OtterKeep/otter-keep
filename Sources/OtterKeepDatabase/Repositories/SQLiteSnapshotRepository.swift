import Foundation
import OtterKeepDomain
import OtterKeepApplication

/// SQLite infrastructure repository implementing `SnapshotRepositoryProtocol`.
///
/// Encapsulates connection lifecycle management, WAL checkpoints, and transaction isolation.
public final class SQLiteSnapshotRepository: SnapshotRepositoryProtocol, Sendable {
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

    public func listSnapshots() async throws -> [SnapshotRecord] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }
        return try await withDatabase { db in
            try await db.listSnapshots()
        }
    }

    public func getSnapshot(id: String) async throws -> SnapshotRecord? {
        guard FileManager.default.fileExists(atPath: databasePath) else { return nil }
        return try await withDatabase { db in
            let all = try await db.listSnapshots()
            return all.first(where: { $0.id == id })
        }
    }

    public func insertSnapshot(_ record: SnapshotRecord) async throws {
        try await withDatabase { db in
            try await db.insertSnapshot(record)
        }
    }

    public func updateSnapshotLockedUntil(id: String, lockedUntil: Date?) async throws {
        try await withDatabase { db in
            try await db.updateSnapshotLockedUntil(id: id, lockedUntil: lockedUntil)
        }
    }

    public func deleteSnapshot(id: String) async throws {
        guard FileManager.default.fileExists(atPath: databasePath) else { return }
        try await withDatabase { db in
            try await db.deleteSnapshot(id: id)
        }
    }
}
