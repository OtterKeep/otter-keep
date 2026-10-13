import Foundation
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension OtterKeepCLI {
    static func handleScrub(_ args: [String]) async {
        let profileName = getOption("--profile", from: args)
        let limitStr = getOption("--limit", from: args)
        let limit = limitStr.flatMap(Int.init)

        let profile = resolveProfile(target: profileName)

        print("🔍 Starting cryptographic data scrubbing pass...")
        print("📁 Profile: \(profile.name)")
        print("🎯 Destination: \(profile.destinationURL.path(percentEncoded: false))\n")

        let scrubber = DataScrubberEngine()
        do {
            let record = try await scrubber.performScrub(backupRootURL: profile.destinationURL, limitSnapshots: limit) { progress in
                if progress.totalFiles > 0 {
                    let pct = Int((Double(progress.checkedFiles) / Double(progress.totalFiles)) * 100)
                    print("\r[Scrubbing] \(pct)% (\(progress.checkedFiles)/\(progress.totalFiles)) - \(progress.currentSnapshot)", terminator: "")
                    fflush(stdout)
                }
            }
            print("\n")
            print("✅ Scrubbing audit completed successfully:")
            print("   • Snapshots audited: \(record.checkedSnapshotsCount)")
            print("   • Files verified:    \(record.checkedFilesCount)")
            print("   • Corrupted files:   \(record.corruptedFilesCount)")
            print("   • Status:            \(record.status)")
            if record.corruptedFilesCount > 0 {
                if let details = record.detailsJson {
                    print("\n⚠️ Corrupted details:\n\(details)")
                }
                exitCLI(1)
            }
            exitCLI(0)
        } catch {
            print("\n❌ Scrubbing failed: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Diff & Side-by-Side Comparison


    static func handleLock(_ args: [String]) async {
        guard let snapId = getOption("--snapshot", from: args) else {
            print("❌ Missing required parameter: --snapshot <id>")
            exitCLI(1)
        }
        let profileName = getOption("--profile", from: args)
        let days = getOption("--days", from: args).flatMap(Int.init) ?? 30

        let profile = resolveProfile(target: profileName)

        do {
            let lockedUntil = Date().addingTimeInterval(Double(days) * 86400)
            try await SnapshotCatalogService.shared.updateSnapshotLock(
                id: snapId,
                lockedUntil: lockedUntil,
                in: profile
            )

            let df = ISO8601DateFormatter()
            print("🔒 Snapshot '\(snapId)' locked with WORM immutability.")
            print("   Protected until: \(df.string(from: lockedUntil)) (\(days) days)")
            exitCLI(0)
        } catch {
            print("❌ Failed to lock snapshot: \(error.localizedDescription)")
            exitCLI(1)
        }
    }


    static func handleUnlock(_ args: [String]) async {
        guard let snapId = getOption("--snapshot", from: args) else {
            print("❌ Missing required parameter: --snapshot <id>")
            exitCLI(1)
        }
        let profileName = getOption("--profile", from: args)
        let profile = resolveProfile(target: profileName)

        do {
            try await SnapshotCatalogService.shared.updateSnapshotLock(
                id: snapId,
                lockedUntil: nil,
                in: profile
            )

            print("🔓 Snapshot '\(snapId)' unlocked.")
            exitCLI(0)
        } catch {
            print("❌ Failed to unlock snapshot: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Photos Backup

    /// Manages headless Apple Photos library backups, status inspection, and snapshot history.
    /// - Parameter args: Command-line arguments passed to the photos subcommand.

    static func handlePrune(_ args: [String]) async {
        let profileName = getOption("--profile", from: args)
        let keepStr = getOption("--keep", from: args)

        let profile = resolveProfile(target: profileName)

        let keepCount = keepStr.flatMap(Int.init)
        var policy = profile.pruningPolicy
        if let maxKeep = keepCount {
            policy.isAutoPruningEnabled = true
            policy.maxSnapshotsToKeep = maxKeep
        }
        let retainLabel = keepCount ?? policy.maxSnapshotsToKeep ?? 5
        print("🧹 Pruning snapshots for profile '\(profile.name)' (Retaining latest \(retainLabel))...")

        let storage = DefaultFileSystemProvider()
        let database = DatabaseEngine()
        let dbPath = profile.manifestDatabasePath
        try? await database.open(at: dbPath)
        let retention = RetentionManager(storage: storage, database: database)

        do {
            let prunedIds = try await retention.applyRetentionPolicy(destinationURL: profile.destinationURL, policy: policy)
            await database.close()
            if prunedIds.isEmpty {
                print("ℹ️ No snapshots required pruning. All snapshots within retention limit.")
            } else {
                print("✅ Retention pruning completed successfully:")
                print("   • Pruned snapshots: \(prunedIds.count)")
                for id in prunedIds {
                    print("     - \(id)")
                }
                NotificationDeliveryService.shared.notifyPruningCompleted(profileName: profile.name, prunedCount: prunedIds.count)
            }
            exitCLI(0)
        } catch {
            await database.close()
            print("❌ Pruning failed: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Daemon & LaunchAgent

    /// Manages macOS launchd background agent registration and status.
    /// - Parameter args: Arguments passed to daemon subcommand.

}
