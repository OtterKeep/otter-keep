import Foundation
import OtterKeepStorage
import OtterKeepDatabase

/// Backend-agnostic inputs shared by every replication sink for a single destination run.
struct ReplicationContext: Sendable {
    let destination: RemoteDestination
    let profile: BackupProfile
    let snapshot: SnapshotRecord
    let snapshotRoot: URL
    let filesToSync: [FileCatalogRecord]
    let throttler: BandwidthThrottler
    let database: DatabaseEngine
}

/// Accumulated per-destination counters of one replication run.
struct ReplicationTotals {
    var replicatedFiles = 0
    var replicatedBytes: Int64 = 0
    var skippedFiles = 0
}

/// Bookkeeping the shared pipeline applies after one backend-specific unit of work (a file or an archive).
struct ReplicationUnitOutcome: Sendable {
    var replicatedFiles = 0
    var replicatedBytes: Int64 = 0
    var skippedFiles = 0
    /// Applied to `ReplicationProgressState.processedFiles`.
    var processedFilesDelta = 0
    /// Applied to `ReplicationProgressState.replicatedBytes`.
    var progressBytesDelta: Int64 = 0
    /// Whether a progress callback is emitted after the deltas are applied.
    var emitProgress = false
    /// Optional replication file record the pipeline persists via `recordReplicationFile`.
    var fileRecord: ReplicationFileRecord?

    /// A unit of work without observable effect (e.g. a missing local source file).
    static let ignored = ReplicationUnitOutcome()

    /// A transferred file: counts as replicated and advances progress by the catalogued file size.
    static func replicatedFile(bytes: Int64, record: ReplicationFileRecord? = nil) -> ReplicationUnitOutcome {
        ReplicationUnitOutcome(
            replicatedFiles: 1,
            replicatedBytes: bytes,
            processedFilesDelta: 1,
            progressBytesDelta: bytes,
            emitProgress: true,
            fileRecord: record
        )
    }

    /// An already-synced file reused without transfer.
    static func reusedFile(record: ReplicationFileRecord) -> ReplicationUnitOutcome {
        ReplicationUnitOutcome(
            skippedFiles: 1,
            processedFilesDelta: 1,
            emitProgress: true,
            fileRecord: record
        )
    }

    /// A file skipped in place on a mounted share, which still advances the progress byte counter.
    static func skippedFile(bytes: Int64) -> ReplicationUnitOutcome {
        ReplicationUnitOutcome(
            skippedFiles: 1,
            processedFilesDelta: 1,
            progressBytesDelta: bytes,
            emitProgress: true
        )
    }
}

/// Narrow adapter describing only the parts of a replication destination that differ per backend:
/// how the store is created/opened and how a single file or packaged archive is pushed to it.
///
/// Everything else (snapshot/file bookkeeping, progress reporting, skip accounting, destination-level
/// error handling and `DestinationSyncResult` construction) lives in `BackupCopyJobCoordinator.executeReplicationPipeline`.
protocol ReplicationSink: Sendable {
    /// Opaque per-run handle holding the opened backend store.
    associatedtype Session: Sendable

    /// Shared run inputs.
    var context: ReplicationContext { get }

    /// Identifier stored in `ReplicationSnapshotRecord`/`ReplicationFileRecord`.
    var destinationIdentifier: String { get }
    /// Destination type tag stored in `ReplicationSnapshotRecord.destinationType`.
    var destinationType: String { get }
    /// Backend label used in destination failure log lines.
    var logName: String { get }
    /// Whether this backend is able to replicate a snapshot as a single packaged archive.
    var supportsArchivePackaging: Bool { get }

    /// Creates and opens the destination store. Failures must surface so the pipeline records them.
    func open() async throws -> Session
    /// Uploads/verifies a single catalogued file.
    func replicateFile(_ file: FileCatalogRecord, session: Session) async throws -> ReplicationUnitOutcome
}

extension ReplicationSink {
    var supportsArchivePackaging: Bool { false }

    /// Whether this run packages the snapshot as one archive instead of replicating files individually.
    var packagesArchive: Bool {
        supportsArchivePackaging
            && (context.destination.archivePackagingEnabled || context.profile.copyJobConfig.archivePackagingEnabled)
    }

    /// Status message announced before archive packaging; `nil` keeps the backend silent.
    var archivePackagingStatusMessage: String? { nil }

    /// Whether the per-file loop announces `currentFile` and emits progress before replicating each file.
    var announcesCurrentFileBeforeReplication: Bool { false }

    /// Backend label used in destination success log lines (defaults to `logName`).
    var successLogTarget: String { logName }

    /// Whether the success log line includes the replicated file/byte counters.
    var successLogIncludesCounts: Bool { true }

    /// Packages and uploads the whole snapshot as one archive. Only called when `packagesArchive` is true.
    func replicateArchive(session: Session) async throws -> ReplicationUnitOutcome {
        .ignored
    }
}
