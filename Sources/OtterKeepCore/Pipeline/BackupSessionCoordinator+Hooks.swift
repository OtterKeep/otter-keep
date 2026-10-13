import Foundation
import Darwin
import os
import OtterKeepStorage
import OtterKeepDatabase

extension BackupSessionCoordinator {
    /// Determines whether an error indicates destination disk space exhaustion (ENOSPC).
    ///
    /// Evaluates `FileSystemError.isOutOfSpace`, POSIX `ENOSPC`, and Cocoa `NSFileWriteOutOfSpaceError`.
    static func isOutOfSpaceError(_ error: Error) -> Bool {
        if let fs = error as? FileSystemError, fs.isOutOfSpace {
            return true
        }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && Int32(ns.code) == ENOSPC {
            return true
        }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return true
        }
        return false
    }

    /// Determines whether an error represents an abrupt, non-recoverable storage or volume failure.
    ///
    /// Detects POSIX `EIO` (I/O error), `ENODEV` (no such device / detached volume), and `EROFS` (read-only filesystem).
    static func isFatalVolumeError(_ error: Error) -> Bool {
        if let fs = error as? FileSystemError, fs.isFatalVolumeError {
            return true
        }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain {
            let code = Int32(ns.code)
            return code == EIO || code == ENODEV || code == EROFS
        }
        return false
    }

    /// Cleans up uncommitted staging directories or leftover temporary artifacts from previous interrupted sessions.
    ///
    /// Strips immutable flags if set and removes `.in-progress_*`, `.latest_temp`, and `.trash_*` folders.
    func cleanupDanglingStagingDirectories(at destinationURL: URL) throws {
        let contents = (try? FileManager.default.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            let name = url.lastPathComponent
            if name.hasPrefix(".in-progress_") || name == ".latest_temp" || name.hasPrefix(".trash_") {
                logger.warning("Cleaning dangling temporary directory: \(name)")
                try? storage.setImmutable(at: url, immutable: false, recursive: true)
                try? storage.removeItem(at: url)
            }
        }
    }

    /// Reconciles unindexed completed snapshots from destination storage, certifying 100% completeness before registering into SQLite.
    public func reconcileUnindexedSnapshots(at destinationURL: URL, profile: BackupProfile) async throws {
        let existingSnapshots = (try? await database.listSnapshots()) ?? []
        let indexedPaths = Set(existingSnapshots.map { $0.snapshotPath })
        let indexedIds = Set(existingSnapshots.map { $0.id })

        let contents = (try? FileManager.default.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for dirURL in contents {
            let dirName = dirURL.lastPathComponent
            // Exclude internal directories, staging folders, or symbolic links
            guard !dirName.hasPrefix("."), dirName != "Latest" else { continue }
            guard !indexedPaths.contains(dirName) && !indexedIds.contains("snapshot_\(dirName)") else { continue }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

            // 100% certainty verification check
            guard let verifiedRecord = await verifySnapshotCompleteness(at: dirURL, expectedProfileName: profile.name) else {
                logger.info("Pre-flight reconciliation skipped unverified or incomplete directory: \(dirName)")
                continue
            }

            logger.info("100% verified unindexed snapshot found on disk: \(dirName) (ID: \(verifiedRecord.id)). Registering into SQLite catalog...")
            LogManager.shared.log("Reconciling unindexed completed snapshot from disk: '\(dirName)' (ID: \(verifiedRecord.id)) for profile '\(profile.name)'.", level: .info, category: "Backup")

            try? await database.insertSnapshot(verifiedRecord)

            // Index files from root/ directory into file catalog
            let rootURL = dirURL.appendingPathComponent("root")
            let scanner = FileTreeScanner(storage: storage)
            if let scannedItems = try? await scanner.scan(rootURL: rootURL) {
                var records: [FileCatalogRecord] = []
                for item in scannedItems {
                    records.append(FileCatalogRecord(
                        snapshotId: verifiedRecord.id,
                        relativePath: item.relativePath,
                        fileSize: item.metadata.size,
                        modificationTime: item.metadata.modificationTime,
                        inode: item.metadata.inode,
                        checksum: try? ChecksumCalculator.computeSHA256(for: item.url),
                        sampleHash: try? FastHashCalculator.computeSamplingHash(for: item.url),
                        isDirectory: item.metadata.isDirectory,
                        isSymlink: item.metadata.isSymlink
                    ))
                }
                if !records.isEmpty {
                    try? await database.insertFileRecordsBatch(records)
                }
                // Mirror to CentralDatabase for offline inspection
                try? CentralDatabase.shared.cacheSnapshotWithFiles(verifiedRecord, files: records, forProfileId: profile.id.uuidString)
            }
        }
    }

    /// Validates with 100% certainty whether a directory on disk is a fully completed, committed snapshot.
    public func verifySnapshotCompleteness(at snapshotDirURL: URL, expectedProfileName: String) async -> SnapshotRecord? {
        let dirName = snapshotDirURL.lastPathComponent

        // 1. Strict name format: yyyy-MM-dd_HHmmss or yyyy-MM-dd_HHmmss_\d+
        let pattern = #"^\d{4}-\d{2}-\d{2}_\d{6}(_\d+)?$"#
        guard dirName.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }

        // 2. .snapshot_info.json must exist and be readable
        let infoURL = snapshotDirURL.appendingPathComponent(".snapshot_info.json")
        guard FileManager.default.fileExists(atPath: infoURL.path),
              let infoData = try? Data(contentsOf: infoURL),
              let json = (try? JSONSerialization.jsonObject(with: infoData)) as? [String: Any] else {
            return nil
        }

        // 3. Required fields validation
        guard let id = json["id"] as? String, !id.isEmpty,
              let ts = json["timestamp"] as? Double, ts > 0,
              let totalFiles = json["totalFiles"] as? Int, totalFiles >= 0,
              let totalBytes = json["totalBytes"] as? Int64, totalBytes >= 0 else {
            return nil
        }

        // 4. Must be marked committed or completed
        let isCommitted = (json["isCommitted"] as? Bool) == true
        let status = (json["status"] as? String) ?? "completed"
        guard isCommitted || status == "completed" || status == "completed_with_warnings" || status == "completed_with_errors" else {
            return nil
        }

        // 5. Must match profile name if profileName is set in info
        if let infoProfileName = json["profileName"] as? String, !infoProfileName.isEmpty {
            guard infoProfileName == expectedProfileName else {
                return nil
            }
        }

        // 6. The root directory must exist and be accessible
        let rootURL = snapshotDirURL.appendingPathComponent("root")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        // 7. Non-empty check: if totalFiles > 0, root directory must contain files
        if totalFiles > 0 {
            let rootContents = (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []
            guard !rootContents.isEmpty else {
                return nil
            }
        }

        let date = Date(timeIntervalSince1970: ts)
        let backupType = (json["backupType"] as? String) ?? "incremental"

        return SnapshotRecord(
            id: id,
            timestamp: date,
            status: status,
            totalFiles: Int64(totalFiles),
            totalBytes: totalBytes,
            snapshotPath: dirName,
            backupType: backupType
        )
    }

    struct CopyWorkerResult: Sendable {
        let item: ScannedItem
        let record: FileCatalogRecord?
        let copiedBytes: Int64
        let errorItem: BackupErrorItem?
        let skippedItem: SkippedItem?
    }

    func handleCopyWorkerResult(
        _ result: CopyWorkerResult,
        profile: BackupProfile,
        progressTracker: OSAllocatedUnfairLock<BackupProgressState>,
        copiedCount: inout Int,
        copiedBytes: inout Int64,
        catalogRecordsToSave: inout [FileCatalogRecord],
        errorItems: inout [BackupErrorItem],
        skippedItems: inout [SkippedItem],
        reportProgress: () -> Void
    ) {
        if let record = result.record {
            catalogRecordsToSave.append(record)
            copiedCount += 1
            copiedBytes += result.copiedBytes

            let currentCopiedCount = copiedCount
            let currentCopiedBytes = copiedBytes
            let itemBytes = result.copiedBytes
            progressTracker.withLock { state in
                state.processedBytes += itemBytes
                state.processedFiles += 1
                state.copiedCount = currentCopiedCount
                state.copiedBytes = currentCopiedBytes
                state.currentItem = result.item.relativePath
            }
        } else if let err = result.errorItem, let skip = result.skippedItem {
            logger.warning("Failed to process '\(result.item.relativePath)': \(err.errorMessage)")
            let isPerm = err.isPermissionError
            let reasonTag = isPerm ? "[Permission Denied / TCC]" : "[Read/Copy Failed]"
            LogManager.shared.log("\(reasonTag) Failed to backup '\(result.item.relativePath)' in profile '\(profile.name)': \(err.errorMessage)", level: .warning, category: "Backup")

            errorItems.append(err)
            skippedItems.append(skip)

            let currentErrors = errorItems
            let currentSkipped = skippedItems
            progressTracker.withLock { state in
                state.processedFiles += 1
                state.currentItem = result.item.relativePath
                state.errorCount = currentErrors.count
                state.errorItems = currentErrors
                state.skippedCount = currentSkipped.count
                state.skippedItems = currentSkipped
            }
        }
        reportProgress()
    }

    func runPostBackupHook(
        profile: BackupProfile,
        mode: BackupMode,
        status: String,
        snapshotPath: String,
        scannedFiles: Int,
        copiedFiles: Int,
        copiedBytes: Int64,
        durationSeconds: Double
    ) async {
        guard let postHookURL = await HookExecutionManager.shared.resolveHookScript(hookName: "post-backup", profile: profile) else {
            return
        }
        logger.info("Executing post-backup hook script: \(postHookURL.path)")
        LogManager.shared.log("Executing post-backup hook script: '\(postHookURL.path)'", level: .info, category: "Hook")
        let postEnv: [String: String] = [
            "OTTERKEEP_PROFILE_ID": profile.id.uuidString,
            "OTTERKEEP_PROFILE_NAME": profile.name,
            "OTTERKEEP_PROFILE": profile.name,
            "OTTERKEEP_SOURCE_PATH": profile.sourceURL.standardizedFileURL.path,
            "OTTERKEEP_SOURCE": profile.sourceURL.standardizedFileURL.path,
            "OTTERKEEP_DESTINATION_PATH": profile.destinationURL.standardizedFileURL.path,
            "OTTERKEEP_DESTINATION": profile.destinationURL.standardizedFileURL.path,
            "OTTERKEEP_BACKUP_MODE": mode.rawValue,
            "OTTERKEEP_STATUS": status,
            "OTTERKEEP_SNAPSHOT_PATH": snapshotPath,
            "OTTERKEEP_FILES_SCANNED": String(scannedFiles),
            "OTTERKEEP_FILES_COPIED": String(copiedFiles),
            "OTTERKEEP_BYTES_WRITTEN": String(copiedBytes),
            "OTTERKEEP_DURATION_SECONDS": String(format: "%.2f", durationSeconds)
        ]
        do {
            let result = try await HookExecutionManager.shared.executeHook(scriptURL: postHookURL, environment: postEnv)
            if result.isSuccess {
                LogManager.shared.log("Post-backup hook executed successfully (Exit code: 0).", level: .info, category: "Hook")
            } else {
                LogManager.shared.log("Post-backup hook exited with non-zero status \(result.exitCode). Stderr: \(result.standardError)", level: .warning, category: "Hook")
            }
        } catch {
            LogManager.shared.log("Post-backup hook execution error: \(error.localizedDescription)", level: .warning, category: "Hook")
        }
    }

    func dispatchWebhookNotification(
        profile: BackupProfile,
        status: String,
        snapshotPath: String,
        scannedFiles: Int,
        copiedFiles: Int,
        copiedBytes: Int64,
        durationSeconds: Double,
        errorMessage: String? = nil
    ) async {
        guard profile.webhookConfig.isEnabled else { return }
        let payload = WebhookBackupPayload(
            profileId: profile.id.uuidString,
            profileName: profile.name,
            status: status,
            snapshotPath: snapshotPath,
            filesScanned: Int64(scannedFiles),
            filesCopied: Int64(copiedFiles),
            bytesWritten: copiedBytes,
            durationSeconds: durationSeconds,
            timestamp: Date(),
            errorMessage: errorMessage
        )
        do {
            try await WebhookDispatcher.shared.dispatch(config: profile.webhookConfig, payload: payload)
        } catch {
            LogManager.shared.log("Failed to dispatch webhook notification: \(error.localizedDescription)", level: .warning, category: "Webhook")
        }
    }
}
