import Foundation
import OtterKeepDomain

/// Abstract repository port for querying and mutating snapshot metadata.
///
/// In accordance with Clean Architecture, this port isolates domain use cases from concrete
/// database drivers (e.g. SQLite, memory mocks, or remote catalogs).
public protocol SnapshotRepositoryProtocol: Sendable {
    /// Lists all snapshots in the catalog sorted by timestamp descending.
    func listSnapshots() async throws -> [SnapshotRecord]

    /// Retrieves a snapshot by its unique ID.
    func getSnapshot(id: String) async throws -> SnapshotRecord?

    /// Inserts a newly committed snapshot record.
    func insertSnapshot(_ record: SnapshotRecord) async throws

    /// Updates the WORM immutability lock date of a snapshot.
    func updateSnapshotLockedUntil(id: String, lockedUntil: Date?) async throws

    /// Deletes a snapshot record from the catalog.
    func deleteSnapshot(id: String) async throws
}
