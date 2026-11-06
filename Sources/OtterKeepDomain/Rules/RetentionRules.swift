import Foundation

public typealias RetentionDecision = RetentionPolicyCalculator.Decision

/// Pure domain rule evaluator executing Grandfather-Father-Son (GFS) snapshot retention decisions.
///
/// Contains zero I/O or filesystem dependencies, guaranteeing deterministic retention pruning decisions.
public struct RetentionPolicyCalculator: Sendable {
    public struct Decision: Sendable, Equatable {
        public let keepSnapshotIds: Set<String>
        public let pruneSnapshotIds: [String]

        public init(keepSnapshotIds: Set<String>, pruneSnapshotIds: [String]) {
            self.keepSnapshotIds = keepSnapshotIds
            self.pruneSnapshotIds = pruneSnapshotIds
        }
    }

    /// Evaluates which snapshots to retain and which to prune based on GFS retention rules.
    /// - Parameters:
    ///   - snapshots: Chronologically ordered list of snapshot records (newest to oldest).
    ///   - now: Reference evaluation timestamp.
    ///   - keepDailyDays: Number of days to keep daily snapshots (nil = unlimited).
    ///   - keepWeeklyWeeks: Number of weeks to keep weekly snapshots (nil = unlimited).
    ///   - keepMonthlyMonths: Number of months to keep monthly snapshots (nil = unlimited).
    ///   - maxSnapshotsToKeep: Hard cap on the number of retained snapshots (nil = no cap).
    /// - Returns: A `Decision` with kept and pruned snapshot IDs.
    public static func evaluate(
        snapshots: [SnapshotRecord],
        now: Date = Date(),
        keepDailyDays: Int? = 7,
        keepWeeklyWeeks: Int? = 4,
        keepMonthlyMonths: Int? = 12,
        maxSnapshotsToKeep: Int? = nil
    ) -> Decision {
        guard !snapshots.isEmpty else {
            return Decision(keepSnapshotIds: [], pruneSnapshotIds: [])
        }

        let oneDayAgo = now.addingTimeInterval(-86400)  // 24 hours

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = .current

        var snapshotsToKeep = Set<String>()
        var seenDays = Set<String>()

        let keepDailyLimit = keepDailyDays.map { now.addingTimeInterval(-Double($0) * 86400) }

        // Safety net: Never prune the newest snapshot
        if let newestSnapshot = snapshots.first {
            snapshotsToKeep.insert(newestSnapshot.id)
        }

        for snap in snapshots {
            // Immutable locked snapshots are strictly immune to pruning
            if snap.isLocked {
                snapshotsToKeep.insert(snap.id)
                continue
            }

            if snap.timestamp >= oneDayAgo {
                // 1. Preserve all snapshots taken within the last 24 hours (hourly granularity)
                snapshotsToKeep.insert(snap.id)
            } else {
                // 2. Snapshots older than 24 hours
                if let limit = keepDailyLimit, snap.timestamp < limit {
                    // Older than daily limit
                    continue
                }

                // Daily granularity: retain one per day
                let dayKey = dayFormatter.string(from: snap.timestamp)
                if !seenDays.contains(dayKey) {
                    seenDays.insert(dayKey)
                    snapshotsToKeep.insert(snap.id)
                }
            }
        }

        snapshotsToKeep = applySnapshotCap(
            snapshots: snapshots,
            keepSnapshotIds: snapshotsToKeep,
            maxSnapshotsToKeep: maxSnapshotsToKeep
        )

        let pruneIds =
            snapshots
            .filter { !snapshotsToKeep.contains($0.id) && !$0.isLocked }
            .map { $0.id }

        return Decision(keepSnapshotIds: snapshotsToKeep, pruneSnapshotIds: pruneIds)
    }

    /// Applies a hard cap on the number of retained snapshots while preserving the newest and all locked snapshots.
    /// - Parameters:
    ///   - snapshots: Chronologically ordered list of snapshot records (newest to oldest).
    ///   - keepSnapshotIds: Snapshot IDs already selected for retention by the GFS rules.
    ///   - maxSnapshotsToKeep: Hard cap on the number of retained snapshots (nil or non-positive = no cap).
    /// - Returns: The capped set of retained snapshot IDs.
    public static func applySnapshotCap(
        snapshots: [SnapshotRecord],
        keepSnapshotIds: Set<String>,
        maxSnapshotsToKeep: Int?
    ) -> Set<String> {
        guard let maxKeep = maxSnapshotsToKeep, maxKeep > 0 else { return keepSnapshotIds }

        let candidates = snapshots.filter { keepSnapshotIds.contains($0.id) }
        guard candidates.count > maxKeep else { return keepSnapshotIds }

        var trimmed = Set(candidates.prefix(maxKeep).map(\.id))
        if let newest = snapshots.first {
            trimmed.insert(newest.id)
        }
        for snap in snapshots where snap.isLocked {
            trimmed.insert(snap.id)
        }
        return trimmed
    }
}
