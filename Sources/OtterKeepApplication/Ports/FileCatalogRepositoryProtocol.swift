import Foundation
import OtterKeepDomain

/// Abstract repository port for querying and indexing file catalog entries.
public protocol FileCatalogRepositoryProtocol: Sendable {
    /// Lists all file catalog entries for a given snapshot ID.
    func listFiles(forSnapshotId snapshotId: String) async throws -> [FileCatalogRecord]

    /// Queries the point-in-time version history for a specific relative file path across all snapshots.
    func listVersions(ofRelativePath relativePath: String) async throws -> [(snapshot: SnapshotRecord, file: FileCatalogRecord)]

    /// Batch inserts file catalog records during snapshot commitment.
    func insertBatch(_ records: [FileCatalogRecord]) async throws

    /// Performs cross-snapshot global keyword search across indexed files.
    func searchGlobal(query: String) async throws -> [GlobalSearchResult]
}
