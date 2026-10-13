import Foundation
import Observation
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

/// Per-profile runtime state for parallel background backups.
///
/// Owns the task registry, live progress telemetry, last-session summaries and the snapshot caches
/// that keep the sidebar status stable while the user switches between profiles. `AppState` exposes
/// this state through forwarding accessors so views keep their existing call sites.
@MainActor
@Observable
public final class BackupRuntimeStore: Sendable {
    /// Active background backup tasks keyed by profile UUID.
    var activeBackupTasks: [UUID: Task<Void, Never>] = [:]

    /// Live telemetry progress states keyed by profile UUID.
    public internal(set) var progressStates: [UUID: BackupProgressState] = [:]

    /// Last session summaries keyed by profile UUID.
    public internal(set) var lastSummaries: [UUID: BackupSessionSummary] = [:]

    /// Latest snapshot records cached per profile UUID to preserve status across profile switching.
    public internal(set) var latestSnapshots: [UUID: SnapshotRecord] = [:]

    /// Total snapshot counts cached per profile UUID.
    public internal(set) var snapshotCounts: [UUID: Int] = [:]

    /// Initializes an empty runtime store.
    public init() {}

    /// Indicates whether a backup operation is currently executing for any profile.
    public var isRunning: Bool {
        !activeBackupTasks.isEmpty
    }

    /// Checks if a specific profile is currently backing up.
    public func isRunning(for profileId: UUID) -> Bool {
        activeBackupTasks[profileId] != nil
    }

    /// Retrieves the live progress state for a specific profile (or idle if not running).
    public func progressState(for profileId: UUID) -> BackupProgressState {
        progressStates[profileId] ?? BackupProgressState(phase: .idle)
    }
}
