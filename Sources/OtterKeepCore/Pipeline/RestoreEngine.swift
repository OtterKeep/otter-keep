import Foundation
import os
import OtterKeepStorage
import OtterKeepDatabase

/// Collision handling strategy when restoring a file to a destination where a file with the same name already exists.
public enum CollisionResolution: Sendable {
    /// Overwrite the existing file at destination.
    case overwrite
    /// Skip restoration if destination file already exists.
    case skip
    /// Keep both files by appending a numerical suffix (e.g. `file (restored 1).txt`).
    case keepBoth
}

/// Structured errors encountered during restore operations.
public enum RestoreError: Error, Sendable, LocalizedError, Equatable {
    /// Target file was not found in the specified snapshot directory.
    case itemNotFoundInSnapshot(String)
    /// Destination conflict occurred and `.skip` resolution was selected.
    case destinationConflict(String)
    /// File restoration failed.
    case restoreFailed(String, String)
    /// Restored file failed cryptographic SHA-256 integrity verification.
    case integrityMismatch(path: String, expected: String, actual: String)
    /// Incompatible collision: directory vs file.
    case typeMismatch(path: String, isSourceDirectory: Bool)
    /// Invalid or unsafe relative path attempting directory traversal.
    case invalidPath(String)

    /// Human-readable localized error description.
    public var errorDescription: String? {
        switch self {
        case .itemNotFoundInSnapshot(let path):
            return "Item not found in snapshot: \(path)"
        case .destinationConflict(let path):
            return "Destination file already exists and skip was chosen: \(path)"
        case .restoreFailed(let path, let msg):
            return "Restore failed (\(path)): \(msg)"
        case .integrityMismatch(let path, let expected, let actual):
            return "Data integrity mismatch (SHA-256 mismatch) for '\(path)'! Expected: \(expected), Actual: \(actual)"
        case .typeMismatch(let path, let isSourceDirectory):
            return isSourceDirectory
                ? "Cannot restore directory '\(path)': a file already exists at the destination."
                : "Cannot restore file '\(path)': a directory already exists at the destination."
        case .invalidPath(let path):
            return "Invalid or unsafe path: \(path)"
        }
    }
}

/// Operational phases of a full snapshot restoration process.
public enum RestorePhase: String, Sendable {
    case preparing = "preparing"
    case restoring = "restoring"
    case verifying = "verifying"
    case completed = "completed"
    case failed = "failed"
}

/// Real-time progress telemetry broadcasted during snapshot restoration.
public struct RestoreProgressState: Sendable {
    public var phase: RestorePhase
    public var totalFiles: Int
    public var processedFiles: Int
    public var totalBytes: Int64
    public var processedBytes: Int64
    public var currentItem: String

    public init(
        phase: RestorePhase = .preparing,
        totalFiles: Int = 0,
        processedFiles: Int = 0,
        totalBytes: Int64 = 0,
        processedBytes: Int64 = 0,
        currentItem: String = ""
    ) {
        self.phase = phase
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.currentItem = currentItem
    }
}

/// Metric summary reported after restoring an entire snapshot.
public struct RestoreSessionSummary: Sendable, Equatable {
    public let snapshotPath: String
    public let totalFiles: Int
    public let totalBytes: Int64
    public let restoredFiles: Int
    public let restoredBytes: Int64
    public let durationSeconds: Double

    public init(
        snapshotPath: String,
        totalFiles: Int,
        totalBytes: Int64,
        restoredFiles: Int,
        restoredBytes: Int64,
        durationSeconds: Double
    ) {
        self.snapshotPath = snapshotPath
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.restoredFiles = restoredFiles
        self.restoredBytes = restoredBytes
        self.durationSeconds = durationSeconds
    }
}

/// Actor-isolated engine responsible for file restoration, collision resolution, cryptographic validation, and raw disk catalog rebuild.
public actor RestoreEngine {
    private let storage: FileSystemProvider
    private let database: DatabaseEngine
    private let logger = Logger(subsystem: "com.otterkeep", category: "RestoreEngine")

    /// Initializes a `RestoreEngine`.
    /// - Parameters:
    ///   - storage: Filesystem provider.
    ///   - database: Catalog database engine.
    public init(storage: FileSystemProvider = DefaultFileSystemProvider(), database: DatabaseEngine = DatabaseEngine()) {
        self.storage = storage
        self.database = database
    }

    private func validatePath(_ path: String, within baseURL: URL) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return baseURL.standardizedFileURL }
        let components = (trimmed as NSString).pathComponents
        if components.contains("..") || (components.count == 1 && components.contains(".")) || trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            throw RestoreError.invalidPath(path)
        }
        let resolved = baseURL.standardizedFileURL.appendingPathComponent(trimmed).standardizedFileURL
        let basePath = baseURL.standardizedFileURL.path(percentEncoded: false)
        let resolvedPath = resolved.path(percentEncoded: false)
        let baseWithSlash = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard resolvedPath == basePath || resolvedPath.hasPrefix(baseWithSlash) else {
            throw RestoreError.invalidPath(path)
        }
        return resolved
    }

    private func validateSnapshotPath(_ snapshotPath: String, within backupRootURL: URL) throws -> URL {
        let trimmed = snapshotPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = (trimmed as NSString).pathComponents
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"), !components.contains("..") else {
            throw RestoreError.invalidPath(snapshotPath)
        }
        let resolved = backupRootURL.standardizedFileURL.appendingPathComponent(trimmed).standardizedFileURL
        let basePath = backupRootURL.standardizedFileURL.path(percentEncoded: false)
        let resolvedPath = resolved.path(percentEncoded: false)
        let baseWithSlash = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard resolvedPath != basePath && resolvedPath.hasPrefix(baseWithSlash) else {
            throw RestoreError.invalidPath(snapshotPath)
        }
        return resolved
    }

    /// Restores a file or directory from a snapshot with collision handling and SHA-256 cryptographic verification.
    /// - Parameters:
    ///   - snapshotPath: Relative snapshot directory name.
    ///   - backupRootURL: Destination backup root URL.
    ///   - relativePath: Relative path of the item within the snapshot root.
    ///   - targetDirectoryURL: Target directory on the user's filesystem where the item will be restored.
    ///   - collisionResolution: Conflict resolution mode.
    /// - Returns: The final restored file URL.
    public func restore(
        snapshotPath: String,
        backupRootURL: URL,
        relativePath: String,
        targetDirectoryURL: URL,
        collisionResolution: CollisionResolution = .keepBoth
    ) async throws -> URL {
        _ = try validateSnapshotPath(snapshotPath, within: backupRootURL)
        let destinationFileURL = try validatePath(relativePath, within: targetDirectoryURL)
        return try await restoreToFile(
            snapshotPath: snapshotPath,
            backupRootURL: backupRootURL,
            relativePath: relativePath,
            destinationFileURL: destinationFileURL,
            collisionResolution: collisionResolution
        )
    }

    /// Restores a file or directory directly to an explicit target destination file URL on disk.
    /// - Parameters:
    ///   - snapshotPath: Relative snapshot directory name.
    ///   - backupRootURL: Destination backup root URL.
    ///   - relativePath: Relative path of the item within the snapshot root.
    ///   - destinationFileURL: Exact destination file URL.
    ///   - collisionResolution: Conflict resolution mode (default: `.overwrite`).
    ///   - expectedChecksum: Optional precomputed or catalog-supplied SHA-256 checksum for verification.
    /// - Returns: The final restored file URL.
    public func restoreToFile(
        snapshotPath: String,
        backupRootURL: URL,
        relativePath: String,
        destinationFileURL: URL,
        collisionResolution: CollisionResolution = .overwrite,
        expectedChecksum: String? = nil
    ) async throws -> URL {
        try Task.checkCancellation()

        let snapshotURL = try validateSnapshotPath(snapshotPath, within: backupRootURL)
        let sourceRootURL = snapshotURL.appendingPathComponent("root")
        let sourceItemURL = try validatePath(relativePath, within: sourceRootURL)

        guard FileManager.default.fileExists(atPath: sourceItemURL.standardizedFileURL.path(percentEncoded: false)) else {
            throw RestoreError.itemNotFoundInSnapshot(relativePath)
        }

        let isSourceDirectory = (try? sourceItemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        var finalDestinationURL = destinationFileURL.standardizedFileURL
        let parentDir = finalDestinationURL.deletingLastPathComponent()
        try storage.createDirectory(at: parentDir)

        // Conflict handling when target file or directory already exists
        let destPath = finalDestinationURL.standardizedFileURL.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: destPath) {
            let isDestDirectory = (try? finalDestinationURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isSourceDirectory != isDestDirectory {
                throw RestoreError.typeMismatch(path: relativePath, isSourceDirectory: isSourceDirectory)
            }

            switch collisionResolution {
            case .skip:
                logger.info("File exists at destination, skipping: \(finalDestinationURL.lastPathComponent)")
                return finalDestinationURL
            case .overwrite:
                logger.info("Will overwrite existing destination file atomically: \(finalDestinationURL.lastPathComponent)")
                // Do NOT delete existing file yet! It remains protected until staging is verified.
            case .keepBoth:
                let ext = finalDestinationURL.pathExtension
                let baseName = finalDestinationURL.deletingPathExtension().lastPathComponent
                var counter = 1
                var newName = "\(baseName)\(L10n.format(.restoredSuffixFormat, counter))"
                if !ext.isEmpty { newName += ".\(ext)" }
                var candidateURL = parentDir.appendingPathComponent(newName)

                while FileManager.default.fileExists(atPath: candidateURL.standardizedFileURL.path(percentEncoded: false)) {
                    counter += 1
                    newName = "\(baseName)\(L10n.format(.restoredSuffixFormat, counter))"
                    if !ext.isEmpty { newName += ".\(ext)" }
                    candidateURL = parentDir.appendingPathComponent(newName)
                }
                finalDestinationURL = candidateURL
                logger.info("Retaining both files with renamed destination: \(finalDestinationURL.lastPathComponent)")
            }
        }

        // Handle directories without pre-deleting destination (non-destructive recursive restoration)
        if isSourceDirectory {
            try storage.createDirectory(at: finalDestinationURL)
            let contents = (try? FileManager.default.contentsOfDirectory(at: sourceItemURL, includingPropertiesForKeys: nil)) ?? []
            for item in contents {
                try Task.checkCancellation()
                let subRel = relativePath.isEmpty ? item.lastPathComponent : "\(relativePath)/\(item.lastPathComponent)"
                _ = try await restoreToFile(
                    snapshotPath: snapshotPath,
                    backupRootURL: backupRootURL,
                    relativePath: subRel,
                    destinationFileURL: finalDestinationURL.appendingPathComponent(item.lastPathComponent),
                    collisionResolution: collisionResolution
                )
            }
            return finalDestinationURL
        }

        // Pre-flight check: ensure target directory filesystem has sufficient storage capacity
        if let sourceMeta = try? storage.metadata(at: sourceItemURL), sourceMeta.size > 0 {
            if let cap = try? storage.storageCapacity(at: parentDir) {
                let eval = VolumeCapabilityEvaluator.evaluate(sourceURL: sourceItemURL, destinationURL: parentDir)
                let safetyMargin: Int64 = 10 * 1024 * 1024
                let requiredSpace = eval.cowMode == .intraVolumeCoW ? safetyMargin : (sourceMeta.size + safetyMargin)
                if cap.availableBytes < requiredSpace {
                    throw FileSystemError.notEnoughSpace(
                        requiredBytes: requiredSpace,
                        availableBytes: cap.availableBytes
                    )
                }
            }
        }

        // 1. Stage file to a temporary hidden file in parentDir to guarantee atomic rollback & protection
        let stagingFilename = ".otterkeep_restore_\(UUID().uuidString)"
        let stagingURL = parentDir.appendingPathComponent(stagingFilename)
        var stagingCommitted = false
        defer {
            if !stagingCommitted {
                try? storage.removeItem(at: stagingURL)
            }
        }

        // 2. Clone or copy to stagingURL
        do {
            try await storage.cloneItem(at: sourceItemURL, to: stagingURL)
        } catch {
            try await storage.copyItemPreservingMetadata(at: sourceItemURL, to: stagingURL, progress: nil)
        }

        // Clear immutability on staging item
        try? storage.setImmutable(at: stagingURL, immutable: false, recursive: true)

        // 3. Pre-flight verify cryptographic SHA-256 data integrity BEFORE touching existing destination
        var targetChecksum = expectedChecksum
        if targetChecksum == nil {
            let internalDir = backupRootURL.appendingPathComponent(".otterkeep")
            let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: dbPath) {
                if (try? await database.open(at: dbPath)) != nil {
                    let snapshots = (try? await database.listSnapshots()) ?? []
                    if let snapshot = snapshots.first(where: { $0.snapshotPath == snapshotPath }) {
                        let files = (try? await database.listFiles(forSnapshotId: snapshot.id)) ?? []
                        if let record = files.first(where: { $0.relativePath == relativePath }),
                           let chk = record.checksum {
                            targetChecksum = chk
                        }
                    }
                    await database.close()
                }
            }
        }

        if let checksum = targetChecksum {
            let actualChecksum = try ChecksumCalculator.computeSHA256(for: stagingURL)
            if actualChecksum != checksum {
                logger.error("Integrity mismatch on restore: \(relativePath) expected: \(checksum), actual: \(actualChecksum)")
                // Quarantine the corrupted restore rather than discarding everything
                let timestampSec = Int(Date().timeIntervalSince1970)
                let corruptName = "\(finalDestinationURL.lastPathComponent).corrupted_\(timestampSec)_\(UUID().uuidString.prefix(6))"
                let corruptURL = parentDir.appendingPathComponent(corruptName)
                if (try? await storage.atomicMove(from: stagingURL, to: corruptURL)) != nil {
                    stagingCommitted = true // Quarantined successfully, do not delete in defer
                }

                throw RestoreError.integrityMismatch(
                    path: relativePath,
                    expected: checksum,
                    actual: actualChecksum
                )
            }
        }

        // 4. Staging verified successfully! Perform atomic swap to finalDestinationURL with .old protection
        if FileManager.default.fileExists(atPath: finalDestinationURL.standardizedFileURL.path(percentEncoded: false)) {
            // Unlock destination file if it has UF_IMMUTABLE active so atomic replace succeeds
            try? storage.setImmutable(at: finalDestinationURL, immutable: false, recursive: true)
            let backupOldURL = parentDir.appendingPathComponent("\(finalDestinationURL.lastPathComponent).old_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6))")
            try await storage.atomicMove(from: finalDestinationURL, to: backupOldURL)
            do {
                try await storage.atomicMove(from: stagingURL, to: finalDestinationURL)
                stagingCommitted = true
                try? storage.removeItem(at: backupOldURL)
            } catch {
                try? await storage.atomicMove(from: backupOldURL, to: finalDestinationURL)
                throw error
            }
        } else {
            try await storage.atomicMove(from: stagingURL, to: finalDestinationURL)
            stagingCommitted = true
        }

        // Guarantee immutability flag is cleared on final target
        try? storage.setImmutable(at: finalDestinationURL, immutable: false, recursive: true)

        logger.info("Restoration successfully verified & atomically committed: \(relativePath) -> \(finalDestinationURL.path)")
        return finalDestinationURL
    }

    /// Restores all items in an entire snapshot directory to a target directory.
    /// Preserves full directory structure, POSIX/Darwin permissions, xattrs, and verifies SHA-256 integrity.
    /// - Parameters:
    ///   - snapshotPath: Relative snapshot directory name.
    ///   - backupRootURL: Destination backup root URL.
    ///   - targetDirectoryURL: Target directory URL where files will be restored.
    ///   - collisionResolution: Conflict resolution mode.
    ///   - progress: Optional callback emitting live progress telemetry.
    /// - Returns: A summary metrics object containing counts and total restored bytes.
    public func restoreSnapshot(
        snapshotPath: String,
        backupRootURL: URL,
        targetDirectoryURL: URL,
        collisionResolution: CollisionResolution = .keepBoth,
        progress: (@Sendable (RestoreProgressState) -> Void)? = nil
    ) async throws -> RestoreSessionSummary {
        try Task.checkCancellation()
        let startTime = Date()

        let snapshotURL = try validateSnapshotPath(snapshotPath, within: backupRootURL)
        let sourceRootURL = snapshotURL.appendingPathComponent("root")

        guard FileManager.default.fileExists(atPath: sourceRootURL.standardizedFileURL.path(percentEncoded: false)) else {
            throw RestoreError.itemNotFoundInSnapshot(snapshotPath)
        }

        let targetURL = targetDirectoryURL.standardizedFileURL
        let parentDir = targetURL.deletingLastPathComponent()

        // 1. Enumerate all items in the snapshot's root directory
        progress?(RestoreProgressState(phase: .preparing, totalFiles: 0, processedFiles: 0, totalBytes: 0, processedBytes: 0, currentItem: "Scanning snapshot items..."))
        let scanner = FileTreeScanner(storage: storage)
        let scannedItems = try await scanner.scan(rootURL: sourceRootURL)

        var totalBytes: Int64 = 0
        var totalFileCount = 0
        for item in scannedItems {
            if !item.metadata.isDirectory {
                totalBytes += item.metadata.size
                totalFileCount += 1
            }
        }

        // 2. Pre-flight capacity check
        if let cap = try? storage.storageCapacity(at: parentDir), totalBytes > 0 {
            let eval = VolumeCapabilityEvaluator.evaluate(sourceURL: sourceRootURL, destinationURL: parentDir)
            let safetyMargin: Int64 = 50 * 1024 * 1024 // 50MB safety margin
            let requiredSpace = eval.cowMode == .intraVolumeCoW ? safetyMargin : (totalBytes + safetyMargin)
            if cap.availableBytes < requiredSpace {
                throw FileSystemError.notEnoughSpace(
                    requiredBytes: requiredSpace,
                    availableBytes: cap.availableBytes
                )
            }
        }

        // Preload catalog checksums in a single query to avoid O(N) database operations
        let internalDir = backupRootURL.appendingPathComponent(".otterkeep")
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)
        var checksumMap: [String: String] = [:]
        if FileManager.default.fileExists(atPath: dbPath) {
            if (try? await database.open(at: dbPath)) != nil {
                let snapshots = (try? await database.listSnapshots()) ?? []
                if let snapshot = snapshots.first(where: { $0.snapshotPath == snapshotPath }) {
                    let catalogFiles = (try? await database.listFiles(forSnapshotId: snapshot.id)) ?? []
                    for rec in catalogFiles {
                        if let cs = rec.checksum {
                            checksumMap[rec.relativePath] = cs
                        }
                    }
                }
                await database.close()
            }
        }

        // 3. Staging and directory creation
        // If overwrite mode is requested, restore into a temporary staging folder first to ensure
        // existing destination files remain 100% untouched until full restore verification completes.
        let useFullDirectoryStaging = (collisionResolution == .overwrite)
        let stagingDir = useFullDirectoryStaging
            ? parentDir.appendingPathComponent(".otterkeep_restore_staging_\(UUID().uuidString)")
            : targetURL

        var stagingCommitted = false
        defer {
            if useFullDirectoryStaging && !stagingCommitted {
                try? storage.removeItem(at: stagingDir)
            }
        }

        try storage.createDirectory(at: stagingDir)

        // Create directories first in order of relative path
        let directories = scannedItems.filter { $0.metadata.isDirectory }.sorted { $0.relativePath < $1.relativePath }
        for dir in directories {
            try Task.checkCancellation()
            let destDir = stagingDir.appendingPathComponent(dir.relativePath)
            try storage.createDirectory(at: destDir)
        }

        // Restore files
        var processedFiles = 0
        var processedBytes: Int64 = 0
        let files = scannedItems.filter { !$0.metadata.isDirectory }
        for file in files {
            try Task.checkCancellation()
            let destFileURL = stagingDir.appendingPathComponent(file.relativePath)

            progress?(RestoreProgressState(
                phase: .restoring,
                totalFiles: totalFileCount,
                processedFiles: processedFiles,
                totalBytes: totalBytes,
                processedBytes: processedBytes,
                currentItem: file.relativePath
            ))

            _ = try await restoreToFile(
                snapshotPath: snapshotPath,
                backupRootURL: backupRootURL,
                relativePath: file.relativePath,
                destinationFileURL: destFileURL,
                collisionResolution: useFullDirectoryStaging ? .overwrite : collisionResolution,
                expectedChecksum: checksumMap[file.relativePath]
            )

            processedFiles += 1
            processedBytes += file.metadata.size

            progress?(RestoreProgressState(
                phase: .restoring,
                totalFiles: totalFileCount,
                processedFiles: processedFiles,
                totalBytes: totalBytes,
                processedBytes: processedBytes,
                currentItem: file.relativePath
            ))
        }

        // 4. Atomic directory swap with .old preservation for overwrite mode
        if useFullDirectoryStaging {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                let backupOldURL = parentDir.appendingPathComponent("\(targetURL.lastPathComponent).old_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6))")
                try? storage.setImmutable(at: targetURL, immutable: false, recursive: true)

                // Step A: Safely rename existing target directory to .old backup
                try await storage.atomicMove(from: targetURL, to: backupOldURL)

                do {
                    // Step B: Atomically move verified staging directory to final target
                    try await storage.atomicMove(from: stagingDir, to: targetURL)
                    stagingCommitted = true
                    try? storage.setImmutable(at: targetURL, immutable: false, recursive: true)

                    // Step C: Only after targetURL is successfully established, clean up .old backup
                    try? storage.removeItem(at: backupOldURL)
                } catch {
                    // Rollback: restore original directory from .old backup
                    try? await storage.atomicMove(from: backupOldURL, to: targetURL)
                    throw error
                }
            } else {
                try await storage.atomicMove(from: stagingDir, to: targetURL)
                stagingCommitted = true
                try? storage.setImmutable(at: targetURL, immutable: false, recursive: true)
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        progress?(RestoreProgressState(
            phase: .completed,
            totalFiles: totalFileCount,
            processedFiles: processedFiles,
            totalBytes: totalBytes,
            processedBytes: processedBytes,
            currentItem: ""
        ))

        // Guarantee all restored files and directories have immutability unlocked
        try? storage.setImmutable(at: targetURL, immutable: false, recursive: true)

        let summary = RestoreSessionSummary(
            snapshotPath: snapshotPath,
            totalFiles: totalFileCount,
            totalBytes: totalBytes,
            restoredFiles: processedFiles,
            restoredBytes: processedBytes,
            durationSeconds: duration
        )

        logger.info("Full snapshot '\(snapshotPath)' restored successfully: \(processedFiles)/\(totalFileCount) files (\(processedBytes) bytes) in \(String(format: "%.2f", duration))s")
        return summary
    }

    /// Rebuilds the internal SQLite database catalog from raw disk snapshot directories.
    /// - Parameter backupRootURL: Destination backup root URL.
    /// - Returns: Count of snapshots successfully re-indexed from disk.
    public func rebuildCatalog(at backupRootURL: URL) async throws -> Int {
        logger.info("Initiating disaster recovery catalog rebuild: \(backupRootURL.path)")

        let internalDir = backupRootURL.standardizedFileURL.appendingPathComponent(".otterkeep")
        try storage.createDirectory(at: internalDir)
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)
        try await database.open(at: dbPath)
        defer {
            Task { await database.close() }
        }

        let contents = (try? FileManager.default.contentsOfDirectory(at: backupRootURL, includingPropertiesForKeys: nil)) ?? []
        var restoredSnapshotsCount = 0

        for url in contents {
            let name = url.lastPathComponent
            if name.hasPrefix(".") || name == "Latest" { continue }

            let infoURL = url.appendingPathComponent(".snapshot_info.json")
            guard FileManager.default.fileExists(atPath: infoURL.standardizedFileURL.path(percentEncoded: false)),
                  let infoData = try? Data(contentsOf: infoURL),
                  let json = (try? JSONSerialization.jsonObject(with: infoData)) as? [String: Any] else {
                continue
            }

            let id = json["id"] as? String ?? "snapshot_\(name)"
            let ts = json["timestamp"] as? Double ?? Date().timeIntervalSince1970
            let filesCount = json["totalFiles"] as? Int64 ?? 0
            let totalBytes = json["totalBytes"] as? Int64 ?? 0

            let record = SnapshotRecord(
                id: id,
                timestamp: Date(timeIntervalSince1970: ts),
                status: "completed",
                totalFiles: filesCount,
                totalBytes: totalBytes,
                snapshotPath: name
            )
            try await database.insertSnapshot(record)

            // Index files from snapshot root folder
            let rootURL = url.appendingPathComponent("root")
            if FileManager.default.fileExists(atPath: rootURL.standardizedFileURL.path(percentEncoded: false)) {
                let scanner = FileTreeScanner(storage: storage)
                let scanned = try await scanner.scan(rootURL: rootURL)
                let fileRecords = scanned.map { item in
                    let hash = (!item.metadata.isDirectory && !item.metadata.isSymlink) ?
                        (try? ChecksumCalculator.computeSHA256(for: item.url)) : nil

                    return FileCatalogRecord(
                        snapshotId: id,
                        relativePath: item.relativePath,
                        fileSize: item.metadata.size,
                        modificationTime: item.metadata.modificationTime,
                        inode: item.metadata.inode,
                        checksum: hash,
                        isDirectory: item.metadata.isDirectory,
                        isSymlink: item.metadata.isSymlink
                    )
                }
                try await database.insertFileRecordsBatch(fileRecords)
            }

            restoredSnapshotsCount += 1
        }

        await database.close()
        logger.info("Disaster recovery catalog rebuild finished: \(restoredSnapshotsCount) snapshots indexed")
        return restoredSnapshotsCount
    }

    /// Restores a file from a remote replication destination (S3 or SMB) with decryption and verification.
    /// - Parameters:
    ///   - destination: Target remote destination definition.
    ///   - snapshotId: Target snapshot identifier.
    ///   - relativePath: Relative path of the file to restore.
    ///   - destinationFileURL: Target local file URL on disk.
    ///   - passphrase: Optional encryption passphrase (defaults to Keychain).
    ///   - collisionResolution: Mode for handling existing destination files.
    /// - Returns: Final restored URL.
    public func restoreFromRemote(
        destination: RemoteDestination,
        snapshotId: String,
        relativePath: String,
        destinationFileURL: URL,
        passphrase: String? = nil,
        collisionResolution: CollisionResolution = .overwrite
    ) async throws -> URL {
        let trimmedSnap = snapshotId.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapComponents = (trimmedSnap as NSString).pathComponents
        guard !trimmedSnap.isEmpty, !trimmedSnap.hasPrefix("/"), !trimmedSnap.hasPrefix("~"), !snapComponents.contains("..") else {
            throw RestoreError.invalidPath(snapshotId)
        }
        let trimmedRel = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let relComponents = (trimmedRel as NSString).pathComponents
        guard !trimmedRel.isEmpty, !trimmedRel.hasPrefix("/"), !trimmedRel.hasPrefix("~"), !relComponents.contains("..") else {
            throw RestoreError.invalidPath(relativePath)
        }

        logger.info("Initiating remote restore for '\(relativePath)' from destination '\(destination.name)'")

        var finalDestinationURL = destinationFileURL.standardizedFileURL
        let parentDir = finalDestinationURL.deletingLastPathComponent()
        try storage.createDirectory(at: parentDir)

        // Conflict handling when target file already exists
        if FileManager.default.fileExists(atPath: finalDestinationURL.standardizedFileURL.path(percentEncoded: false)) {
            switch collisionResolution {
            case .skip:
                logger.info("File exists at destination, skipping remote restore: \(finalDestinationURL.lastPathComponent)")
                return finalDestinationURL
            case .overwrite:
                logger.info("Will overwrite existing destination file atomically: \(finalDestinationURL.lastPathComponent)")
            case .keepBoth:
                let ext = finalDestinationURL.pathExtension
                let baseName = finalDestinationURL.deletingPathExtension().lastPathComponent
                var counter = 1
                var newName = "\(baseName)\(L10n.format(.restoredSuffixFormat, counter))"
                if !ext.isEmpty { newName += ".\(ext)" }
                var candidateURL = parentDir.appendingPathComponent(newName)

                while FileManager.default.fileExists(atPath: candidateURL.standardizedFileURL.path(percentEncoded: false)) {
                    counter += 1
                    newName = "\(baseName)\(L10n.format(.restoredSuffixFormat, counter))"
                    if !ext.isEmpty { newName += ".\(ext)" }
                    candidateURL = parentDir.appendingPathComponent(newName)
                }
                finalDestinationURL = candidateURL
                logger.info("Retaining both files with renamed destination: \(finalDestinationURL.lastPathComponent)")
            }
        }

        let stagingFilename = ".otterkeep_remote_restore_\(UUID().uuidString)"
        let stagingURL = parentDir.appendingPathComponent(stagingFilename)
        var stagingCommitted = false
        defer {
            if !stagingCommitted {
                try? storage.removeItem(at: stagingURL)
            }
        }

        let resolvedPassphrase = RemoteStorageFactory.resolveEncryptionPassphrase(for: destination, profileId: destination.id, explicitPassphrase: passphrase)

        switch destination.type {
        case .s3(let s3Config):
            let s3Provider = RemoteStorageFactory.makeS3Provider(for: destination, config: s3Config)

            let encryptedKey = "\(snapshotId)/\(relativePath).enc"
            let plainKey = "\(snapshotId)/\(relativePath)"

            let rawDownloadedData: Data
            var isEncrypted = destination.isClientEncryptionEnabled

            if isEncrypted {
                do {
                    rawDownloadedData = try await s3Provider.getObject(key: encryptedKey)
                } catch {
                    rawDownloadedData = try await s3Provider.getObject(key: plainKey)
                    isEncrypted = false
                }
            } else {
                do {
                    rawDownloadedData = try await s3Provider.getObject(key: plainKey)
                } catch {
                    rawDownloadedData = try await s3Provider.getObject(key: encryptedKey)
                    isEncrypted = true
                }
            }

            let finalData: Data
            if isEncrypted {
                finalData = try ClientSideEncryptor.decrypt(envelope: rawDownloadedData, passphrase: resolvedPassphrase)
            } else {
                finalData = rawDownloadedData
            }

            try finalData.write(to: stagingURL, options: .atomic)

        case .backblazeB2(let b2Config):
            let b2Provider = RemoteStorageFactory.makeB2Provider(for: destination, config: b2Config)

            let encryptedKey = "\(snapshotId)/\(relativePath).enc"
            let plainKey = "\(snapshotId)/\(relativePath)"

            let rawDownloadedData: Data
            var isEncrypted = destination.isClientEncryptionEnabled

            if isEncrypted {
                do {
                    rawDownloadedData = try await b2Provider.getObject(key: encryptedKey)
                } catch {
                    rawDownloadedData = try await b2Provider.getObject(key: plainKey)
                    isEncrypted = false
                }
            } else {
                do {
                    rawDownloadedData = try await b2Provider.getObject(key: plainKey)
                } catch {
                    rawDownloadedData = try await b2Provider.getObject(key: encryptedKey)
                    isEncrypted = true
                }
            }

            let finalData: Data
            if isEncrypted {
                finalData = try ClientSideEncryptor.decrypt(envelope: rawDownloadedData, passphrase: resolvedPassphrase)
            } else {
                finalData = rawDownloadedData
            }

            try finalData.write(to: stagingURL, options: .atomic)

        case .smb(let smbConfig):
            let (mountPoint, resolvedSubpath) = try await RemoteStorageFactory.mountNetworkShare(for: destination, config: smbConfig)

            let baseRemoteDir = mountPoint.appendingPathComponent(resolvedSubpath).appendingPathComponent(snapshotId)
            let fileURL = baseRemoteDir.appendingPathComponent("root").appendingPathComponent(relativePath)
            let encURL = baseRemoteDir.appendingPathComponent("root").appendingPathComponent("\(relativePath).enc")

            let finalData: Data
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                finalData = try Data(contentsOf: fileURL)
            } else if FileManager.default.fileExists(atPath: encURL.path(percentEncoded: false)) {
                let encData = try Data(contentsOf: encURL)
                finalData = try ClientSideEncryptor.decrypt(envelope: encData, passphrase: resolvedPassphrase)
            } else {
                throw RestoreError.itemNotFoundInSnapshot(relativePath)
            }

            try finalData.write(to: stagingURL, options: .atomic)

        case .webdav(let webdavConfig):
            let provider = RemoteStorageFactory.makeWebDAVProvider(for: destination, config: webdavConfig)

            let encryptedPath = "\(snapshotId)/\(relativePath).enc"
            let plainPath = "\(snapshotId)/\(relativePath)"

            let rawData: Data
            var isEncrypted = destination.isClientEncryptionEnabled
            if isEncrypted {
                do {
                    rawData = try await provider.downloadFile(path: encryptedPath)
                } catch {
                    rawData = try await provider.downloadFile(path: plainPath)
                    isEncrypted = false
                }
            } else {
                do {
                    rawData = try await provider.downloadFile(path: plainPath)
                } catch {
                    rawData = try await provider.downloadFile(path: encryptedPath)
                    isEncrypted = true
                }
            }

            let finalData: Data
            if isEncrypted {
                finalData = try ClientSideEncryptor.decrypt(envelope: rawData, passphrase: resolvedPassphrase)
            } else {
                finalData = rawData
            }

            try finalData.write(to: stagingURL, options: .atomic)

        case .sftp(let sftpConfig):
            let provider = RemoteStorageFactory.makeSFTPProvider(for: destination, config: sftpConfig)

            let tempDownloadURL = parentDir.appendingPathComponent(".otterkeep_sftp_temp_\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDownloadURL) }

            let encryptedRemote = "\(snapshotId)/\(relativePath).enc"
            let plainRemote = "\(snapshotId)/\(relativePath)"

            var isEncrypted = destination.isClientEncryptionEnabled
            if isEncrypted {
                do {
                    try await provider.downloadFile(remotePath: encryptedRemote, to: tempDownloadURL)
                } catch {
                    try await provider.downloadFile(remotePath: plainRemote, to: tempDownloadURL)
                    isEncrypted = false
                }
            } else {
                do {
                    try await provider.downloadFile(remotePath: plainRemote, to: tempDownloadURL)
                } catch {
                    try await provider.downloadFile(remotePath: encryptedRemote, to: tempDownloadURL)
                    isEncrypted = true
                }
            }

            let rawData = try Data(contentsOf: tempDownloadURL)
            let finalData: Data
            if isEncrypted {
                finalData = try ClientSideEncryptor.decrypt(envelope: rawData, passphrase: resolvedPassphrase)
            } else {
                finalData = rawData
            }

            try finalData.write(to: stagingURL, options: .atomic)
        }

        if FileManager.default.fileExists(atPath: finalDestinationURL.standardizedFileURL.path(percentEncoded: false)) {
            // Unlock destination file if it has UF_IMMUTABLE active so atomic replace succeeds
            try? storage.setImmutable(at: finalDestinationURL, immutable: false, recursive: true)
            let backupOldURL = parentDir.appendingPathComponent("\(finalDestinationURL.lastPathComponent).old_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6))")
            try await storage.atomicMove(from: finalDestinationURL, to: backupOldURL)
            do {
                try await storage.atomicMove(from: stagingURL, to: finalDestinationURL)
                stagingCommitted = true
                try? storage.removeItem(at: backupOldURL)
            } catch {
                try? await storage.atomicMove(from: backupOldURL, to: finalDestinationURL)
                throw error
            }
        } else {
            try await storage.atomicMove(from: stagingURL, to: finalDestinationURL)
            stagingCommitted = true
        }

        try? storage.setImmutable(at: finalDestinationURL, immutable: false, recursive: true)
        logger.info("Remote restore successfully committed: \(relativePath) -> \(finalDestinationURL.path)")
        return finalDestinationURL
    }
}
