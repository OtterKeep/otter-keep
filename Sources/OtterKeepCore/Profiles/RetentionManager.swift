import Foundation
import OtterKeepDatabase
import OtterKeepDomain
import OtterKeepStorage
import os

/// Actor-isolated manager executing Grandfather-Father-Son (GFS) snapshot retention pruning and atomic two-step deletion.
public actor RetentionManager {
    private let storage: FileSystemProvider
    private let database: DatabaseEngine
    private let logger = Logger(subsystem: "com.otterkeep", category: "RetentionManager")

    /// Initializes a `RetentionManager`.
    /// - Parameters:
    ///   - storage: Filesystem provider.
    ///   - database: Catalog database engine.
    public init(storage: FileSystemProvider = DefaultFileSystemProvider(), database: DatabaseEngine = DatabaseEngine()) {
        self.storage = storage
        self.database = database
    }

    /// Evaluates and applies Grandfather-Father-Son (GFS) retention rules against historical snapshots on the target disk.
    /// - Parameters:
    ///   - destinationURL: Backup destination root URL.
    ///   - policy: Pruning configuration policy.
    /// - Returns: Array of pruned snapshot IDs.
    public func applyRetentionPolicy(
        destinationURL: URL,
        policy: PruningPolicy
    ) async throws -> [String] {
        let snapshots = try await database.listSnapshots()
        guard !snapshots.isEmpty else { return [] }

        let decision = RetentionPolicyCalculator.evaluate(
            snapshots: snapshots,
            keepDailyDays: policy.keepDailyDays,
            keepWeeklyWeeks: nil,
            keepMonthlyMonths: nil,
            maxSnapshotsToKeep: policy.maxSnapshotsToKeep
        )
        let snapshotsToKeep = decision.keepSnapshotIds

        // Final guard: if snapshotsToKeep is empty for any reason, abort pruning to prevent total data loss
        guard !snapshotsToKeep.isEmpty else {
            logger.warning("Retention safety guard triggered: snapshotsToKeep is empty. Aborting pruning to prevent total data loss.")
            return []
        }

        let snapshotsToDelete = snapshots.filter { !snapshotsToKeep.contains($0.id) }
        var deletedIds: [String] = []

        for snap in snapshotsToDelete {
            if snap.isLocked { continue }
            try await deleteSnapshot(destinationURL: destinationURL, snapshot: snap, isPruning: true)
            deletedIds.append(snap.id)
        }

        if !deletedIds.isEmpty {
            await updateLatestSymlink(destinationURL: destinationURL)
        }

        logger.info("GFS retention pruning complete: \(deletedIds.count) snapshots removed")
        return deletedIds
    }

    /// Updates or cleans up the 'Latest' symlink at the destination root to point to the newest remaining snapshot.
    public func updateLatestSymlink(destinationURL: URL) async {
        let remainingSnapshots = (try? await database.listSnapshots()) ?? []
        let latestLink = destinationURL.standardizedFileURL.appendingPathComponent("Latest")
        let tempLink = destinationURL.standardizedFileURL.appendingPathComponent(".latest_temp")

        if let newest = remainingSnapshots.first {
            let targetDir = destinationURL.standardizedFileURL.appendingPathComponent(newest.snapshotPath)
            if FileManager.default.fileExists(atPath: targetDir.standardizedFileURL.path(percentEncoded: false)) {
                try? FileManager.default.removeItem(at: tempLink)
                do {
                    try FileManager.default.createSymbolicLink(at: tempLink, withDestinationURL: targetDir)
                    try await storage.atomicMove(from: tempLink, to: latestLink)
                    logger.info("Updated 'Latest' symlink to point to: \(newest.snapshotPath)")
                } catch {
                    logger.warning("Failed to update 'Latest' symlink: \(error.localizedDescription)")
                }
                return
            }
        }

        // If no snapshots remain, remove the dangling Latest link
        try? FileManager.default.removeItem(at: latestLink)
    }

    /// Safely deletes an individual snapshot by unlocking WORM immutability, staging to `.trash_<snapshotPath>`, and updating SQLite.
    /// - Parameters:
    ///   - destinationURL: Backup destination root URL.
    ///   - snapshot: The snapshot record to remove.
    ///   - isPruning: True when triggered by automated retention pruning policy.
    public func deleteSnapshot(destinationURL: URL, snapshot: SnapshotRecord, isPruning: Bool = false) async throws {
        if snapshot.isLocked {
            let msg = "Snapshot '\(snapshot.id)' is locked with WORM immutability until \(snapshot.lockedUntil?.description ?? ""). Deletion rejected."
            logger.error("\(msg)")
            throw FileSystemError.permissionDenied(path: "\(snapshot.snapshotPath) (\(msg))")
        }

        let snapshotDir = destinationURL.standardizedFileURL.appendingPathComponent(snapshot.snapshotPath)
        let trashDir = destinationURL.standardizedFileURL.appendingPathComponent(".trash_\(snapshot.snapshotPath)")

        logger.info("Initiating snapshot deletion (pruning: \(isPruning)): \(snapshot.id) (\(snapshot.snapshotPath))")

        // 0. Unlock BSD immutability (UF_IMMUTABLE) recursively before renaming/deleting
        if FileManager.default.fileExists(atPath: snapshotDir.standardizedFileURL.path(percentEncoded: false)) {
            try? storage.setImmutable(at: snapshotDir, immutable: false, recursive: true)
        }

        // 1. Atomically rename to hidden `.trash` directory so it disappears instantly from Finder
        if FileManager.default.fileExists(atPath: snapshotDir.standardizedFileURL.path(percentEncoded: false)) {
            try await storage.atomicMove(from: snapshotDir, to: trashDir)
        }

        // 2. Delete database records
        try await database.deleteSnapshot(id: snapshot.id)

        // 3. Remove physical files in background
        if FileManager.default.fileExists(atPath: trashDir.standardizedFileURL.path(percentEncoded: false)) {
            try? storage.setImmutable(at: trashDir, immutable: false, recursive: true)
            try storage.removeItem(at: trashDir)
        }

        logger.info("Snapshot physical removal and extent deallocation complete: \(snapshot.id)")
    }
}
