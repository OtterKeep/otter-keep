import Foundation
import os
import AppKit
import OtterKeepStorage
import OtterKeepDatabase

extension BackupSessionCoordinator {
    public func performDryRun(profile: BackupProfile, mode: BackupMode = .incremental) async throws -> DryRunSummary {
        let modeTag = mode == .full ? "[FORCED FULL BACKUP]" : "[INCREMENTAL]"
        logger.info("Starting pre-backup analysis (Dry-Run \(modeTag, privacy: .public)): '\(profile.name, privacy: .private)' (Source: \(profile.sourceURL.path, privacy: .private))")

        let destinationURL = profile.destinationURL.standardizedFileURL
        let internalDir = destinationURL.appendingPathComponent(".otterkeep")
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)

        var previousCatalog: [String: FileCatalogRecord] = [:]
        if mode == .incremental && FileManager.default.fileExists(atPath: dbPath) {
            try? await database.open(at: dbPath)
            if let latestSnapshots = try? await database.listSnapshots(),
               let previousSnapshot = latestSnapshots.first(where: { $0.status == "completed" || $0.status == "completed_with_warnings" }) {
                if let files = try? await database.listFiles(forSnapshotId: previousSnapshot.id) {
                    for f in files {
                        previousCatalog[f.relativePath] = f
                    }
                }
            }
            await database.close()
        }

        // Scan source directory respecting exclusion rules
        let scanner = FileTreeScanner(
            storage: storage,
            excludePatterns: profile.excludePatterns,
            enableIgnoreFiles: profile.enableIgnoreFiles,
            respectGitIgnore: profile.respectGitIgnore
        )
        let scanResult = try await scanner.scanDetailed(rootURL: profile.sourceURL)
        let scannedItems = scanResult.items

        // Detect differential changes
        let detector = ChangeDetector()
        let changes = detector.detectChanges(
            scannedItems: scannedItems,
            previousCatalog: previousCatalog,
            hashMode: profile.hashVerificationMode
        )

        let addedBytes = changes.added.reduce(0) { $0 + $1.metadata.size }
        let modifiedBytes = changes.modified.reduce(0) { $0 + $1.metadata.size }
        let totalScannedBytes = scannedItems.reduce(0) { $0 + $1.metadata.size }

        logger.info("Dry-Run (\(mode.rawValue)) completed: \(changes.added.count) added, \(changes.modified.count) modified, \(changes.deleted.count) deleted, \(changes.unmodified.count) unmodified. Estimated net storage: \(changes.totalChangedBytes) bytes.")

        return DryRunSummary(
            totalScannedFiles: scannedItems.count,
            totalScannedBytes: totalScannedBytes,
            addedCount: changes.added.count,
            addedBytes: addedBytes,
            modifiedCount: changes.modified.count,
            modifiedBytes: modifiedBytes,
            deletedCount: changes.deleted.count,
            unmodifiedCount: changes.unmodified.count,
            estimatedNewBytes: changes.totalChangedBytes,
            skippedCount: scanResult.skippedItems.count,
            skippedItems: scanResult.skippedItems,
            addedPaths: changes.added.map { $0.relativePath },
            modifiedPaths: changes.modified.map { $0.relativePath },
            deletedPaths: changes.deleted.map { $0.relativePath }
        )
    }


}
