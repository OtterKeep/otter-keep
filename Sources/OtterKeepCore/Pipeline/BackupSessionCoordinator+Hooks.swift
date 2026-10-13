import Foundation
import os
import AppKit
import OtterKeepStorage
import OtterKeepDatabase

extension BackupSessionCoordinator {
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
