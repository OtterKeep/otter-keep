import Foundation
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension OtterKeepCLI {
    static func handleStatus() async {
        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        LogManager.shared.log("CLI status queried. Total profiles: \(profiles.count)", level: .info, category: "CLI")

        print("\(L10n.t(.cliSystemStatus))\n")
        print(L10n.format(.cliProfilesCountFormat, profiles.count))

        for (idx, p) in profiles.enumerated() {
            print("\n[\(idx + 1)] \(L10n.t(.activeProfileLabel)): \(p.name) (UUID: \(p.id))")
            print("    \(L10n.t(.sourceFolderTitle)):      \(p.sourceURL.path)")
            print("    \(L10n.t(.destinationFolderTitle)): \(p.destinationURL.path)")
            print("    \(L10n.t(.excludeRulesTitle)):   \(p.excludePatterns.joined(separator: ", "))")
            let sched = p.schedule
            let schedStatus = sched.isEnabled ? "\(L10n.t(.scheduleEnableToggle)) (\(sched.frequency.rawValue))" : L10n.t(.scheduleNotScheduled)
            print("    \(L10n.t(.scheduleCardTitle)):    \(schedStatus)")
            if let last = sched.lastRunDate {
                print(L10n.format(.cliLastRunFormat, ISO8601DateFormatter().string(from: last)))
            } else {
                print(L10n.t(.cliNeverRun))
            }
            if p.pruningPolicy.isAutoPruningEnabled {
                print("    \(L10n.t(.autoPruningToggleTitle)): \(L10n.format(.autoPruningRetainFormat, p.pruningPolicy.maxSnapshotsToKeep ?? 5))")
            }

            // 3-2-1 Compliance Evaluation & Remote Targets
            let report = ComplianceEvaluator.evaluate(profile: p)
            let complianceTag: String
            switch report.status {
            case .compliant:
                complianceTag = "✅ \(L10n.t(.rule321StatusCompliant))"
            case .partial:
                complianceTag = "⚠️ \(L10n.t(.rule321StatusPartial))"
            case .localOnly:
                complianceTag = "⚠️ \(L10n.t(.rule321StatusLocalOnly))"
            }

            print("    🛡️ \(L10n.t(.rule321Title)): \(complianceTag)")
            print("       • \(L10n.format(.rule321CopiesFormat, report.copiesCount, report.activeRemoteDestinationsCount)) (\(p.sourceURL.lastPathComponent) + \(p.destinationURL.lastPathComponent) + \(report.activeRemoteDestinationsCount))")
            let mediaTypesList = report.mediaTypeIdentifiers.sorted().joined(separator: ", ")
            print("       • \(L10n.format(.rule321MediaTypesFormat, report.mediaTypesCount, mediaTypesList))")
            let offsiteTag = report.hasOffsite ? L10n.t(.commonYes) : L10n.t(.commonNo)
            print("       • \(L10n.format(.rule321OffsiteFormat, offsiteTag))")

            if p.copyJobConfig.isEnabled && !p.copyJobConfig.destinations.isEmpty {
                print("    🌐 Távoli célok (Backup Copy Job) [\(p.copyJobConfig.trigger.localizedTitle)]:")
                for dest in p.copyJobConfig.destinations {
                    let encTag = dest.isClientEncryptionEnabled ? " [🔒 Titkosított (AES-GCM)]" : ""
                    let statusTag = dest.isEnabled ? "Aktív" : "Kikapcsolva"
                    print("       • [\(dest.type.typeDisplayName)] \(dest.name) (\(statusTag))\(encTag)")
                }
            }
        }
        exitCLI(0)
    }

    // MARK: - Replicate

    /// Manually triggers 3-2-1 secondary replication (Backup Copy Job) for a profile.
    /// - Parameter args: Arguments passed to replicate subcommand.

    static func handleProfile(_ args: [String]) async {
        guard let sub = args.first else {
            await handleStatus()
            return
        }

        let store = ProfileStore.shared

        switch sub {
        case "list":
            let profiles = store.loadProfiles()
            print("\(L10n.t(.profilesMenuTitle)) (\(profiles.count)):")
            for p in profiles {
                print("• \(p.name) [ID: \(p.id)] -> \(p.sourceURL.path) ==> \(p.destinationURL.path)")
            }
        case "create":
            guard let name = getOption("--name", from: args),
                  let src = getOption("--source", from: args),
                  let dst = getOption("--destination", from: args) else {
                print("\(L10n.t(.cliMissingParams)) Required: --name <name> --source <path> --destination <path>")
                exitCLI(1)
            }
            let newP = BackupProfile(
                name: name,
                sourceURL: URL(fileURLWithPath: src),
                destinationURL: URL(fileURLWithPath: dst)
            )
            do {
                try store.updateProfile(newP)
                print(L10n.format(.cliProfileCreated, name))
            } catch {
                print(L10n.format(.cliProfileSaveError, error.localizedDescription))
                exitCLI(1)
            }
        case "delete", "remove":
            guard let target = getOption("--name", from: args) else {
                print("\(L10n.t(.cliMissingParams)) --name <name|uuid>")
                exitCLI(1)
            }
            let profiles = store.loadProfiles()
            guard let matched = profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, target))
                exitCLI(1)
            }
            guard profiles.count > 1 else {
                print(L10n.t(.cliLastProfileError))
                exitCLI(1)
            }
            do {
                try store.deleteProfile(id: matched.id)
                print(L10n.format(.cliProfileDeleted, matched.name))
            } catch {
                print(L10n.format(.cliProfileDeleteError, error.localizedDescription))
                exitCLI(1)
            }
        default:
            print(L10n.format(.cliUnknownSubcommand, sub))
            exitCLI(1)
        }
    }

    // MARK: - Snapshots

    /// Lists completed snapshots stored in the manifest catalog of the given profile.
    /// - Parameter args: Command-line arguments passed to the snapshots subcommand.

    static func handleSnapshots(_ args: [String]) async {
        let profileName = getOption("--profile", from: args)
        let profile = resolveProfile(target: profileName)

        do {
            let snaps = try await SnapshotCatalogService.shared.listSnapshots(for: profile)
            if snaps.isEmpty {
                print(L10n.t(.noSnapshotsAvailable))
            } else {
                print("\(L10n.t(.snapshotsCountTitle)) [\(profile.name)] (\(snaps.count)):")
                let df = ISO8601DateFormatter()
                for s in snaps {
                    let typeTag = s.backupType == "full" ? "[FULL]" : "[INC] "
                    let lockTag = s.isLocked ? " 🔒[WORM LOCKED]" : ""
                    print("• \(typeTag) [\(s.id)]  \(df.string(from: s.timestamp))  \(s.totalFiles) \(L10n.t(.filesCountUnit))  \(formatBytes(s.totalBytes))  (\(s.snapshotPath))\(lockTag)")
                }
            }
            exitCLI(0)
        } catch {
            print("❌ \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Restore

    /// Restores a file or directory from a specific snapshot back to a target directory.
    /// - Parameter args: Command-line arguments passed to the restore subcommand.

    static func handleSchedule(_ args: [String]) async {
        print(L10n.t(.cliScheduleCheckStarting))
        let storage = DefaultFileSystemProvider()
        let database = DatabaseEngine()
        let retentionManager = RetentionManager(storage: storage, database: database)
        let coordinator = BackupSessionCoordinator(
            storage: storage,
            database: database,
            retentionManager: retentionManager,
            volumeEjector: SystemVolumeEjector()
        )
        let store = ProfileStore.shared

        let scheduler = BackupScheduler.shared
        scheduler.start(triggerHandler: { profile, isCatchUp in
            let tag = isCatchUp ? "[Catch-Up]" : "[Scheduled]"
            print("🚀 \(tag) Starting backup for profile '\(profile.name)'...")
            do {
                _ = try await coordinator.performBackup(profile: profile, mode: .incremental)
                var updated = profile
                updated.schedule.lastRunDate = Date()
                try? store.updateProfile(updated)
                print("✅ Backup completed for profile '\(profile.name)'.")
            } catch {
                print("❌ Backup failed for profile '\(profile.name)': \(error.localizedDescription)")
            }
        })

        await scheduler.checkAndRunCatchUpBackups()
        await scheduler.evaluateSchedules()
        scheduler.stop()
        LogManager.shared.flush()
        print(L10n.t(.cliScheduleCheckDone))
    }

    // MARK: - Scrub

    /// Performs cryptographic data scrubbing and bit-rot detection on historical snapshots.
    /// - Parameter args: Command-line arguments.

    static func handleDoctor() async {
        print("🩺 OtterKeep System Health & Diagnostic Audit\n")

        // 1. macOS System & Engine Version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        print("💻 Operating System: macOS \(osVersion)")
        print("🦦 OtterKeep Engine: v\(CoreEngine.version) (Build \(CoreEngine.buildNumber))")
        print("   ├── OtterKeepStorage:  v\(CoreEngine.storageVersion)")
        print("   ├── OtterKeepDatabase: v\(CoreEngine.databaseVersion)")
        print("   ├── OtterKeepCore:     v\(CoreEngine.coreVersion)")
        print("   ├── OtterKeepUI:       v\(CoreEngine.uiVersion)")
        print("   └── OtterKeepCLI:      v\(CoreEngine.cliVersion)\n")

        // 2. Full Disk Access & File System Permissions
        print("🔐 Permissions & TCC:")
        let testPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").path
        let isFDA = access(testPath, R_OK) == 0
        if isFDA {
            print("   ✅ Full Disk Access / Filesystem Read: GRANTED")
        } else {
            print("   ⚠️ Full Disk Access: RESTRICTED or DENIED")
            print("      Action: Open System Settings > Privacy & Security > Full Disk Access and add OtterKeep.")
        }

        // 3. Profiles & Destination Capability Audit
        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        print("\n📁 Backup Profiles Audit (\(profiles.count)):")
        let storage = DefaultFileSystemProvider()

        for (idx, p) in profiles.enumerated() {
            print("   [\(idx + 1)] Profile: \(p.name)")
            let srcExists = FileManager.default.fileExists(atPath: p.sourceURL.path(percentEncoded: false))
            let dstExists = FileManager.default.fileExists(atPath: p.destinationURL.path(percentEncoded: false))

            print("       • Source:      \(srcExists ? "✅ Accessible" : "❌ NOT FOUND") (\(p.sourceURL.path))")
            if srcExists, let srcCaps = try? await storage.capabilities(at: p.sourceURL) {
                print("         FS Format:   \(srcCaps.fsTypeName.uppercased()) (Precision: \(srcCaps.timestampToleranceSeconds)s)")
            }
            print("       • Destination: \(dstExists ? "✅ Mounted" : "⚠️ UNMOUNTED / NOT FOUND") (\(p.destinationURL.path))")

            if dstExists {
                if let caps = try? await storage.capabilities(at: p.destinationURL) {
                    let fsLabel = caps.fsTypeName.uppercased()
                    let roLabel = caps.isReadOnly ? " [READ-ONLY ⚠️]" : " [READ-WRITE ✅]"
                    let cowStatus = caps.supportsAPFSClone ? "✅ Supported (APFS clonefile)" : (caps.isExFAT ? "ℹ️ Fallback Stream Copy (exFAT)" : "⚠️ Unsupported CoW (Fallback Copy)")
                    print("         FS Format:   \(fsLabel)\(roLabel)")
                    print("       • CoW Clones:  \(cowStatus)")
                }
                if let capacity = try? storage.storageCapacity(at: p.destinationURL) {
                    let freeMb = capacity.availableBytes / 1024 / 1024
                    let spaceStatus = freeMb > 2048 ? "✅ \(formatBytes(capacity.availableBytes)) free" : "⚠️ LOW DISK SPACE (\(formatBytes(capacity.availableBytes)))"
                    print("       • Free Space:  \(spaceStatus)")
                }
            }
        }


        // 4. Background Daemon
        print("\n⚙️ Background Daemon:")
        let isDaemon = DaemonServiceManager.shared.isDaemonEnabled
        print("   • LaunchAgent: \(isDaemon ? "✅ Installed & Active (900s interval)" : "ℹ️ Not installed (Run 'otterkeep daemon install' to enable)")")

        print("\n🎉 Doctor diagnostic audit complete.")
        exitCLI(0)
    }

    // MARK: - Helpers

    /// Extracts the value following an option flag in an argument list.
    /// - Parameters:
    ///   - option: The option flag to search for (e.g. `--profile`).
    ///   - args: The argument array.
    /// - Returns: The argument value string if present, or `nil`.

}
