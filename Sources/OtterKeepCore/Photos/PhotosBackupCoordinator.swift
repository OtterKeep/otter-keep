import Foundation
import Photos
import os
import OtterKeepStorage
import OtterKeepDatabase

/// Central actor-isolated coordinator for reliable, differential, and storage-efficient Apple Photos backup sessions.
public actor PhotosBackupCoordinator {
    private let storage: FileSystemProvider
    private let dbEngine: DatabaseEngine
    private let metadataExtractor: PhotoMetadataExtractor
    private let deltaScanner: PhotosDeltaScanner
    private let ephemeralGuard: EphemeralStorageGuard
    private let logger = Logger(subsystem: "com.otterkeep", category: "PhotosBackupCoordinator")

    private var isCancelled: Bool = false

    /// Initializes a new `PhotosBackupCoordinator`.
    /// - Parameters:
    ///   - storage: Underlying filesystem provider (default: `DefaultFileSystemProvider`).
    ///   - dbEngine: SQLite database engine for catalog indexing.
    ///   - metadataExtractor: EXIF, IPTC, and GPS sidecar generator.
    ///   - deltaScanner: Differential scanner for photo assets.
    ///   - ephemeralGuard: Disk cache guard for in-flight downloads.
    public init(
        storage: FileSystemProvider = DefaultFileSystemProvider(),
        dbEngine: DatabaseEngine = DatabaseEngine(),
        metadataExtractor: PhotoMetadataExtractor = PhotoMetadataExtractor(),
        deltaScanner: PhotosDeltaScanner = PhotosDeltaScanner(),
        ephemeralGuard: EphemeralStorageGuard = EphemeralStorageGuard()
    ) {
        self.storage = storage
        self.dbEngine = dbEngine
        self.metadataExtractor = metadataExtractor
        self.deltaScanner = deltaScanner
        self.ephemeralGuard = ephemeralGuard
    }

    /// Cancels an in-progress backup session.
    public func cancel() {
        self.isCancelled = true
    }

    /// Queries the current Photos library privacy authorization status on macOS.
    public func checkAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Prompts the user for Photos library read/write authorization.
    public func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Executes the full Apple Photos backup workflow according to the provided configuration.
    /// - Parameters:
    ///   - configuration: Backup profile rules and destination settings.
    ///   - onProgress: Optional callback reporting live telemetry and progress metrics.
    /// - Returns: A session summary containing execution statistics.
    public func executeBackup(
        configuration: PhotosBackupConfiguration,
        onProgress: (@Sendable (PhotosBackupProgressState) -> Void)? = nil
    ) async throws -> PhotosSessionSummary {
        self.isCancelled = false
        let startTime = Date()

        var progress = PhotosBackupProgressState()
        progress.isRunning = true
        progress.phaseDescription = L10n.t(.phaseScanning)
        onProgress?(progress)

        // 1. Verify privacy authorization
        var authStatus = checkAuthorizationStatus()
        if authStatus != .authorized && authStatus != .limited {
            authStatus = await requestAuthorization()
            guard authStatus == .authorized || authStatus == .limited else {
                throw NSError(
                    domain: "com.otterkeep.photos",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "Photos access not authorized. Please grant permission in System Settings -> Privacy & Security -> Photos."]
                )
            }
        }

        // 2. Open catalog database at destination
        let internalDir = configuration.destinationURL.appendingPathComponent(".otterkeep")
        try storage.createDirectory(at: internalDir)
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").path
        try await dbEngine.open(at: dbPath)
        defer {
            Task { await dbEngine.close() }
        }

        // 3. Fetch previous snapshot index
        let previousIndex = try await dbEngine.fetchLatestPhotosAssetIndex()
        let previousSnapshot = try await dbEngine.fetchLatestSnapshot()

        // 4. Scan media library
        let scannedAssets = deltaScanner.scanAssets(configuration: configuration)
        progress.totalAssetsCount = scannedAssets.count
        progress.phaseDescription = L10n.t(.phaseAnalyzing)
        onProgress?(progress)

        // 5. Compute differential delta action list
        let actions = deltaScanner.computeDeltaActions(
            scannedItems: scannedAssets,
            previousIndex: previousIndex,
            configuration: configuration
        )

        // 6. Prepare new snapshot identifier, staging directory and root container
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let snapshotDateStr = formatter.string(from: startTime)
        let snapshotId = "photos_\(snapshotDateStr)"
        let snapshotFolderURL = configuration.destinationURL.appendingPathComponent(snapshotDateStr, isDirectory: true)

        let stagingFolderURL = configuration.destinationURL.appendingPathComponent(".in-progress_photos_\(snapshotDateStr)")
        let rootStagingURL = stagingFolderURL.appendingPathComponent("root")
        try storage.createDirectory(at: rootStagingURL)

        var stagingCommitted = false
        defer {
            if !stagingCommitted {
                try? FileManager.default.removeItem(at: stagingFolderURL)
            }
        }

        progress.phaseDescription = L10n.t(.phaseCopying)
        onProgress?(progress)

        // 7. Process assets with bounded concurrency and APFS CoW cloning
        var downloadedCount = 0
        var downloadedBytes: Int64 = 0
        var clonedCount = 0
        var clonedBytes: Int64 = 0
        var errorCount = 0
        var recordedAssets: [PhotosAssetRecord] = []
        recordedAssets.reserveCapacity(actions.count)

        let resourceManager = PHAssetResourceManager.default()

        // Batch fetch PHAsset entities
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: scannedAssets.map { $0.localIdentifier }, options: nil)
        var assetDictionary: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            assetDictionary[asset.localIdentifier] = asset
        }

        for action in actions {
            if isCancelled || Task.isCancelled {
                await ephemeralGuard.cleanupAllTemporaryFiles()
                throw CancellationError()
            }

            do {
                switch action {
                case .cloneReflink(let prevRecord, let relativePath):
                    let targetURL = rootStagingURL.appendingPathComponent(relativePath)
                    try self.storage.createDirectory(at: targetURL.deletingLastPathComponent())

                    if let prevSnap = previousSnapshot {
                        let prevSnapDir = configuration.destinationURL.appendingPathComponent(prevSnap.snapshotPath)
                        let prevRootURL = prevSnapDir.appendingPathComponent("root")
                        let prevCandidate1 = prevRootURL.appendingPathComponent(prevRecord.relativePath)
                        let prevCandidate2 = prevSnapDir.appendingPathComponent(prevRecord.relativePath)
                        let prevFileURL = FileManager.default.fileExists(atPath: prevCandidate1.path) ? prevCandidate1 : prevCandidate2

                        if (try? self.storage.metadata(at: prevFileURL)) != nil {
                            try await self.storage.cloneItem(at: prevFileURL, to: targetURL)
                        }
                    }

                    let newRec = PhotosAssetRecord(
                        snapshotId: snapshotId,
                        localIdentifier: prevRecord.localIdentifier,
                        originalFilename: prevRecord.originalFilename,
                        relativePath: relativePath,
                        fileSize: prevRecord.fileSize,
                        modificationTime: prevRecord.modificationTime,
                        sha256: prevRecord.sha256,
                        isEdited: prevRecord.isEdited,
                        isLivePhoto: prevRecord.isLivePhoto,
                        mediaType: prevRecord.mediaType,
                        albumsJson: prevRecord.albumsJson
                    )
                    recordedAssets.append(newRec)
                    clonedCount += 1
                    clonedBytes += prevRecord.fileSize
                    progress.clonedBytes = clonedBytes

                case .downloadAndExport(let item, let relativePath):
                    guard let phAsset = assetDictionary[item.localIdentifier] else {
                        continue
                    }

                    let targetURL = rootStagingURL.appendingPathComponent(relativePath)
                    try self.storage.createDirectory(at: targetURL.deletingLastPathComponent())

                    // Download resources from Photos / iCloud
                    let resources = PHAssetResource.assetResources(for: phAsset)
                    let primaryResource = resources.first { $0.type == .photo || $0.type == .video } ?? resources.first

                    guard let resource = primaryResource else {
                        continue
                    }

                    let ext = (resource.originalFilename as NSString).pathExtension
                    let tmpURL = await self.ephemeralGuard.createTemporaryFileURL(prefix: "dl", fileExtension: ext)
                    await self.ephemeralGuard.acquireInFlightCapacity(for: item.estimatedSizeBytes)

                    let options = PHAssetResourceRequestOptions()
                    options.isNetworkAccessAllowed = true

                    do {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            resourceManager.writeData(for: resource, toFile: tmpURL, options: options) { error in
                                if let err = error {
                                    continuation.resume(throwing: err)
                                } else {
                                    continuation.resume()
                                }
                            }
                        }

                        // Move staged download to final destination
                        if FileManager.default.fileExists(atPath: targetURL.path) {
                            try? FileManager.default.removeItem(at: targetURL)
                        }
                        try FileManager.default.moveItem(at: tmpURL, to: targetURL)

                        // Compute file size and cryptographic SHA-256 hash
                        let actualSize = (try? self.storage.metadata(at: targetURL).size) ?? item.estimatedSizeBytes
                        let sha = (try? ChecksumCalculator.computeSHA256(for: targetURL)) ?? nil

                        // Save Live Photo .mov video component if configured
                        if configuration.includeLivePhotoVideos && item.isLivePhoto {
                            if let pairedVideoRes = resources.first(where: { $0.type == .pairedVideo }) {
                                let movRelativePath = (relativePath as NSString).deletingPathExtension + ".mov"
                                let movTargetURL = rootStagingURL.appendingPathComponent(movRelativePath)
                                let movTmpURL = await self.ephemeralGuard.createTemporaryFileURL(prefix: "live_mov", fileExtension: "mov")

                                try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                                    resourceManager.writeData(for: pairedVideoRes, toFile: movTmpURL, options: options) { err in
                                        if let err = err { c.resume(throwing: err) } else { c.resume() }
                                    }
                                }
                                if FileManager.default.fileExists(atPath: movTmpURL.path) {
                                    try? FileManager.default.moveItem(at: movTmpURL, to: movTargetURL)
                                }
                                await self.ephemeralGuard.evictTemporaryFile(at: movTmpURL)
                            }
                        }

                        // Export edited/adjusted version if present
                        var isEditedFlag = false
                        if configuration.includeEditedVersions && item.hasAdjustments {
                            if let adjResource = resources.first(where: { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }) {
                                let adjRelativePath = self.deltaScanner.resolveRelativePath(for: item, structure: configuration.exportStructure, isEdited: true)
                                let adjTargetURL = rootStagingURL.appendingPathComponent(adjRelativePath)
                                try? self.storage.createDirectory(at: adjTargetURL.deletingLastPathComponent())
                                let adjTmpURL = await self.ephemeralGuard.createTemporaryFileURL(prefix: "adj", fileExtension: "jpg")

                                try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                                    resourceManager.writeData(for: adjResource, toFile: adjTmpURL, options: options) { err in
                                        if let err = err { c.resume(throwing: err) } else { c.resume() }
                                    }
                                }
                                if FileManager.default.fileExists(atPath: adjTmpURL.path) {
                                    try? FileManager.default.moveItem(at: adjTmpURL, to: adjTargetURL)
                                    isEditedFlag = true
                                }
                                await self.ephemeralGuard.evictTemporaryFile(at: adjTmpURL)
                            }
                        }

                        // Write standard XMP sidecar file
                        if configuration.generateXMPSidecars {
                            if let xmpData = self.metadataExtractor.generateXMPSidecar(for: phAsset, albums: item.albums) {
                                let xmpRelativePath = (relativePath as NSString).deletingPathExtension + ".xmp"
                                let xmpURL = rootStagingURL.appendingPathComponent(xmpRelativePath)
                                try? xmpData.write(to: xmpURL)
                            }
                        }

                        let albumsJsonData = try? JSONEncoder().encode(item.albums)
                        let albumsJsonStr = albumsJsonData.flatMap { String(data: $0, encoding: .utf8) }

                        let rec = PhotosAssetRecord(
                            snapshotId: snapshotId,
                            localIdentifier: item.localIdentifier,
                            originalFilename: item.originalFilename,
                            relativePath: relativePath,
                            fileSize: actualSize,
                            modificationTime: item.modificationDate,
                            sha256: sha,
                            isEdited: isEditedFlag,
                            isLivePhoto: item.isLivePhoto,
                            mediaType: item.mediaType,
                            albumsJson: albumsJsonStr
                        )
                        recordedAssets.append(rec)
                        downloadedCount += 1
                        downloadedBytes += actualSize
                        progress.downloadedBytes = downloadedBytes
                    } catch {
                        errorCount += 1
                        logger.warning("Download failed for \(item.originalFilename): \(error.localizedDescription)")
                    }

                    await self.ephemeralGuard.evictTemporaryFile(at: tmpURL)
                    await self.ephemeralGuard.releaseInFlightCapacity(for: item.estimatedSizeBytes)
                }
            } catch {
                errorCount += 1
                logger.warning("Photos export error: \(error.localizedDescription)")
            }

            progress.processedAssetsCount += 1
            progress.currentAssetFilename = actionItemFilename(action)
            progress.inFlightBufferBytes = await ephemeralGuard.currentBufferBytes
            progress.errorCount = errorCount
            onProgress?(progress)
        }

        // 8. Commit snapshot manifest and catalog records to SQLite database
        progress.phaseDescription = L10n.t(.phaseFinalizing)
        onProgress?(progress)

        let totalSnapshotBytes = downloadedBytes + clonedBytes
        let snapshotRecord = SnapshotRecord(
            id: snapshotId,
            timestamp: startTime,
            status: errorCount == 0 ? "completed" : "completed_with_warnings",
            totalFiles: Int64(recordedAssets.count),
            totalBytes: totalSnapshotBytes,
            snapshotPath: snapshotDateStr,
            backupType: previousSnapshot == nil ? "full" : "incremental"
        )

        try await dbEngine.insertSnapshot(snapshotRecord)
        try await dbEngine.insertPhotosAssetRecordsBatch(recordedAssets)

        // Write standard FileCatalogRecord entries so snapshot works with RestoreEngine and DataScrubber
        let fileCatalogRecords = recordedAssets.map { asset in
            FileCatalogRecord(
                snapshotId: snapshotId,
                relativePath: asset.relativePath,
                fileSize: asset.fileSize,
                modificationTime: asset.modificationTime,
                inode: 0,
                checksum: asset.sha256,
                isDirectory: false,
                isSymlink: false
            )
        }
        try await dbEngine.insertFileRecordsBatch(fileCatalogRecords)

        // Write standard .snapshot_info.json metadata file
        let snapshotInfoURL = stagingFolderURL.appendingPathComponent(".snapshot_info.json")
        let snapshotInfo: [String: Any] = [
            "id": snapshotId,
            "timestamp": startTime.timeIntervalSince1970,
            "totalFiles": Int64(recordedAssets.count),
            "totalBytes": totalSnapshotBytes,
            "backupType": previousSnapshot == nil ? "full" : "incremental",
            "sourceType": "photos"
        ]
        if let infoData = try? JSONSerialization.data(withJSONObject: snapshotInfo, options: [.prettyPrinted]) {
            try? infoData.write(to: snapshotInfoURL)
        }

        // Atomically commit staged snapshot directory to final destination
        try await storage.atomicMove(from: stagingFolderURL, to: snapshotFolderURL)
        stagingCommitted = true

        // 9. Clean up all temporary files and release database locks
        await ephemeralGuard.cleanupAllTemporaryFiles()
        await dbEngine.close()

        let duration = Date().timeIntervalSince(startTime)
        progress.isRunning = false
        progress.phaseDescription = L10n.t(.phaseCompleted)
        onProgress?(progress)

        let summary = PhotosSessionSummary(
            snapshotId: snapshotId,
            timestamp: startTime,
            durationSeconds: duration,
            totalAssetsScanned: scannedAssets.count,
            newDownloadedCount: downloadedCount,
            newDownloadedBytes: downloadedBytes,
            reflinkClonedCount: clonedCount,
            reflinkClonedBytes: clonedBytes,
            errorCount: errorCount,
            status: errorCount == 0 ? "completed" : "completed_with_warnings"
        )

        logger.info("Photos backup finished: \(downloadedCount) downloaded, \(clonedCount) cloned, \(errorCount) errors, duration: \(duration)s")
        return summary
    }

    private func actionItemFilename(_ action: PhotoAssetAction) -> String {
        switch action {
        case .cloneReflink(let prev, _):
            return prev.originalFilename
        case .downloadAndExport(let item, _):
            return item.originalFilename
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
