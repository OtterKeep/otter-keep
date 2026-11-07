import Foundation

/// Pure domain representation of a deferred or pending secondary replication task awaiting destination availability.
public struct PendingReplicationRecord: Sendable, Identifiable, Equatable {
    public let id: String
    public let profileId: UUID
    public let snapshotId: String
    public let destinationId: UUID
    public let destinationType: String
    public let status: String
    public let retryCount: Int
    public let createdAt: Date
    public let lastAttemptAt: Date?
    public let errorMessage: String?

    public init(
        id: String = UUID().uuidString,
        profileId: UUID,
        snapshotId: String,
        destinationId: UUID,
        destinationType: String,
        status: String = "pending",
        retryCount: Int = 0,
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.profileId = profileId
        self.snapshotId = snapshotId
        self.destinationId = destinationId
        self.destinationType = destinationType
        self.status = status
        self.retryCount = retryCount
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.errorMessage = errorMessage
    }
}
