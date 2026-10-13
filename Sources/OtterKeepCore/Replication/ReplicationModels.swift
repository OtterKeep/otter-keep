import Foundation
import os
import OtterKeepStorage
import OtterKeepDatabase

/// Summary metrics of a completed 3-2-1 replication copy job run.
public struct ReplicationJobSummary: Sendable, Equatable {
    public let snapshotId: String
    public let profileId: UUID
    public let totalDestinations: Int
    public let successfulDestinations: Int
    public let replicatedFiles: Int
    public let replicatedBytes: Int64
    public let skippedFiles: Int
    public let durationSeconds: Double
    public let status: String

    public init(
        snapshotId: String,
        profileId: UUID,
        totalDestinations: Int,
        successfulDestinations: Int,
        replicatedFiles: Int,
        replicatedBytes: Int64,
        skippedFiles: Int,
        durationSeconds: Double,
        status: String
    ) {
        self.snapshotId = snapshotId
        self.profileId = profileId
        self.totalDestinations = totalDestinations
        self.successfulDestinations = successfulDestinations
        self.replicatedFiles = replicatedFiles
        self.replicatedBytes = replicatedBytes
        self.skippedFiles = skippedFiles
        self.durationSeconds = durationSeconds
        self.status = status
    }
}

/// Real-time progress state broadcasted during a live 3-2-1 backup copy job.
public struct ReplicationProgressState: Sendable {
    public var isRunning: Bool
    public var currentDestinationName: String
    public var totalFiles: Int
    public var processedFiles: Int
    public var totalBytes: Int64
    public var replicatedBytes: Int64
    public var currentFile: String
    public var speedBytesPerSecond: Double
    public var statusMessage: String

    public init(
        isRunning: Bool = false,
        currentDestinationName: String = "",
        totalFiles: Int = 0,
        processedFiles: Int = 0,
        totalBytes: Int64 = 0,
        replicatedBytes: Int64 = 0,
        currentFile: String = "",
        speedBytesPerSecond: Double = 0,
        statusMessage: String = ""
    ) {
        self.isRunning = isRunning
        self.currentDestinationName = currentDestinationName
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.totalBytes = totalBytes
        self.replicatedBytes = replicatedBytes
        self.currentFile = currentFile
        self.speedBytesPerSecond = speedBytesPerSecond
        self.statusMessage = statusMessage
    }
}

/// Internal outcome metrics for a single destination sync execution.
struct DestinationSyncResult: Sendable {
    let replicatedFiles: Int
    let replicatedBytes: Int64
    let skippedFiles: Int
    let isSuccess: Bool
}

