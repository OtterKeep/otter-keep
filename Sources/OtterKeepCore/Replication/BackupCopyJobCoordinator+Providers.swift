import Foundation
import os
import OtterKeepStorage
import OtterKeepDatabase

// MARK: - Backend Adapters

/// S3-compatible replication sink. Also serves Backblaze B2, which reuses this code path.
struct S3ReplicationSink: ReplicationSink {
    struct Session: Sendable {
        let provider: S3StorageProvider
        let passphrase: String
    }

    let context: ReplicationContext
    let config: S3Configuration

    var destinationIdentifier: String { "s3://\(config.bucket)/\(config.pathPrefix)" }
    var destinationType: String { "s3" }
    var logName: String { "S3" }
    var supportsArchivePackaging: Bool { true }
    var archivePackagingStatusMessage: String? { "Packaging snapshot into compressed archive..." }
    var announcesCurrentFileBeforeReplication: Bool { true }

    func open() async throws -> Session {
        Session(
            provider: RemoteStorageFactory.makeS3Provider(for: context.destination, config: config),
            passphrase: RemoteStorageFactory.resolveEncryptionPassphrase(for: context.destination, profileId: context.profile.id)
        )
    }

    func replicateFile(_ file: FileCatalogRecord, session: Session) async throws -> ReplicationUnitOutcome {
        let destId = destinationIdentifier
        let (alreadySynced, existingKey, existingETag) = try await context.database.isReplicationFileSynced(
            destinationIdentifier: destId,
            relativePath: file.relativePath,
            checksum: file.checksum,
            fileSize: file.fileSize
        )

        if alreadySynced, let key = existingKey {
            return .reusedFile(record: ReplicationFileRecord(
                snapshotId: context.snapshot.id,
                destinationIdentifier: destId,
                relativePath: file.relativePath,
                remoteKey: key,
                remoteETag: existingETag,
                checksum: file.checksum,
                fileSize: file.fileSize,
                status: "reused"
            ))
        }

        let localFileURL = context.snapshotRoot.appendingPathComponent(file.relativePath)
        guard FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else {
            return .ignored
        }

        let rawData = try Data(contentsOf: localFileURL)
        let payload: Data
        let objectKey: String
        if context.destination.isClientEncryptionEnabled {
            payload = try ClientSideEncryptor.encrypt(data: rawData, passphrase: session.passphrase)
            objectKey = "\(context.snapshot.id)/\(file.relativePath).enc"
        } else {
            payload = rawData
            objectKey = "\(context.snapshot.id)/\(file.relativePath)"
        }

        await context.throttler.throttle(byteCount: Int64(payload.count))
        let etag = try await upload(payload, objectKey: objectKey, session: session)

        return .replicatedFile(bytes: file.fileSize, record: ReplicationFileRecord(
            snapshotId: context.snapshot.id,
            destinationIdentifier: destId,
            relativePath: file.relativePath,
            remoteKey: objectKey,
            remoteETag: etag,
            checksum: file.checksum,
            fileSize: file.fileSize,
            status: "replicated"
        ))
    }

    func replicateArchive(session: Session) async throws -> ReplicationUnitOutcome {
        let snapshot = context.snapshot
        let format = ArchivePackagingEngine.shared.defaultFormat
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_Arch_\(UUID().uuidString)")
        let archiveURL = tempDir.appendingPathComponent("\(snapshot.id).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await ArchivePackagingEngine.shared.createArchive(
            sourceDirectory: context.snapshotRoot,
            destinationArchiveURL: archiveURL,
            compressionLevel: context.destination.archiveCompressionLevel
        )

        let rawData = try Data(contentsOf: archiveURL)
        let payload: Data
        let objectKey: String
        if context.destination.isClientEncryptionEnabled {
            payload = try ClientSideEncryptor.encrypt(data: rawData, passphrase: session.passphrase)
            objectKey = "\(snapshot.id)/\(archiveURL.lastPathComponent).enc"
        } else {
            payload = rawData
            objectKey = "\(snapshot.id)/\(archiveURL.lastPathComponent)"
        }

        await context.throttler.throttle(byteCount: Int64(payload.count))
        let etag = try await upload(payload, objectKey: objectKey, session: session)

        return ReplicationUnitOutcome(
            replicatedFiles: 1,
            replicatedBytes: Int64(payload.count),
            processedFilesDelta: context.filesToSync.count,
            progressBytesDelta: Int64(payload.count),
            emitProgress: true,
            fileRecord: ReplicationFileRecord(
                snapshotId: snapshot.id,
                destinationIdentifier: destinationIdentifier,
                relativePath: archiveURL.lastPathComponent,
                remoteKey: objectKey,
                remoteETag: etag,
                checksum: try? ChecksumCalculator.computeSHA256(for: archiveURL),
                fileSize: Int64(payload.count),
                status: "replicated"
            )
        )
    }

    /// Uploads an object, switching to a 5 MB chunked multipart upload above the 8 MB single-PUT threshold.
    private func upload(_ payload: Data, objectKey: String, session: Session) async throws -> String {
        if payload.count > 8 * 1024 * 1024 {
            let uploadId = try await session.provider.initiateMultipartUpload(key: objectKey)
            var parts: [(partNumber: Int, etag: String)] = []
            let chunkSize = 5 * 1024 * 1024
            var offset = 0
            var partNumber = 1

            while offset < payload.count {
                try Task.checkCancellation()
                let length = min(chunkSize, payload.count - offset)
                let chunkData = payload.subdata(in: offset..<(offset + length))
                await context.throttler.throttle(byteCount: Int64(chunkData.count))
                let partETag = try await session.provider.uploadPart(key: objectKey, uploadId: uploadId, partNumber: partNumber, data: chunkData)
                parts.append((partNumber: partNumber, etag: partETag))
                offset += length
                partNumber += 1
            }
            try await session.provider.completeMultipartUpload(key: objectKey, uploadId: uploadId, parts: parts)
            return parts.first?.etag ?? ""
        }
        return try await session.provider.putObject(key: objectKey, data: payload)
    }
}

/// SMB/NFS network share replication sink (mounted-share copy semantics; no archive packaging).
struct SMBReplicationSink: ReplicationSink {
    struct Session: Sendable {
        let targetDirectory: URL
    }

    let context: ReplicationContext
    let config: NetworkShareConfiguration

    var destinationIdentifier: String { config.shareURL }
    var destinationType: String { "smb" }
    var logName: String { "SMB" }
    var successLogTarget: String { "SMB NAS" }
    var successLogIncludesCounts: Bool { false }

    func open() async throws -> Session {
        let (mountPoint, resolvedSubpath) = try await RemoteStorageFactory.mountNetworkShare(for: context.destination, config: config)
        let targetDir = mountPoint.appendingPathComponent(resolvedSubpath).appendingPathComponent(context.snapshot.snapshotPath)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        return Session(targetDirectory: targetDir)
    }

    func replicateFile(_ file: FileCatalogRecord, session: Session) async throws -> ReplicationUnitOutcome {
        let srcURL = context.snapshotRoot.appendingPathComponent(file.relativePath)
        let dstURL = session.targetDirectory.appendingPathComponent("root").appendingPathComponent(file.relativePath)
        try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: dstURL.path(percentEncoded: false)) {
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            return .replicatedFile(bytes: file.fileSize)
        }
        return .skippedFile(bytes: file.fileSize)
    }
}

/// WebDAV replication sink.
struct WebDAVReplicationSink: ReplicationSink {
    struct Session: Sendable {
        let provider: WebDAVStorageProvider
        let passphrase: String
    }

    let context: ReplicationContext
    let config: WebDAVConfiguration

    var destinationIdentifier: String { config.serverURL + config.destinationPath }
    var destinationType: String { "webdav" }
    var logName: String { "WebDAV" }
    var supportsArchivePackaging: Bool { true }

    func open() async throws -> Session {
        Session(
            provider: RemoteStorageFactory.makeWebDAVProvider(for: context.destination, config: config),
            passphrase: RemoteStorageFactory.resolveEncryptionPassphrase(for: context.destination, profileId: context.profile.id)
        )
    }

    func replicateFile(_ file: FileCatalogRecord, session: Session) async throws -> ReplicationUnitOutcome {
        let localFileURL = context.snapshotRoot.appendingPathComponent(file.relativePath)
        guard FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else {
            return .ignored
        }

        let rawData = try Data(contentsOf: localFileURL)
        let payload: Data
        let remotePath: String
        if context.destination.isClientEncryptionEnabled {
            payload = try ClientSideEncryptor.encrypt(data: rawData, passphrase: session.passphrase)
            remotePath = "\(context.snapshot.id)/\(file.relativePath).enc"
        } else {
            payload = rawData
            remotePath = "\(context.snapshot.id)/\(file.relativePath)"
        }

        await context.throttler.throttle(byteCount: Int64(payload.count))
        try await session.provider.uploadFile(path: remotePath, data: payload)
        return .replicatedFile(bytes: file.fileSize)
    }

    func replicateArchive(session: Session) async throws -> ReplicationUnitOutcome {
        let snapshot = context.snapshot
        let format = ArchivePackagingEngine.shared.defaultFormat
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_WebDAV_\(UUID().uuidString)")
        let archiveURL = tempDir.appendingPathComponent("\(snapshot.id).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await ArchivePackagingEngine.shared.createArchive(
            sourceDirectory: context.snapshotRoot,
            destinationArchiveURL: archiveURL,
            compressionLevel: context.destination.archiveCompressionLevel
        )

        let rawArchiveData = try Data(contentsOf: archiveURL)
        let payload: Data
        let remoteFilename: String
        if context.destination.isClientEncryptionEnabled {
            payload = try ClientSideEncryptor.encrypt(data: rawArchiveData, passphrase: session.passphrase)
            remoteFilename = "\(archiveURL.lastPathComponent).enc"
        } else {
            payload = rawArchiveData
            remoteFilename = archiveURL.lastPathComponent
        }

        try await session.provider.uploadFile(path: remoteFilename, data: payload)

        return ReplicationUnitOutcome(replicatedFiles: 1, replicatedBytes: Int64(payload.count))
    }
}

/// SFTP replication sink.
struct SFTPReplicationSink: ReplicationSink {
    struct Session: Sendable {
        let provider: SFTPStorageProvider
        let passphrase: String
    }

    let context: ReplicationContext
    let config: SFTPConfiguration

    var destinationIdentifier: String { "\(config.host):\(config.remotePath)" }
    var destinationType: String { "sftp" }
    var logName: String { "SFTP" }
    var supportsArchivePackaging: Bool { true }

    func open() async throws -> Session {
        Session(
            provider: RemoteStorageFactory.makeSFTPProvider(for: context.destination, config: config),
            passphrase: RemoteStorageFactory.resolveEncryptionPassphrase(for: context.destination, profileId: context.profile.id)
        )
    }

    func replicateFile(_ file: FileCatalogRecord, session: Session) async throws -> ReplicationUnitOutcome {
        let localFileURL = context.snapshotRoot.appendingPathComponent(file.relativePath)
        guard FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else {
            return .ignored
        }

        try await session.provider.uploadFile(localURL: localFileURL, remotePath: "\(context.snapshot.id)/\(file.relativePath)")
        return .replicatedFile(bytes: file.fileSize)
    }

    func replicateArchive(session: Session) async throws -> ReplicationUnitOutcome {
        let snapshot = context.snapshot
        let format = ArchivePackagingEngine.shared.defaultFormat
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_SFTP_\(UUID().uuidString)")
        let archiveURL = tempDir.appendingPathComponent("\(snapshot.id).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await ArchivePackagingEngine.shared.createArchive(
            sourceDirectory: context.snapshotRoot,
            destinationArchiveURL: archiveURL,
            compressionLevel: context.destination.archiveCompressionLevel
        )

        let uploadURL: URL
        if context.destination.isClientEncryptionEnabled {
            let rawArchiveData = try Data(contentsOf: archiveURL)
            let payload = try ClientSideEncryptor.encrypt(data: rawArchiveData, passphrase: session.passphrase)
            let encURL = tempDir.appendingPathComponent("\(archiveURL.lastPathComponent).enc")
            try payload.write(to: encURL)
            uploadURL = encURL
        } else {
            uploadURL = archiveURL
        }

        try await session.provider.uploadFile(localURL: uploadURL, remotePath: uploadURL.lastPathComponent)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: uploadURL.path)[.size] as? Int64) ?? 0
        return ReplicationUnitOutcome(replicatedFiles: 1, replicatedBytes: fileSize)
    }
}

extension BackupCopyJobCoordinator {
    // MARK: - Thin Protocol-Specific Adapters

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
        let sink = S3ReplicationSink(
            context: replicationContext(
                dest: dest,
                snapshot: snapshot,
                snapshotRoot: snapshotRoot,
                filesToSync: filesToSync,
                profile: profile,
                throttler: throttler
            ),
            config: s3Config
        )
        return try await executeReplicationPipeline(sink, state: &state)
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
        let sink = SMBReplicationSink(
            context: replicationContext(
                dest: dest,
                snapshot: snapshot,
                snapshotRoot: snapshotRoot,
                filesToSync: filesToSync,
                profile: profile,
                throttler: throttler
            ),
            config: smbConfig
        )
        return try await executeReplicationPipeline(sink, state: &state)
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
        let sink = WebDAVReplicationSink(
            context: replicationContext(
                dest: dest,
                snapshot: snapshot,
                snapshotRoot: snapshotRoot,
                filesToSync: filesToSync,
                profile: profile,
                throttler: throttler
            ),
            config: webdavConfig
        )
        return try await executeReplicationPipeline(sink, state: &state)
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
        let sink = SFTPReplicationSink(
            context: replicationContext(
                dest: dest,
                snapshot: snapshot,
                snapshotRoot: snapshotRoot,
                filesToSync: filesToSync,
                profile: profile,
                throttler: throttler
            ),
            config: sftpConfig
        )
        return try await executeReplicationPipeline(sink, state: &state)
    }

    private func replicationContext(
        dest: RemoteDestination,
        snapshot: SnapshotRecord,
        snapshotRoot: URL,
        filesToSync: [FileCatalogRecord],
        profile: BackupProfile,
        throttler: BandwidthThrottler
    ) -> ReplicationContext {
        ReplicationContext(
            destination: dest,
            profile: profile,
            snapshot: snapshot,
            snapshotRoot: snapshotRoot,
            filesToSync: filesToSync,
            throttler: throttler,
            database: database
        )
    }
}
