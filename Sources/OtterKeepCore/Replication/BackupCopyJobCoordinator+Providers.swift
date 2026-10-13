import Foundation
import os
import OtterKeepStorage
import OtterKeepDatabase

extension BackupCopyJobCoordinator {
    // MARK: - Private Protocol-Specific Replicators

    func replicateS3(
        dest: RemoteDestination,
        s3Config: S3Configuration,
        snapshot: SnapshotRecord,
        snapshotRoot: URL,
        filesToSync: [FileCatalogRecord],
        profile: BackupProfile,
        throttler: BandwidthThrottler,
        state: inout ReplicationProgressState
    ) async throws -> DestinationSyncResult {
        let destId = "s3://\(s3Config.bucket)/\(s3Config.pathPrefix)"
        _ = try await database.recordReplicationSnapshot(ReplicationSnapshotRecord(
            snapshotId: snapshot.id,
            destinationType: "s3",
            destinationIdentifier: destId,
            status: "in_progress",
            replicatedBytes: 0,
            totalBytes: snapshot.totalBytes,
            startedAt: Date()
        ))

        do {
            let s3Provider = RemoteStorageFactory.makeS3Provider(for: dest, config: s3Config)
            let passphrase = RemoteStorageFactory.resolveEncryptionPassphrase(for: dest, profileId: profile.id)

            var destReplicatedFiles = 0
            var destReplicatedBytes: Int64 = 0
            var destSkippedFiles = 0

            if dest.archivePackagingEnabled || profile.copyJobConfig.archivePackagingEnabled {
                state.statusMessage = "Packaging snapshot into compressed archive..."
                let format = ArchivePackagingEngine.shared.defaultFormat
                state.currentFile = "\(snapshot.id).\(format.fileExtension)"
                onProgress?(state)

                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_Arch_\(UUID().uuidString)")
                let archiveURL = tempDir.appendingPathComponent("\(snapshot.id).\(format.fileExtension)")
                defer { try? FileManager.default.removeItem(at: tempDir) }

                try await ArchivePackagingEngine.shared.createArchive(
                    sourceDirectory: snapshotRoot,
                    destinationArchiveURL: archiveURL,
                    compressionLevel: dest.archiveCompressionLevel
                )

                let rawData = try Data(contentsOf: archiveURL)
                let payload: Data
                let objectKey: String
                if dest.isClientEncryptionEnabled {
                    payload = try ClientSideEncryptor.encrypt(data: rawData, passphrase: passphrase)
                    objectKey = "\(snapshot.id)/\(archiveURL.lastPathComponent).enc"
                } else {
                    payload = rawData
                    objectKey = "\(snapshot.id)/\(archiveURL.lastPathComponent)"
                }

                await throttler.throttle(byteCount: Int64(payload.count))

                let etag: String
                if payload.count > 8 * 1024 * 1024 {
                    let uploadId = try await s3Provider.initiateMultipartUpload(key: objectKey)
                    var parts: [(partNumber: Int, etag: String)] = []
                    let chunkSize = 5 * 1024 * 1024
                    var offset = 0
                    var partNumber = 1

                    while offset < payload.count {
                        try Task.checkCancellation()
                        let length = min(chunkSize, payload.count - offset)
                        let chunkData = payload.subdata(in: offset..<(offset + length))
                        await throttler.throttle(byteCount: Int64(chunkData.count))
                        let partETag = try await s3Provider.uploadPart(key: objectKey, uploadId: uploadId, partNumber: partNumber, data: chunkData)
                        parts.append((partNumber: partNumber, etag: partETag))
                        offset += length
                        partNumber += 1
                    }
                    try await s3Provider.completeMultipartUpload(key: objectKey, uploadId: uploadId, parts: parts)
                    etag = parts.first?.etag ?? ""
                } else {
                    etag = try await s3Provider.putObject(key: objectKey, data: payload)
                }

                try await database.recordReplicationFile(ReplicationFileRecord(
                    snapshotId: snapshot.id,
                    destinationIdentifier: destId,
                    relativePath: archiveURL.lastPathComponent,
                    remoteKey: objectKey,
                    remoteETag: etag,
                    checksum: try? ChecksumCalculator.computeSHA256(for: archiveURL),
                    fileSize: Int64(payload.count),
                    status: "replicated"
                ))

                destReplicatedFiles = 1
                destReplicatedBytes = Int64(payload.count)
                state.processedFiles = filesToSync.count
                state.replicatedBytes = destReplicatedBytes
                onProgress?(state)
            } else {
                for file in filesToSync {
                    try Task.checkCancellation()

                    state.currentFile = file.relativePath
                    onProgress?(state)

                    let (alreadySynced, existingKey, existingETag) = try await database.isReplicationFileSynced(
                        destinationIdentifier: destId,
                        relativePath: file.relativePath,
                        checksum: file.checksum,
                        fileSize: file.fileSize
                    )

                    if alreadySynced, let key = existingKey {
                        destSkippedFiles += 1
                        try await database.recordReplicationFile(ReplicationFileRecord(
                            snapshotId: snapshot.id,
                            destinationIdentifier: destId,
                            relativePath: file.relativePath,
                            remoteKey: key,
                            remoteETag: existingETag,
                            checksum: file.checksum,
                            fileSize: file.fileSize,
                            status: "reused"
                        ))
                        state.processedFiles += 1
                        onProgress?(state)
                        continue
                    }

                    let localFileURL = snapshotRoot.appendingPathComponent(file.relativePath)
                    guard FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else {
                        continue
                    }

                    let rawData = try Data(contentsOf: localFileURL)
                    let payload: Data
                    let objectKey: String
                    if dest.isClientEncryptionEnabled {
                        payload = try ClientSideEncryptor.encrypt(data: rawData, passphrase: passphrase)
                        objectKey = "\(snapshot.id)/\(file.relativePath).enc"
                    } else {
                        payload = rawData
                        objectKey = "\(snapshot.id)/\(file.relativePath)"
                    }

                    await throttler.throttle(byteCount: Int64(payload.count))

                    let etag: String
                    if payload.count > 8 * 1024 * 1024 {
                        let uploadId = try await s3Provider.initiateMultipartUpload(key: objectKey)
                        var parts: [(partNumber: Int, etag: String)] = []
                        let chunkSize = 5 * 1024 * 1024
                        var offset = 0
                        var partNumber = 1

                        while offset < payload.count {
                            try Task.checkCancellation()
                            let length = min(chunkSize, payload.count - offset)
                            let chunkData = payload.subdata(in: offset..<(offset + length))
                            await throttler.throttle(byteCount: Int64(chunkData.count))
                            let partETag = try await s3Provider.uploadPart(key: objectKey, uploadId: uploadId, partNumber: partNumber, data: chunkData)
                            parts.append((partNumber: partNumber, etag: partETag))
                            offset += length
                            partNumber += 1
                        }
                        try await s3Provider.completeMultipartUpload(key: objectKey, uploadId: uploadId, parts: parts)
                        etag = parts.first?.etag ?? ""
                    } else {
                        etag = try await s3Provider.putObject(key: objectKey, data: payload)
                    }

                    try await database.recordReplicationFile(ReplicationFileRecord(
                        snapshotId: snapshot.id,
                        destinationIdentifier: destId,
                        relativePath: file.relativePath,
                        remoteKey: objectKey,
                        remoteETag: etag,
                        checksum: file.checksum,
                        fileSize: file.fileSize,
                        status: "replicated"
                    ))

                    destReplicatedFiles += 1
                    destReplicatedBytes += file.fileSize
                    state.processedFiles += 1
                    state.replicatedBytes += file.fileSize
                    onProgress?(state)
                }
            }

            try await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "completed",
                replicatedBytes: destReplicatedBytes,
                completedAt: Date()
            )

            logger.info("Successfully replicated snapshot \(snapshot.id) to S3: \(destReplicatedFiles) files, \(destReplicatedBytes) bytes")
            return DestinationSyncResult(
                replicatedFiles: destReplicatedFiles,
                replicatedBytes: destReplicatedBytes,
                skippedFiles: destSkippedFiles,
                isSuccess: true
            )
        } catch {
            let errMsg = error.localizedDescription
            logger.error("Failed to replicate snapshot to S3: \(errMsg)")
            try? await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "failed",
                replicatedBytes: 0,
                completedAt: Date(),
                errorMessage: errMsg
            )
            return DestinationSyncResult(
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                isSuccess: false
            )
        }
    }

    func replicateSMB(
        dest: RemoteDestination,
        smbConfig: NetworkShareConfiguration,
        snapshot: SnapshotRecord,
        snapshotRoot: URL,
        filesToSync: [FileCatalogRecord],
        profile: BackupProfile,
        throttler: BandwidthThrottler,
        state: inout ReplicationProgressState
    ) async throws -> DestinationSyncResult {
        let destId = smbConfig.shareURL
        _ = try await database.recordReplicationSnapshot(ReplicationSnapshotRecord(
            snapshotId: snapshot.id,
            destinationType: "smb",
            destinationIdentifier: destId,
            status: "in_progress",
            replicatedBytes: 0,
            totalBytes: snapshot.totalBytes,
            startedAt: Date()
        ))

        do {
            let (mountPoint, resolvedSubpath) = try await RemoteStorageFactory.mountNetworkShare(for: dest, config: smbConfig)
            let targetDir = mountPoint.appendingPathComponent(resolvedSubpath).appendingPathComponent(snapshot.snapshotPath)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            var destReplicatedFiles = 0
            var destReplicatedBytes: Int64 = 0
            var destSkippedFiles = 0

            for file in filesToSync {
                try Task.checkCancellation()
                let srcURL = snapshotRoot.appendingPathComponent(file.relativePath)
                let dstURL = targetDir.appendingPathComponent("root").appendingPathComponent(file.relativePath)
                try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                if !FileManager.default.fileExists(atPath: dstURL.path(percentEncoded: false)) {
                    try FileManager.default.copyItem(at: srcURL, to: dstURL)
                    destReplicatedFiles += 1
                    destReplicatedBytes += file.fileSize
                } else {
                    destSkippedFiles += 1
                }

                state.processedFiles += 1
                state.replicatedBytes += file.fileSize
                onProgress?(state)
            }

            try await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "completed",
                replicatedBytes: destReplicatedBytes,
                completedAt: Date()
            )

            logger.info("Successfully replicated snapshot \(snapshot.id) to SMB NAS")
            return DestinationSyncResult(
                replicatedFiles: destReplicatedFiles,
                replicatedBytes: destReplicatedBytes,
                skippedFiles: destSkippedFiles,
                isSuccess: true
            )
        } catch {
            let errMsg = error.localizedDescription
            logger.error("Failed to replicate snapshot to SMB: \(errMsg)")
            try? await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "failed",
                replicatedBytes: 0,
                completedAt: Date(),
                errorMessage: errMsg
            )
            return DestinationSyncResult(
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                isSuccess: false
            )
        }
    }

    func replicateWebDAV(
        dest: RemoteDestination,
        webdavConfig: WebDAVConfiguration,
        snapshot: SnapshotRecord,
        snapshotRoot: URL,
        filesToSync: [FileCatalogRecord],
        profile: BackupProfile,
        throttler: BandwidthThrottler,
        state: inout ReplicationProgressState
    ) async throws -> DestinationSyncResult {
        let destId = webdavConfig.serverURL + webdavConfig.destinationPath
        _ = try await database.recordReplicationSnapshot(ReplicationSnapshotRecord(
            snapshotId: snapshot.id,
            destinationType: "webdav",
            destinationIdentifier: destId,
            status: "in_progress",
            replicatedBytes: 0,
            totalBytes: snapshot.totalBytes,
            startedAt: Date()
        ))

        do {
            let webdavProvider = RemoteStorageFactory.makeWebDAVProvider(for: dest, config: webdavConfig)
            let passphrase = RemoteStorageFactory.resolveEncryptionPassphrase(for: dest, profileId: profile.id)

            var destReplicatedFiles = 0
            var destReplicatedBytes: Int64 = 0
            let destSkippedFiles = 0

            if dest.archivePackagingEnabled || profile.copyJobConfig.archivePackagingEnabled {
                let format = ArchivePackagingEngine.shared.defaultFormat
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_WebDAV_\(UUID().uuidString)")
                let archiveURL = tempDir.appendingPathComponent("\(snapshot.id).\(format.fileExtension)")
                defer { try? FileManager.default.removeItem(at: tempDir) }

                try await ArchivePackagingEngine.shared.createArchive(
                    sourceDirectory: snapshotRoot,
                    destinationArchiveURL: archiveURL,
                    compressionLevel: dest.archiveCompressionLevel
                )

                let rawArchiveData = try Data(contentsOf: archiveURL)
                let payload: Data
                let remoteFilename: String
                if dest.isClientEncryptionEnabled {
                    payload = try ClientSideEncryptor.encrypt(data: rawArchiveData, passphrase: passphrase)
                    remoteFilename = "\(archiveURL.lastPathComponent).enc"
                } else {
                    payload = rawArchiveData
                    remoteFilename = archiveURL.lastPathComponent
                }

                try await webdavProvider.uploadFile(path: remoteFilename, data: payload)

                destReplicatedFiles = 1
                destReplicatedBytes = Int64(payload.count)
            } else {
                for file in filesToSync {
                    try Task.checkCancellation()
                    let localFileURL = snapshotRoot.appendingPathComponent(file.relativePath)
                    guard FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else { continue }
                    let rawData = try Data(contentsOf: localFileURL)
                    let payload: Data
                    let remotePath: String
                    if dest.isClientEncryptionEnabled {
                        payload = try ClientSideEncryptor.encrypt(data: rawData, passphrase: passphrase)
                        remotePath = "\(snapshot.id)/\(file.relativePath).enc"
                    } else {
                        payload = rawData
                        remotePath = "\(snapshot.id)/\(file.relativePath)"
                    }
                    await throttler.throttle(byteCount: Int64(payload.count))
                    try await webdavProvider.uploadFile(path: remotePath, data: payload)
                    destReplicatedFiles += 1
                    destReplicatedBytes += file.fileSize
                    state.processedFiles += 1
                    state.replicatedBytes += file.fileSize
                    onProgress?(state)
                }
            }

            try await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "completed",
                replicatedBytes: destReplicatedBytes,
                completedAt: Date()
            )

            logger.info("Successfully replicated snapshot \(snapshot.id) to WebDAV: \(destReplicatedFiles) files, \(destReplicatedBytes) bytes")
            return DestinationSyncResult(
                replicatedFiles: destReplicatedFiles,
                replicatedBytes: destReplicatedBytes,
                skippedFiles: destSkippedFiles,
                isSuccess: true
            )
        } catch {
            let errMsg = error.localizedDescription
            logger.error("Failed to replicate snapshot to WebDAV: \(errMsg)")
            try? await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "failed",
                replicatedBytes: 0,
                completedAt: Date(),
                errorMessage: errMsg
            )
            return DestinationSyncResult(
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                isSuccess: false
            )
        }
    }

    func replicateSFTP(
        dest: RemoteDestination,
        sftpConfig: SFTPConfiguration,
        snapshot: SnapshotRecord,
        snapshotRoot: URL,
        filesToSync: [FileCatalogRecord],
        profile: BackupProfile,
        throttler: BandwidthThrottler,
        state: inout ReplicationProgressState
    ) async throws -> DestinationSyncResult {
        let destId = "\(sftpConfig.host):\(sftpConfig.remotePath)"
        _ = try await database.recordReplicationSnapshot(ReplicationSnapshotRecord(
            snapshotId: snapshot.id,
            destinationType: "sftp",
            destinationIdentifier: destId,
            status: "in_progress",
            replicatedBytes: 0,
            totalBytes: snapshot.totalBytes,
            startedAt: Date()
        ))

        do {
            let sftpProvider = RemoteStorageFactory.makeSFTPProvider(for: dest, config: sftpConfig)
            let passphrase = RemoteStorageFactory.resolveEncryptionPassphrase(for: dest, profileId: profile.id)

            var destReplicatedFiles = 0
            var destReplicatedBytes: Int64 = 0
            let destSkippedFiles = 0

            if dest.archivePackagingEnabled || profile.copyJobConfig.archivePackagingEnabled {
                let format = ArchivePackagingEngine.shared.defaultFormat
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_SFTP_\(UUID().uuidString)")
                let archiveURL = tempDir.appendingPathComponent("\(snapshot.id).\(format.fileExtension)")
                defer { try? FileManager.default.removeItem(at: tempDir) }

                try await ArchivePackagingEngine.shared.createArchive(
                    sourceDirectory: snapshotRoot,
                    destinationArchiveURL: archiveURL,
                    compressionLevel: dest.archiveCompressionLevel
                )

                let uploadURL: URL
                if dest.isClientEncryptionEnabled {
                    let rawArchiveData = try Data(contentsOf: archiveURL)
                    let payload = try ClientSideEncryptor.encrypt(data: rawArchiveData, passphrase: passphrase)
                    let encURL = tempDir.appendingPathComponent("\(archiveURL.lastPathComponent).enc")
                    try payload.write(to: encURL)
                    uploadURL = encURL
                } else {
                    uploadURL = archiveURL
                }

                try await sftpProvider.uploadFile(localURL: uploadURL, remotePath: uploadURL.lastPathComponent)

                let fileSize = (try? FileManager.default.attributesOfItem(atPath: uploadURL.path)[.size] as? Int64) ?? 0
                destReplicatedFiles = 1
                destReplicatedBytes = fileSize
            } else {
                for file in filesToSync {
                    try Task.checkCancellation()
                    let localFileURL = snapshotRoot.appendingPathComponent(file.relativePath)
                    guard FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else { continue }
                    try await sftpProvider.uploadFile(localURL: localFileURL, remotePath: "\(snapshot.id)/\(file.relativePath)")
                    destReplicatedFiles += 1
                    destReplicatedBytes += file.fileSize
                    state.processedFiles += 1
                    state.replicatedBytes += file.fileSize
                    onProgress?(state)
                }
            }

            try await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "completed",
                replicatedBytes: destReplicatedBytes,
                completedAt: Date()
            )

            logger.info("Successfully replicated snapshot \(snapshot.id) to SFTP: \(destReplicatedFiles) files, \(destReplicatedBytes) bytes")
            return DestinationSyncResult(
                replicatedFiles: destReplicatedFiles,
                replicatedBytes: destReplicatedBytes,
                skippedFiles: destSkippedFiles,
                isSuccess: true
            )
        } catch {
            let errMsg = error.localizedDescription
            logger.error("Failed to replicate snapshot to SFTP: \(errMsg)")
            try? await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "failed",
                replicatedBytes: 0,
                completedAt: Date(),
                errorMessage: errMsg
            )
            return DestinationSyncResult(
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                isSuccess: false
            )
        }
    }
}
