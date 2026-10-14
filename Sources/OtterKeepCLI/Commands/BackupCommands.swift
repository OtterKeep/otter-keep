import Foundation
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension OtterKeepCLI {
    static func handleBackup(_ args: [String]) async {
        let isDryRun = args.contains("--dry-run")
        let isFull = args.contains("--full")
        let backupMode: BackupMode = isFull ? .full : .incremental
        let profileName = getOption("--profile", from: args)
        let profile = resolveProfile(target: profileName)

        let storage = DefaultFileSystemProvider()
        let database = DatabaseEngine()
        let retentionManager = RetentionManager(storage: storage, database: database)
        let coordinator = BackupSessionCoordinator(
            storage: storage,
            database: database,
            retentionManager: retentionManager,
            volumeEjector: SystemVolumeEjector()
        )

        let modeLabel = isFull ? " [\(L10n.t(.backupTypeFull).uppercased())]" : ""
        LogManager.shared.log("CLI backup initiated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)] (DryRun: \(isDryRun), Full: \(isFull), Continuous: \(args.contains("--continuous")))", level: .info, category: "CLI")

        if args.contains("--continuous") {
            let debounce = profile.executionMode.debouncingSeconds
            print("⚡️ Starting continuous real-time backup watcher for '\(profile.name)' (quiet window: \(debounce)s)...")
            print("📁 \(L10n.t(.activeProfileLabel)): \(profile.name)")
            print("📂 \(L10n.t(.sourceFolderTitle)): \(profile.sourceURL.path)")
            print("🎯 \(L10n.t(.destinationFolderTitle)): \(profile.destinationURL.path)")
            print("   Press Ctrl+C to terminate.\n")

            let watcher = FSEventWatcher(
                watchedPath: profile.sourceURL.standardizedFileURL.path(percentEncoded: false),
                excludePatterns: profile.excludePatterns,
                debouncingSeconds: debounce
            ) { _ in
                print("\n🔔 [FSEvents] Change detected! Triggering incremental backup...")
                Task {
                    do {
                        _ = try await coordinator.performBackup(profile: profile, mode: .incremental) { progress in
                            if progress.totalFiles > 0 {
                                let pct = Int((Double(progress.processedFiles) / Double(progress.totalFiles)) * 100)
                                let file = progress.currentItem.isEmpty ? "" : " - \(progress.currentItem)"
                                print("\r[\(progress.phase.localizedDescription)] \(pct)% (\(progress.processedFiles)/\(progress.totalFiles))\(file)", terminator: "")
                                fflush(stdout)
                            }
                        }
                        if let sum = await coordinator.lastSessionSummary {
                            print("\n✅ Real-time backup completed: Snapshot \(sum.snapshotId), Copied: \(sum.copiedCount), Cloned: \(sum.clonedCount)")
                        }
                    } catch {
                        print("\n❌ Backup failed: \(error.localizedDescription)")
                    }
                }
            }
            watcher.start()

            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        if isDryRun {
            print(L10n.t(.cliDryRunStarting) + modeLabel)
            print("📁 \(L10n.t(.activeProfileLabel)): \(profile.name)")
            print("📂 \(L10n.t(.sourceFolderTitle)): \(profile.sourceURL.path)")
            print("🎯 \(L10n.t(.destinationFolderTitle)): \(profile.destinationURL.path)\n")

            do {
                let summary = try await coordinator.performDryRun(profile: profile, mode: backupMode)
                LogManager.shared.log("CLI Dry-Run completed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: Scanned: \(summary.totalScannedFiles) (\(summary.totalScannedBytes) bytes), Added: \(summary.addedCount), Modified: \(summary.modifiedCount), Unmodified (CoW): \(summary.unmodifiedCount), Deleted: \(summary.deletedCount)", level: .info, category: "CLI")
                print(L10n.t(.cliDryRunFinished) + modeLabel)
                print("   • \(L10n.t(.inspectorTotalScanned)): \(summary.totalScannedFiles) (\(formatBytes(summary.totalScannedBytes)))")
                print("   • \(L10n.t(.dryRunTabAdded)):             \(summary.addedCount) (\(formatBytes(summary.addedBytes)))")
                print("   • \(L10n.t(.dryRunTabModified)):        \(summary.modifiedCount) (\(formatBytes(summary.modifiedBytes)))")
                print("   • \(L10n.t(.timelineUnmodifiedCoW)):      \(summary.unmodifiedCount)")
                print("   • \(L10n.t(.dryRunTabDeleted)):          \(summary.deletedCount)")
                exitCLI(0)
            } catch {
                LogManager.shared.log("CLI Dry-Run failed for profile '\(profile.name)': \(error.localizedDescription)", level: .error, category: "CLI")
                print(L10n.format(.cliDryRunError, error.localizedDescription))
                exitCLI(1)
            }
        } else {
            print(L10n.t(.cliBackupStarting) + modeLabel)
            print("📁 \(L10n.t(.activeProfileLabel)): \(profile.name)")
            print("📂 \(L10n.t(.sourceFolderTitle)): \(profile.sourceURL.path)")
            print("🎯 \(L10n.t(.destinationFolderTitle)): \(profile.destinationURL.path)\n")

            do {
                _ = try await coordinator.performBackup(profile: profile, mode: backupMode) { progress in
                    if progress.totalFiles > 0 {
                        let pct = Int((Double(progress.processedFiles) / Double(progress.totalFiles)) * 100)
                        let file = progress.currentItem.isEmpty ? "" : " - \(progress.currentItem)"
                        print("\r[\(progress.phase.localizedDescription)] \(pct)% (\(progress.processedFiles)/\(progress.totalFiles))\(file)", terminator: "")
                        fflush(stdout)
                    }
                }
                print("\n")

                if let sum = await coordinator.lastSessionSummary {
                    print(L10n.t(.cliBackupFinished) + modeLabel)
                    print("   • Snapshot ID:       \(sum.snapshotId)")
                    print("   • \(L10n.t(.telemetryCopied)):  \(sum.copiedCount) (\(formatBytes(sum.copiedBytes)))")
                    print("   • \(L10n.t(.telemetryCloned)):  \(sum.clonedCount)")
                    print("   • \(L10n.t(.telemetrySkipped)): \(sum.skippedCount)")
                    print("   • \(L10n.t(.telemetryErrors)):  \(sum.errorCount)")
                    print("   • \(L10n.t(.inspectorDuration)): \(String(format: "%.1f", sum.durationSeconds)) s")

                    var updated = profile
                    updated.schedule.lastRunDate = Date()
                    try? ProfileStore.shared.updateProfile(updated)
                    LogManager.shared.log("CLI backup completed successfully for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: Snapshot \(sum.snapshotId), Copied: \(sum.copiedCount), Cloned: \(sum.clonedCount)", level: .info, category: "CLI")
                }
                LogManager.shared.flush()
                exitCLI(0)
            } catch {
                LogManager.shared.log("Backup failed via CLI for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: \(error.localizedDescription)", level: .error, category: "CLI")
                LogManager.shared.flush()
                print("\n" + L10n.format(.cliBackupError, error.localizedDescription))
                exitCLI(1)
            }
        }
    }

    // MARK: - Status

    /// Displays current system status, configured profiles, paths, 3-2-1 compliance, and scheduling details.

    static func handleRestore(_ args: [String]) async {
        guard let snapId = getOption("--snapshot", from: args),
              let filePath = getOption("--file", from: args),
              let target = getOption("--target", from: args) else {
            print("\(L10n.t(.cliMissingParams)) --snapshot <id> --file <rel_path> --target <dest_dir>")
            exitCLI(1)
        }

        let profileName = getOption("--profile", from: args)
        let profile = resolveProfile(target: profileName)

        let db = DatabaseEngine()
        let storage = DefaultFileSystemProvider()
        let engine = RestoreEngine(storage: storage, database: db)

        do {
            try await db.open(at: profile.manifestDatabasePath)
            let snaps = try await db.listSnapshots()
            guard let snap = snaps.first(where: { $0.id == snapId }) else {
                await db.close()
                print("❌ Snapshot not found: '\(snapId)'")
                exitCLI(1)
            }

            let destURL = try await engine.restore(
                snapshotPath: snap.snapshotPath,
                backupRootURL: profile.destinationURL,
                relativePath: filePath,
                targetDirectoryURL: URL(fileURLWithPath: target),
                collisionResolution: .overwrite
            )
            await db.close()
            print(L10n.format(.restoreSuccessMessage, destURL.path))
            exitCLI(0)
        } catch {
            await db.close()
            print("❌ \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    /// Restores all files and directory structure of an entire snapshot to a target directory.
    /// - Parameter args: Command-line arguments passed to the restore-snapshot subcommand.

    static func handleRestoreSnapshot(_ args: [String]) async {
        guard let snapId = getOption("--snapshot", from: args),
              let target = getOption("--target", from: args) else {
            print("\(L10n.t(.cliMissingParams)) --snapshot <id> --target <dest_dir> [--profile <name>] [--collision overwrite|keepBoth|skip]")
            exitCLI(1)
        }

        let collisionModeStr = getOption("--collision", from: args)?.lowercased() ?? "keepboth"
        let collision: CollisionResolution
        switch collisionModeStr {
        case "overwrite": collision = .overwrite
        case "skip": collision = .skip
        default: collision = .keepBoth
        }

        let profileName = getOption("--profile", from: args)
        let profile = resolveProfile(target: profileName)

        let db = DatabaseEngine()
        let storage = DefaultFileSystemProvider()
        let engine = RestoreEngine(storage: storage, database: db)

        do {
            try await db.open(at: profile.manifestDatabasePath)
            let snaps = try await db.listSnapshots()
            guard let snap = snaps.first(where: { $0.id == snapId || $0.snapshotPath == snapId }) else {
                await db.close()
                print("❌ Snapshot not found: '\(snapId)'")
                exitCLI(1)
            }

            print("🔄 Restoring entire snapshot '\(snap.snapshotPath)' (\(snap.totalFiles) files) to '\(target)'...")

            let summary = try await engine.restoreSnapshot(
                snapshotPath: snap.snapshotPath,
                backupRootURL: profile.destinationURL,
                targetDirectoryURL: URL(fileURLWithPath: target),
                collisionResolution: collision,
                progress: { prog in
                    if prog.phase == .restoring && !prog.currentItem.isEmpty {
                        print("  [\(prog.processedFiles)/\(prog.totalFiles)] \(prog.currentItem)")
                    }
                }
            )
            await db.close()

            print("✅ \(L10n.format(.restoreEntireSnapshotSuccessFormat, snap.snapshotPath, Int64(summary.restoredFiles), target))")
            print("⏱️ Duration: \(String(format: "%.2f", summary.durationSeconds))s, Restored: \(ByteCountFormatter.string(fromByteCount: summary.restoredBytes, countStyle: .file))")
            exitCLI(0)
        } catch {
            await db.close()
            print("❌ \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - File History

    /// Handles inspecting version history for a file or requesting the GUI to open version history.
    /// - Parameter args: Arguments passed to file-history.

    static func handleFileHistory(_ args: [String]) async {
        guard let filePath = args.first(where: { !$0.hasPrefix("-") }) else {
            print("❌ Missing required file path. Usage: otterkeep file-history <path> [--gui]")
            exitCLI(1)
        }

        let isGui = args.contains("--gui")
        let fileURL = URL(fileURLWithPath: filePath).standardizedFileURL
        let fullPath = fileURL.path(percentEncoded: false)

        if isGui {
            let delivered = SingleInstanceManager.shared.sendMessageToRunningInstance(
                SingleInstanceMessage(action: .openVersionHistory, filePath: fullPath)
            )
            if delivered {
                print("✅ Opened version history for '\(fullPath)' in active OtterKeep GUI instance.")
                exitCLI(0)
            } else {
                print("ℹ️ OtterKeep GUI is not currently running. Launching GUI...")
                let proc = Process()
                var components = URLComponents()
                components.scheme = "otterkeep"
                components.host = "restore-versions"
                components.queryItems = [URLQueryItem(name: "path", value: fullPath)]
                if let url = components.url {
                    proc.arguments = [url.absoluteString]
                    try? proc.run()
                }
                exitCLI(0)
            }
        }

        // CLI inspection mode
        let profiles = ProfileStore.shared.loadProfiles()
        guard let matchingProfile = profiles.first(where: { $0.containsPath(fullPath) }) else {
            print(L10n.t(.fileNotUnderAnyProfile))
            exitCLI(1)
        }

        guard let relPath = matchingProfile.relativePath(for: fullPath), !relPath.isEmpty else {
            print("❌ Cannot inspect version history of the root source directory.")
            exitCLI(1)
        }

        do {
            let versions = try await SnapshotCatalogService.shared.listFileVersions(relativePath: relPath, in: matchingProfile)
            if versions.isEmpty {
                print(L10n.t(.noVersionsFoundForFile))
                exitCLI(0)
            }

            print("🦦 OtterKeep: \(versions.count) version(s) found for '\(relPath)' in profile '\(matchingProfile.name)':")
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .medium

            for (idx, item) in versions.enumerated() {
                let snap = item.snapshot
                let file = item.file
                let sizeStr = formatBytes(file.fileSize)
                let dateStr = df.string(from: snap.timestamp)
                let checksumStr = file.checksum.map { String($0.prefix(12)) + "..." } ?? "none"
                print("  [\(idx + 1)] Snapshot: \(snap.snapshotPath) (\(dateStr)) | Size: \(sizeStr) | SHA-256: \(checksumStr)")
            }

            print("\n💡 Tip: Run 'otterkeep file-history \"\(filePath)\" --gui' to inspect or restore in GUI.")
            exitCLI(0)
        } catch {
            print("❌ Failed to query version history: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    /// Prints or manages persistent system log entries and debug .log files.
    /// - Parameter args: Command-line arguments passed to the logs subcommand.

    static func handleDiff(_ args: [String]) async {
        let profileName = getOption("--profile", from: args)
        let targetId = getOption("--target", from: args)
        let baseId = getOption("--base", from: args)
        let fileRel = getOption("--file", from: args)
        let sideBySide = args.contains("--side-by-side")

        let profile = resolveProfile(target: profileName)

        do {
            let snaps = try await SnapshotCatalogService.shared.listSnapshots(for: profile)
            guard !snaps.isEmpty else {
                print(L10n.t(.noSnapshotsAvailable))
                exitCLI(1)
            }

            let effectiveTargetId = targetId ?? snaps[0].id
            let effectiveBaseId = baseId ?? (snaps.count > 1 ? snaps[1].id : nil)

            if let filePath = fileRel {
                guard let bId = effectiveBaseId,
                      let snapBase = snaps.first(where: { $0.id == bId }),
                      let snapTarget = snaps.first(where: { $0.id == effectiveTargetId }) else {
                    print("❌ Requires at least two snapshots to compare file content.")
                    exitCLI(1)
                }

                let urlA = profile.destinationURL.appendingPathComponent(snapBase.snapshotPath).appendingPathComponent("root").appendingPathComponent(filePath)
                let urlB = profile.destinationURL.appendingPathComponent(snapTarget.snapshotPath).appendingPathComponent("root").appendingPathComponent(filePath)

                let diffResult = try SnapshotCatalogService.shared.diffFiles(leftURL: urlA, rightURL: urlB, relativePath: filePath)
                print("📄 File comparison: '\(filePath)'")
                print("   Base:   [\(snapBase.id)] (\(snapBase.snapshotPath))")
                print("   Target: [\(snapTarget.id)] (\(snapTarget.snapshotPath))\n")

                if diffResult.isBinary {
                    print("⚠️ Binary file detected: inline text diff is not available.")
                    print("   Base size:   \(diffResult.leftSize) bytes")
                    print("   Target size: \(diffResult.rightSize) bytes")
                    exitCLI(0)
                }

                if diffResult.addedLinesCount == 0 && diffResult.deletedLinesCount == 0 && diffResult.modifiedLinesCount == 0 {
                    print("✅ Files are identical.")
                    exitCLI(0)
                }

                print("Changes: +\(diffResult.addedLinesCount) lines, -\(diffResult.deletedLinesCount) lines\n")

                if sideBySide {
                    print("┌─── BASE ──────────────────────────────┬─── TARGET ────────────────────────────┐")
                    for row in diffResult.rows {
                        let leftNum = row.leftLineNumber.map { String(format: "%3d", $0) } ?? "   "
                        let leftContent = (row.leftText ?? "").prefix(34).padding(toLength: 34, withPad: " ", startingAt: 0)
                        let rightNum = row.rightLineNumber.map { String(format: "%3d", $0) } ?? "   "
                        let rightContent = (row.rightText ?? "").prefix(34).padding(toLength: 34, withPad: " ", startingAt: 0)
                        let sep: String
                        switch row.type {
                        case .added: sep = "│ + "
                        case .deleted: sep = "│ - "
                        case .modified: sep = "│ ~ "
                        case .unchanged: sep = "│   "
                        }
                        print("│ \(leftNum) \(leftContent) \(sep)\(rightNum) \(rightContent) │")
                    }
                    print("└───────────────────────────────────────┴───────────────────────────────────────┘")
                } else {
                    for row in diffResult.rows {
                        switch row.type {
                        case .added:
                            print("+ [\(row.rightLineNumber ?? 0)] \(row.rightText ?? "")")
                        case .deleted:
                            print("- [\(row.leftLineNumber ?? 0)] \(row.leftText ?? "")")
                        case .modified:
                            print("~ [\(row.leftLineNumber ?? 0) → \(row.rightLineNumber ?? 0)] \(row.rightText ?? "")")
                        case .unchanged:
                            break
                        }
                    }
                }
            } else {
                let report = try await SnapshotCatalogService.shared.diffSnapshots(
                    targetSnapshotId: effectiveTargetId,
                    baseSnapshotId: effectiveBaseId,
                    in: profile
                )
                print("📊 Snapshot Diff Report:")
                print("   Base:   \(report.baseSnapshotId ?? "Initial State")")
                print("   Target: \(report.targetSnapshotId)\n")
                print("   • Added:     \(report.addedCount) files")
                print("   • Modified:  \(report.modifiedCount) files")
                print("   • Deleted:   \(report.deletedCount) files")
                print("   • Net size:  \(formatBytes(report.netBytesDelta))\n")

                for item in report.items where item.changeType != .unchanged {
                    let symbol = item.changeType == .added ? "+" : (item.changeType == .deleted ? "-" : "~")
                    print("  \(symbol) \(item.relativePath)")
                }
            }
            exitCLI(0)
        } catch {
            print("❌ Diff failed: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - WORM Immutability Locking


}
