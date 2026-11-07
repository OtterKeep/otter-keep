import Foundation
import SQLite3
import OtterKeepStorage
import OtterKeepDomain

/// Actor engine providing high-performance diff calculation between snapshot manifests.
public actor SnapshotDiffEngine {
    public static let shared = SnapshotDiffEngine()

    public init() {}

    /// Pure in-memory calculation of differences between two lists of file catalog records.
    public static func computeDiff(
        baseFiles: [FileCatalogRecord],
        targetFiles: [FileCatalogRecord],
        baseSnapshotId: String? = nil,
        targetSnapshotId: String = "target",
        baseTimestamp: Date? = nil,
        targetTimestamp: Date = Date()
    ) -> SnapshotDiffReport {
        var baseMap: [String: FileCatalogRecord] = [:]
        baseMap.reserveCapacity(baseFiles.count)
        for record in baseFiles {
            baseMap[record.relativePath] = record
        }

        var targetMap: [String: FileCatalogRecord] = [:]
        targetMap.reserveCapacity(targetFiles.count)
        for record in targetFiles {
            targetMap[record.relativePath] = record
        }

        var diffItems: [SnapshotDiffItem] = []

        // Evaluate target items (Added and Modified)
        for (path, targetRec) in targetMap {
            if let baseRec = baseMap[path] {
                // Check if changed
                let hasDifferentSize = baseRec.fileSize != targetRec.fileSize
                let hasDifferentHash = (targetRec.checksum != nil && baseRec.checksum != nil && targetRec.checksum != baseRec.checksum)
                let hasDifferentMtime = abs(targetRec.modificationTime.timeIntervalSince(baseRec.modificationTime)) > 0.001
                let hasDifferentSample = (targetRec.sampleHash != nil && baseRec.sampleHash != nil && targetRec.sampleHash != baseRec.sampleHash)

                let isModified = hasDifferentSize || hasDifferentHash || hasDifferentSample || (!targetRec.isDirectory && hasDifferentMtime)

                if isModified {
                    let delta = targetRec.fileSize - baseRec.fileSize
                    diffItems.append(SnapshotDiffItem(
                        relativePath: path,
                        changeType: .modified,
                        oldRecord: baseRec,
                        newRecord: targetRec,
                        sizeDelta: delta
                    ))
                }
            } else {
                // Added item
                diffItems.append(SnapshotDiffItem(
                    relativePath: path,
                    changeType: .added,
                    oldRecord: nil,
                    newRecord: targetRec,
                    sizeDelta: targetRec.fileSize
                ))
            }
        }

        // Evaluate deleted items (existed in base but not in target)
        for (path, baseRec) in baseMap {
            if targetMap[path] == nil {
                diffItems.append(SnapshotDiffItem(
                    relativePath: path,
                    changeType: .deleted,
                    oldRecord: baseRec,
                    newRecord: nil,
                    sizeDelta: -baseRec.fileSize
                ))
            }
        }

        diffItems.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

        return SnapshotDiffReport(
            baseSnapshotId: baseSnapshotId,
            targetSnapshotId: targetSnapshotId,
            baseTimestamp: baseTimestamp,
            targetTimestamp: targetTimestamp,
            items: diffItems
        )
    }

    /// Computes the visual diff between two snapshots using the given database engine.
    /// If `baseSnapshotId` is nil, the engine automatically finds the snapshot immediately preceding `targetSnapshotId`.
    public func diff(
        database: DatabaseEngine,
        targetSnapshotId: String,
        baseSnapshotId: String? = nil
    ) async throws -> SnapshotDiffReport {
        // 1. Fetch target snapshot metadata
        let allSnapshots = try await database.listSnapshots()
        guard let targetSnapshot = allSnapshots.first(where: { $0.id == targetSnapshotId }) else {
            throw DatabaseError.stepFailed("listSnapshots", "Target snapshot '\(targetSnapshotId)' not found.")
        }

        // 2. Resolve base snapshot
        let resolvedBaseSnapshot: SnapshotRecord?
        if let explicitBase = baseSnapshotId {
            resolvedBaseSnapshot = allSnapshots.first(where: { $0.id == explicitBase })
        } else {
            // Find immediately preceding snapshot chronologically
            resolvedBaseSnapshot = allSnapshots
                .filter { $0.timestamp < targetSnapshot.timestamp }
                .sorted { $0.timestamp > $1.timestamp }
                .first
        }

        // 3. Fetch catalogs for both snapshots
        let targetCatalog = try await database.listFiles(forSnapshotId: targetSnapshotId)
        let baseCatalog: [FileCatalogRecord]
        if let base = resolvedBaseSnapshot {
            baseCatalog = try await database.listFiles(forSnapshotId: base.id)
        } else {
            baseCatalog = []
        }

        // 4. Delegate to pure diff engine
        return Self.computeDiff(
            baseFiles: baseCatalog,
            targetFiles: targetCatalog,
            baseSnapshotId: resolvedBaseSnapshot?.id,
            targetSnapshotId: targetSnapshot.id,
            baseTimestamp: resolvedBaseSnapshot?.timestamp,
            targetTimestamp: targetSnapshot.timestamp
        )
    }
}
