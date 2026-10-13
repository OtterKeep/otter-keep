import Foundation
import os
import OtterKeepStorage
import OtterKeepDatabase

extension BackupCopyJobCoordinator {
    /// Single shared orchestration routine for one replication destination.
    ///
    /// Owns every concern that is identical across backends: the in-progress/failed/completed snapshot records,
    /// per-file `recordReplicationFile` bookkeeping, progress-state updates, skipped/failed accounting,
    /// destination-level error handling and `DestinationSyncResult` construction.
    func executeReplicationPipeline<Sink: ReplicationSink>(
        _ sink: Sink,
        state: inout ReplicationProgressState
    ) async throws -> DestinationSyncResult {
        let destId = sink.destinationIdentifier
        let snapshot = sink.context.snapshot

        _ = try await database.recordReplicationSnapshot(ReplicationSnapshotRecord(
            snapshotId: snapshot.id,
            destinationType: sink.destinationType,
            destinationIdentifier: destId,
            status: "in_progress",
            replicatedBytes: 0,
            totalBytes: snapshot.totalBytes,
            startedAt: Date()
        ))

        do {
            let session = try await sink.open()
            var totals = ReplicationTotals()

            if sink.packagesArchive {
                if let message = sink.archivePackagingStatusMessage {
                    state.statusMessage = message
                    state.currentFile = "\(snapshot.id).\(ArchivePackagingEngine.shared.defaultFormat.fileExtension)"
                    onProgress?(state)
                }
                let outcome = try await sink.replicateArchive(session: session)
                try await apply(outcome, to: &totals, state: &state)
            } else {
                for file in sink.context.filesToSync {
                    try Task.checkCancellation()
                    if sink.announcesCurrentFileBeforeReplication {
                        state.currentFile = file.relativePath
                        onProgress?(state)
                    }
                    let outcome = try await sink.replicateFile(file, session: session)
                    try await apply(outcome, to: &totals, state: &state)
                }
            }

            try await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "completed",
                replicatedBytes: totals.replicatedBytes,
                completedAt: Date()
            )

            if sink.successLogIncludesCounts {
                logger.info("Successfully replicated snapshot \(snapshot.id) to \(sink.successLogTarget, privacy: .public): \(totals.replicatedFiles) files, \(totals.replicatedBytes) bytes")
            } else {
                logger.info("Successfully replicated snapshot \(snapshot.id) to \(sink.successLogTarget, privacy: .public)")
            }

            return DestinationSyncResult(
                replicatedFiles: totals.replicatedFiles,
                replicatedBytes: totals.replicatedBytes,
                skippedFiles: totals.skippedFiles,
                isSuccess: true
            )
        } catch {
            let errMsg = error.localizedDescription
            logger.error("Failed to replicate snapshot to \(sink.logName, privacy: .public): \(errMsg)")
            try? await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "failed",
                replicatedBytes: 0,
                completedAt: Date(),
                errorMessage: errMsg
            )
            return DestinationSyncResult(
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                isSuccess: false
            )
        }
    }

    /// Folds one backend outcome into the run totals, progress state and file bookkeeping.
    private func apply(
        _ outcome: ReplicationUnitOutcome,
        to totals: inout ReplicationTotals,
        state: inout ReplicationProgressState
    ) async throws {
        if let record = outcome.fileRecord {
            try await database.recordReplicationFile(record)
        }
        totals.replicatedFiles += outcome.replicatedFiles
        totals.replicatedBytes += outcome.replicatedBytes
        totals.skippedFiles += outcome.skippedFiles
        state.processedFiles += outcome.processedFilesDelta
        state.replicatedBytes += outcome.progressBytesDelta
        if outcome.emitProgress {
            onProgress?(state)
        }
    }
}
