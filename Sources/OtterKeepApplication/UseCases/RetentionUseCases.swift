import Foundation
import OtterKeepDomain

/// Interactor / Use Case for applying Grandfather-Father-Son (GFS) retention pruning.
public struct ApplyRetentionPruningUseCase: Sendable {
    private let snapshotRepository: SnapshotRepositoryProtocol
    private let fileSystem: FileSystemPort

    public init(snapshotRepository: SnapshotRepositoryProtocol, fileSystem: FileSystemPort) {
        self.snapshotRepository = snapshotRepository
        self.fileSystem = fileSystem
    }

    /// Evaluates retention rules, deletes pruned directories, and updates the catalog.
    /// - Parameters:
    ///   - destinationRootURL: Root backup destination directory.
    ///   - keepDailyDays: Number of daily snapshots to preserve.
    ///   - keepWeeklyWeeks: Number of weekly snapshots to preserve.
    ///   - keepMonthlyMonths: Number of monthly snapshots to preserve.
    /// - Returns: Array of pruned snapshot IDs.
    public func execute(
        destinationRootURL: URL,
        keepDailyDays: Int? = 7,
        keepWeeklyWeeks: Int? = 4,
        keepMonthlyMonths: Int? = 12
    ) async throws -> [String] {
        let snapshots = try await snapshotRepository.listSnapshots()
        guard !snapshots.isEmpty else { return [] }

        let decision = RetentionPolicyCalculator.evaluate(
            snapshots: snapshots,
            now: Date(),
            keepDailyDays: keepDailyDays,
            keepWeeklyWeeks: keepWeeklyWeeks,
            keepMonthlyMonths: keepMonthlyMonths
        )

        var successfullyPruned: [String] = []

        for pruneId in decision.pruneSnapshotIds {
            guard let snap = snapshots.first(where: { $0.id == pruneId }) else { continue }
            let snapDirURL = destinationRootURL.appendingPathComponent(snap.snapshotPath)

            // Remove immutability flag if set before deletion
            try? fileSystem.setImmutable(at: snapDirURL, immutable: false, recursive: true)

            // Atomic 2-step deletion via trash staging
            let stagingTrashURL = destinationRootURL.appendingPathComponent(".trash_\(UUID().uuidString)")
            do {
                if fileSystem.fileExists(at: snapDirURL) {
                    try fileSystem.move(from: snapDirURL, to: stagingTrashURL)
                    try fileSystem.remove(at: stagingTrashURL)
                }
                try await snapshotRepository.deleteSnapshot(id: pruneId)
                successfullyPruned.append(pruneId)
            } catch {
                // If deletion fails, keep record in catalog to avoid orphan entries
                continue
            }
        }

        return successfullyPruned
    }
}
