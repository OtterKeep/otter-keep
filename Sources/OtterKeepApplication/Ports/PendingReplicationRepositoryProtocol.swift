import Foundation
import OtterKeepDomain

/// Abstract repository port for managing deferred secondary replication jobs.
public protocol PendingReplicationRepositoryProtocol: Sendable {
    /// Lists all pending replication jobs awaiting synchronization.
    func listPendingReplications() async throws -> [PendingReplicationRecord]

    /// Enqueues a new pending replication job.
    func insertPendingReplication(_ record: PendingReplicationRecord) async throws

    /// Updates execution status and retry counters for a replication job.
    func updatePendingReplicationStatus(id: String, status: String, errorMessage: String?) async throws

    /// Deletes a completed or discarded replication job from the queue.
    func deletePendingReplication(id: String) async throws
}
