import Foundation
import os
import OtterKeepStorage
import OtterKeepDatabase

/// Actor orchestrating the secondary replication pipeline (3-2-1 Backup Copy Job) to S3 Cloud and NAS storage.
public actor BackupCopyJobCoordinator {
    let storage: FileSystemProvider
    let database: DatabaseEngine
    let logger = Logger(subsystem: "com.otterkeep", category: "Replication")

    public typealias ProgressHandler = @Sendable (ReplicationProgressState) -> Void
    var onProgress: ProgressHandler?

    public init(storage: FileSystemProvider, database: DatabaseEngine) {
        self.storage = storage
        self.database = database
    }

    /// Sets the progress update callback.
    public func setProgressHandler(_ handler: @escaping ProgressHandler) {
        self.onProgress = handler
    }

    /// Executes the 3-2-1 replication copy job for a given profile and snapshot.
    /// - Parameters:
    ///   - profile: The backup profile.
    ///   - targetSnapshotId: Optional snapshot ID (if nil, uses latest completed snapshot).
    /// - Returns: Summary of replication results.
    public func executeReplication(
        profile: BackupProfile,
        targetSnapshotId: String? = nil
    ) async throws -> ReplicationJobSummary {
        let startTime = Date()
        let destinations = profile.copyJobConfig.destinations.filter { $0.isEnabled }

        guard profile.copyJobConfig.isEnabled, !destinations.isEmpty else {
            logger.info("3-2-1 Replication copy job is not enabled or has no active destinations.")
            return ReplicationJobSummary(
                snapshotId: targetSnapshotId ?? "",
                profileId: profile.id,
                totalDestinations: 0,
                successfulDestinations: 0,
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                durationSeconds: 0,
                status: "skipped_no_destinations"
            )
        }

        // 1. Verify Network Policy (including Wi-Fi SSID rules and metered connection guard)
        let unmeteredOnly = profile.copyJobConfig.networkPolicy == .unmeteredOnly || profile.copyJobConfig.pauseOnMeteredNetwork
        let eval = NetworkReachability.shared.evaluatePolicy(
            allowedSSIDs: profile.copyJobConfig.allowedWiFiSSIDs,
            disallowedSSIDs: profile.copyJobConfig.disallowedWiFiSSIDs,
            pauseOnMetered: unmeteredOnly
        )
        if !eval.isPermitted {
            let msg = eval.reason ?? "Network policy constraint not satisfied."
            logger.warning("\(msg)")
            LogManager.shared.log("Replication postponed for profile [\(profile.id)]: \(msg)", level: .warning, category: "Replication")
            throw NSError(domain: "OtterKeep.Replication", code: 4001, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        // 2. Resolve target snapshot
        let snapshot: SnapshotRecord
        if let id = targetSnapshotId {
            let snaps = try await database.listSnapshots()
            guard let found = snaps.first(where: { $0.id == id }) else {
                throw NSError(domain: "OtterKeep.Replication", code: 4004, userInfo: [NSLocalizedDescriptionKey: "Snapshot not found: \(id)"])
            }
            snapshot = found
        } else {
            guard let latest = try await database.fetchLatestSnapshot() else {
                throw NSError(domain: "OtterKeep.Replication", code: 4004, userInfo: [NSLocalizedDescriptionKey: "No snapshots available for replication"])
            }
            snapshot = latest
        }

        let snapshotRoot = profile.destinationURL.appendingPathComponent(snapshot.snapshotPath).appendingPathComponent("root")
        let fileRecords = try await database.listFiles(forSnapshotId: snapshot.id)
        let filesToSync = fileRecords.filter { !$0.isDirectory }

        var totalReplicatedFiles = 0
        var totalReplicatedBytes: Int64 = 0
        var totalSkippedFiles = 0
        var successfulDests = 0

        let throttler = BandwidthThrottler(maxBytesPerSecond: profile.copyJobConfig.maxBandwidthBytesPerSec)

        for dest in destinations {
            try Task.checkCancellation()

            var state = ReplicationProgressState(
                isRunning: true,
                currentDestinationName: dest.name,
                totalFiles: filesToSync.count,
                processedFiles: 0,
                totalBytes: snapshot.totalBytes,
                replicatedBytes: 0,
                statusMessage: "Starting replication to \(dest.name)..."
            )
            onProgress?(state)

            let result: DestinationSyncResult
            switch dest.type {
            case .s3(let s3Config):
                result = try await replicateS3(
                    dest: dest,
                    s3Config: s3Config,
                    snapshot: snapshot,
                    snapshotRoot: snapshotRoot,
                    filesToSync: filesToSync,
                    profile: profile,
                    throttler: throttler,
                    state: &state
                )
            case .backblazeB2(let b2Config):
                result = try await replicateS3(
                    dest: dest,
                    s3Config: b2Config.toS3Configuration(),
                    snapshot: snapshot,
                    snapshotRoot: snapshotRoot,
                    filesToSync: filesToSync,
                    profile: profile,
                    throttler: throttler,
                    state: &state
                )
            case .smb(let smbConfig):
                result = try await replicateSMB(
                    dest: dest,
                    smbConfig: smbConfig,
                    snapshot: snapshot,
                    snapshotRoot: snapshotRoot,
                    filesToSync: filesToSync,
                    profile: profile,
                    throttler: throttler,
                    state: &state
                )
            case .webdav(let webdavConfig):
                result = try await replicateWebDAV(
                    dest: dest,
                    webdavConfig: webdavConfig,
                    snapshot: snapshot,
                    snapshotRoot: snapshotRoot,
                    filesToSync: filesToSync,
                    profile: profile,
                    throttler: throttler,
                    state: &state
                )
            case .sftp(let sftpConfig):
                result = try await replicateSFTP(
                    dest: dest,
                    sftpConfig: sftpConfig,
                    snapshot: snapshot,
                    snapshotRoot: snapshotRoot,
                    filesToSync: filesToSync,
                    profile: profile,
                    throttler: throttler,
                    state: &state
                )
            }

            totalReplicatedFiles += result.replicatedFiles
            totalReplicatedBytes += result.replicatedBytes
            totalSkippedFiles += result.skippedFiles
            if result.isSuccess {
                successfulDests += 1
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let summary = ReplicationJobSummary(
            snapshotId: snapshot.id,
            profileId: profile.id,
            totalDestinations: destinations.count,
            successfulDestinations: successfulDests,
            replicatedFiles: totalReplicatedFiles,
            replicatedBytes: totalReplicatedBytes,
            skippedFiles: totalSkippedFiles,
            durationSeconds: duration,
            status: successfulDests == destinations.count ? "completed" : "completed_with_errors"
        )

        onProgress?(ReplicationProgressState(
            isRunning: false,
            currentDestinationName: "",
            totalFiles: filesToSync.count,
            processedFiles: filesToSync.count,
            totalBytes: snapshot.totalBytes,
            replicatedBytes: totalReplicatedBytes,
            statusMessage: "3-2-1 Replication finished."
        ))

        LogManager.shared.log("3-2-1 Replication Copy Job finished for profile [\(profile.id)]: \(successfulDests)/\(destinations.count) destinations synced (\(totalReplicatedFiles) files, \(totalReplicatedBytes / 1024 / 1024) MB) in \(String(format: "%.2f", duration))s", level: .info, category: "Replication")

        return summary
    }

}
