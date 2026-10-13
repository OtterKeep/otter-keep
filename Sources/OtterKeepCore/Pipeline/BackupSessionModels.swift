import Foundation
import os
import AppKit
import OtterKeepStorage
import OtterKeepDatabase

/// Operational phases of the incremental backup workflow.
public enum BackupPhase: String, Sendable {
    /// Idle state awaiting backup initiation.
    case idle = "idle"
    /// Scanning source directory and evaluating exclusion rules.
    case scanning = "scanning"
    /// Running differential change detection against the previous snapshot.
    case analyzing = "analyzing"
    /// Copying new/modified files and creating APFS reflink clones.
    case copying = "copying"
    /// Committing snapshot metadata, immutability flags, and catalog index.
    case committing = "committing"
    /// Backup successfully completed.
    case completed = "completed"
    /// Backup failed with an unrecoverable error.
    case failed = "failed"

    /// Corresponding localization key.
    public var localizedKey: L10n.Key {
        switch self {
        case .idle: return .phaseIdle
        case .scanning: return .phaseScanning
        case .analyzing: return .phaseAnalyzing
        case .copying: return .phaseCopying
        case .committing: return .phaseFinalizing
        case .completed: return .phaseCompleted
        case .failed: return .phaseFailed
        }
    }

    /// Localized display description.
    public var localizedDescription: String {
        L10n.t(localizedKey)
    }
}

/// Execution mode for a backup operation.
public enum BackupMode: String, Codable, Sendable {
    /// Standard incremental backup comparing against previous catalog with APFS CoW deduplication.
    case incremental = "incremental"
    /// Forced full backup ignoring previous snapshots and freshly copying all files from source.
    case full = "full"

    /// Localized display title.
    public var localizedTitle: String {
        switch self {
        case .incremental: return L10n.t(.backupTypeIncremental)
        case .full: return L10n.t(.backupTypeFull)
        }
    }
}

/// Representation of an individual file error encountered during a backup operation.
public struct BackupErrorItem: Sendable, Equatable, Identifiable {
    /// Stable identifier for SwiftUI collections.
    public var id: String { relativePath + "_" + errorMessage }
    /// File URL that failed.
    public let url: URL
    /// Relative path of the failed item.
    public let relativePath: String
    /// Detailed error message.
    public let errorMessage: String
    /// Indicates whether the error was caused by missing permissions.
    public let isPermissionError: Bool

    /// Initializes a `BackupErrorItem`.
    public init(url: URL, relativePath: String, errorMessage: String, isPermissionError: Bool = false) {
        self.url = url
        self.relativePath = relativePath
        self.errorMessage = errorMessage
        self.isPermissionError = isPermissionError
    }
}

/// Comprehensive summary metrics recorded at the end of a backup session.
public struct BackupSessionSummary: Sendable, Equatable {
    /// Unique snapshot identifier.
    public let snapshotId: String
    /// Name of the profile that executed the backup.
    public let profileName: String
    /// Execution timestamp.
    public let timestamp: Date
    /// Total duration in seconds.
    public let durationSeconds: Double
    /// Total source files scanned.
    public let totalScannedFiles: Int
    /// Total source bytes scanned.
    public let totalScannedBytes: Int64
    /// Number of newly copied or modified files.
    public let copiedCount: Int
    /// Total byte size of transferred files.
    public let copiedBytes: Int64
    /// Number of files deduplicated via APFS Copy-on-Write (reflink).
    public let clonedCount: Int
    /// Total byte size of reflinked files.
    public let clonedBytes: Int64
    /// Total number of skipped items.
    public let skippedCount: Int
    /// Total number of encountered errors.
    public let errorCount: Int
    /// List of items skipped during scan.
    public let skippedItems: [SkippedItem]
    /// List of file errors encountered during copy.
    public let errorItems: [BackupErrorItem]
    /// Final completion status string.
    public let status: String
    /// Average data throughput in bytes per second.
    public let averageSpeedBytesPerSecond: Double
    /// Count of older snapshots pruned by retention rules.
    public let autoPrunedSnapshotsCount: Int

    /// Initializes a `BackupSessionSummary`.
    public init(
        snapshotId: String,
        profileName: String,
        timestamp: Date,
        durationSeconds: Double,
        totalScannedFiles: Int,
        totalScannedBytes: Int64,
        copiedCount: Int,
        copiedBytes: Int64,
        clonedCount: Int,
        clonedBytes: Int64,
        skippedCount: Int,
        errorCount: Int,
        skippedItems: [SkippedItem],
        errorItems: [BackupErrorItem],
        status: String,
        averageSpeedBytesPerSecond: Double,
        autoPrunedSnapshotsCount: Int = 0
    ) {
        self.snapshotId = snapshotId
        self.profileName = profileName
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.totalScannedFiles = totalScannedFiles
        self.totalScannedBytes = totalScannedBytes
        self.copiedCount = copiedCount
        self.copiedBytes = copiedBytes
        self.clonedCount = clonedCount
        self.clonedBytes = clonedBytes
        self.skippedCount = skippedCount
        self.errorCount = errorCount
        self.skippedItems = skippedItems
        self.errorItems = errorItems
        self.status = status
        self.averageSpeedBytesPerSecond = averageSpeedBytesPerSecond
        self.autoPrunedSnapshotsCount = autoPrunedSnapshotsCount
    }
}

/// Real-time progress state broadcasted during a live backup run.
public struct BackupProgressState: Sendable {
    /// Active operational phase.
    public var phase: BackupPhase
    /// Total number of files to process.
    public var totalFiles: Int
    /// Number of files processed so far.
    public var processedFiles: Int
    /// Total bytes requiring transfer.
    public var totalBytes: Int64
    /// Bytes transferred so far.
    public var processedBytes: Int64
    /// Current file path being processed.
    public var currentItem: String
    /// Current transfer speed in bytes per second.
    public var speedBytesPerSecond: Double

    /// Telemetry counters
    public var copiedCount: Int
    public var copiedBytes: Int64
    public var clonedCount: Int
    public var clonedBytes: Int64
    public var skippedCount: Int
    public var errorCount: Int
    public var skippedItems: [SkippedItem]
    public var errorItems: [BackupErrorItem]
    public var estimatedRemainingSeconds: TimeInterval?
    public var lastSummary: BackupSessionSummary?

    /// Initializes a `BackupProgressState`.
    public init(
        phase: BackupPhase = .idle,
        totalFiles: Int = 0,
        processedFiles: Int = 0,
        totalBytes: Int64 = 0,
        processedBytes: Int64 = 0,
        currentItem: String = "",
        speedBytesPerSecond: Double = 0,
        copiedCount: Int = 0,
        copiedBytes: Int64 = 0,
        clonedCount: Int = 0,
        clonedBytes: Int64 = 0,
        skippedCount: Int = 0,
        errorCount: Int = 0,
        skippedItems: [SkippedItem] = [],
        errorItems: [BackupErrorItem] = [],
        estimatedRemainingSeconds: TimeInterval? = nil,
        lastSummary: BackupSessionSummary? = nil
    ) {
        self.phase = phase
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.currentItem = currentItem
        self.speedBytesPerSecond = speedBytesPerSecond
        self.copiedCount = copiedCount
        self.copiedBytes = copiedBytes
        self.clonedCount = clonedCount
        self.clonedBytes = clonedBytes
        self.skippedCount = skippedCount
        self.errorCount = errorCount
        self.skippedItems = skippedItems
        self.errorItems = errorItems
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
        self.lastSummary = lastSummary
    }
}

/// Pre-backup simulation summary estimating disk space requirements without writing files.
public struct DryRunSummary: Sendable, Equatable {
    /// Total files scanned at source.
    public let totalScannedFiles: Int
    /// Total byte size of scanned source files.
    public let totalScannedBytes: Int64
    /// Count of newly added files.
    public let addedCount: Int
    /// Byte size of newly added files.
    public let addedBytes: Int64
    /// Count of modified files.
    public let modifiedCount: Int
    /// Byte size of modified files.
    public let modifiedBytes: Int64
    /// Count of deleted files.
    public let deletedCount: Int
    /// Count of unmodified files eligible for APFS reflink deduplication.
    public let unmodifiedCount: Int
    /// Estimated net additional disk storage required.
    public let estimatedNewBytes: Int64
    /// Number of skipped items.
    public let skippedCount: Int
    /// List of skipped items.
    public let skippedItems: [SkippedItem]
    /// List of relative paths for added items.
    public let addedPaths: [String]
    /// List of relative paths for modified items.
    public let modifiedPaths: [String]
    /// List of relative paths for deleted items.
    public let deletedPaths: [String]

    /// Initializes a `DryRunSummary`.
    public init(
        totalScannedFiles: Int,
        totalScannedBytes: Int64,
        addedCount: Int,
        addedBytes: Int64,
        modifiedCount: Int,
        modifiedBytes: Int64,
        deletedCount: Int,
        unmodifiedCount: Int,
        estimatedNewBytes: Int64,
        skippedCount: Int,
        skippedItems: [SkippedItem] = [],
        addedPaths: [String] = [],
        modifiedPaths: [String] = [],
        deletedPaths: [String] = []
    ) {
        self.totalScannedFiles = totalScannedFiles
        self.totalScannedBytes = totalScannedBytes
        self.addedCount = addedCount
        self.addedBytes = addedBytes
        self.modifiedCount = modifiedCount
        self.modifiedBytes = modifiedBytes
        self.deletedCount = deletedCount
        self.unmodifiedCount = unmodifiedCount
        self.estimatedNewBytes = estimatedNewBytes
        self.skippedCount = skippedCount
        self.skippedItems = skippedItems
        self.addedPaths = addedPaths
        self.modifiedPaths = modifiedPaths
        self.deletedPaths = deletedPaths
    }
}

/// Actor-isolated coordinator orchestrating the atomic, incremental APFS Copy-on-Write backup lifecycle.
