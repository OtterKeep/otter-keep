import Foundation
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension OtterKeepCLI {
    static func handleReplicate(_ args: [String]) async {
        let profileName = getOption("--profile", from: args)
        let snapshotId = getOption("--snapshot", from: args)

        let profile = resolveProfile(target: profileName)

        guard profile.copyJobConfig.isEnabled, !profile.copyJobConfig.destinations.filter({ $0.isEnabled }).isEmpty else {
            print("⚠️ No remote replication destinations enabled for profile '\(profile.name)'.")
            exitCLI(0)
        }

        do {
            let snaps = try await SnapshotCatalogService.shared.listSnapshots(for: profile)
            guard !snaps.isEmpty else {
                print("❌ No snapshots available to replicate in profile '\(profile.name)'.")
                exitCLI(1)
            }

            let snap: SnapshotRecord
            if let targetSnapId = snapshotId {
                guard let found = snaps.first(where: { $0.id == targetSnapId }) else {
                    print("❌ Snapshot '\(targetSnapId)' not found.")
                    exitCLI(1)
                }
                snap = found
            } else {
                snap = snaps.first!
            }

            print("🦦 Starting 3-2-1 Remote Replication Copy Job...")
            print("📁 Profile:     \(profile.name)")
            print("📸 Snapshot ID: \(snap.id) (\(snap.snapshotPath))")
            print("🎯 Remote Targets (\(profile.copyJobConfig.destinations.filter({ $0.isEnabled }).count)):")
            for dest in profile.copyJobConfig.destinations where dest.isEnabled {
                print("   • [\(dest.type.typeDisplayName)] \(dest.name)")
            }
            print()

            let db = DatabaseEngine()
            try await db.open(at: profile.manifestDatabasePath)
            do {
                let storage = DefaultFileSystemProvider()
                let coordinator = BackupCopyJobCoordinator(storage: storage, database: db)
                await coordinator.setProgressHandler { state in
                    if state.totalFiles > 0 {
                        let pct = Int((Double(state.processedFiles) / Double(state.totalFiles)) * 100)
                        let file = state.currentFile.isEmpty ? "" : " - \(state.currentFile)"
                        print("\r[\(state.currentDestinationName)] \(pct)% (\(state.processedFiles)/\(state.totalFiles))\(file)", terminator: "")
                        fflush(stdout)
                    }
                }

                let summary = try await coordinator.executeReplication(
                    profile: profile,
                    targetSnapshotId: snap.id
                )

                await db.close()

                let statusDisplay: String
                switch summary.status {
                case "completed":
                    statusDisplay = "completed"
                case "completed_with_errors":
                    statusDisplay = "completed_with_errors"
                default:
                    statusDisplay = "failed"
                }

                print("\n")
                print("✅ 3-2-1 Replication Completed:")
                print("   • Status:                  \(statusDisplay)")
                print("   • Successful Destinations: \(summary.successfulDestinations)/\(summary.totalDestinations)")
                print("   • Replicated Files:        \(summary.replicatedFiles)")
                print("   • Replicated Bytes:        \(formatBytes(summary.replicatedBytes))")
                print("   • Skipped (Deduplicated):  \(summary.skippedFiles)")
                print("   • Duration:                \(String(format: "%.2f", summary.durationSeconds)) s")
                exitCLI(0)
            } catch {
                await db.close()
                throw error
            }
        } catch {
            print("\n❌ Replication failed: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Profile

    /// Manages backup profiles (listing, creating, and deleting).
    /// - Parameter args: Command-line arguments passed to the profile subcommand.

    static func handlePhotos(_ args: [String]) async {
        let sub = args.first ?? "status"
        let store = PhotosProfileStore.shared
        let config = store.loadConfiguration()

        switch sub {
        case "status":
            print("📸 Apple Photos Backup Status\n")
            print("   • Enabled:            \(config.isEnabled)")
            print("   • Destination:        \(config.destinationURL.path(percentEncoded: false))")
            print("   • Destination Valid:  \(FileManager.default.fileExists(atPath: config.destinationURL.path(percentEncoded: false)))")
            print("   • Buffer Guard:       \(config.maxInFlightCacheBytes / 1024 / 1024) MB")
            let sched = config.schedule
            let schedStatus = sched.isEnabled ? "\(sched.frequency.rawValue)" : L10n.t(.scheduleNotScheduled)
            print("   • Schedule:           \(schedStatus)")
            if let last = sched.lastRunDate {
                print("   • Last Run:           \(ISO8601DateFormatter().string(from: last))")
            } else {
                print("   • Last Run:           \(L10n.t(.cliNeverRun))")
            }
            exitCLI(0)

        case "backup":
            print("📸 Starting Apple Photos backup...")
            print("🎯 Destination: \(config.destinationURL.path(percentEncoded: false))\n")

            let storage = DefaultFileSystemProvider()
            let database = DatabaseEngine()
            let coordinator = PhotosBackupCoordinator(storage: storage, dbEngine: database)

            do {
                let summary = try await coordinator.executeBackup(configuration: config) { progress in
                    if progress.totalAssetsCount > 0 {
                        let pct = Int(progress.progressFraction * 100)
                        let file = progress.currentAssetFilename.isEmpty ? "" : " - \(progress.currentAssetFilename)"
                        print("\r[\(progress.phaseDescription)] \(pct)% (\(progress.processedAssetsCount)/\(progress.totalAssetsCount))\(file)", terminator: "")
                        fflush(stdout)
                    }
                }
                print("\n\n✅ Apple Photos backup completed successfully:")
                print("   • New downloaded:    \(summary.newDownloadedCount) (\(formatBytes(summary.newDownloadedBytes)))")
                print("   • Cloned via CoW:    \(summary.reflinkClonedCount) (\(formatBytes(summary.reflinkClonedBytes)))")
                print("   • Errors:            \(summary.errorCount)")
                print("   • Duration:          \(String(format: "%.1f", summary.durationSeconds)) s")

                var updated = config
                updated.schedule.lastRunDate = Date()
                try? store.saveConfiguration(updated)

                NotificationDeliveryService.shared.notifyPhotosBackupCompleted(
                    copiedCount: summary.newDownloadedCount + summary.reflinkClonedCount,
                    durationSec: summary.durationSeconds
                )
                exitCLI(0)
            } catch {
                print("\n❌ Photos backup failed: \(error.localizedDescription)")
                NotificationDeliveryService.shared.notifyPhotosBackupFailed(errorMessage: error.localizedDescription)
                exitCLI(1)
            }

        case "snapshots", "list":
            let db = DatabaseEngine()
            let unifiedPath = config.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: unifiedPath) {
                do {
                    try await db.open(at: unifiedPath)
                    let snaps = try await db.listSnapshots()
                    await db.close()
                    if snaps.isEmpty {
                        print(L10n.t(.noSnapshotsAvailable))
                    } else {
                        print("📸 Photos Snapshots (\(snaps.count)):")
                        let df = ISO8601DateFormatter()
                        for s in snaps {
                            print("• [\(s.id)]  \(df.string(from: s.timestamp))  \(s.totalFiles) \(L10n.t(.assetsCountUnit))  \(formatBytes(s.totalBytes))  (\(s.snapshotPath))")
                        }
                    }
                } catch {
                    await db.close()
                    print(L10n.t(.noSnapshotsAvailable))
                }
            } else {
                print(L10n.t(.noSnapshotsAvailable))
            }
            exitCLI(0)

        default:
            print(L10n.format(.cliUnknownSubcommand, sub))
            exitCLI(1)
        }
    }

    // MARK: - Prune / Retention

    /// Prunes expired snapshots for a profile according to configured retention limits or custom keep threshold.
    /// - Parameter args: Command-line arguments.

}
