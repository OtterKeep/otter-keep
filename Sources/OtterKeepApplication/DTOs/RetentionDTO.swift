import Foundation
import OtterKeepDomain

/// Data Transfer Object representing the outcome of a retention policy evaluation.
public struct RetentionEvaluationDTO: Sendable, Codable, Equatable {
    public let keepSnapshotIds: [String]
    public let pruneSnapshotIds: [String]
    public let totalEvaluated: Int

    public init(keepSnapshotIds: [String], pruneSnapshotIds: [String], totalEvaluated: Int) {
        self.keepSnapshotIds = keepSnapshotIds
        self.pruneSnapshotIds = pruneSnapshotIds
        self.totalEvaluated = totalEvaluated
    }

    public init(from decision: RetentionDecision) {
        self.keepSnapshotIds = decision.keepSnapshotIds.sorted()
        self.pruneSnapshotIds = decision.pruneSnapshotIds
        self.totalEvaluated = decision.keepSnapshotIds.count + decision.pruneSnapshotIds.count
    }

    public func toDomain() -> RetentionDecision {
        RetentionDecision(keepSnapshotIds: Set(keepSnapshotIds), pruneSnapshotIds: pruneSnapshotIds)
    }
}
