import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension AppState {
    // MARK: - 3-2-1 Compliance & Replication Controls

    public typealias Rule321Compliance = OtterKeepCore.Rule321Compliance

    public var rule321Compliance: Rule321Compliance {
        guard let profile = selectedProfile else {
            return .localOnly(description: L10n.t(.rule321StatusLocalOnly))
        }
        return ComplianceEvaluator.evaluate(profile: profile).rule321Status
    }

    public func startReplication(for profile: BackupProfile? = nil) {
        guard let prof = profile ?? selectedProfile else { return }
        guard !isReplicationRunning else { return }

        isReplicationRunning = true
        replicationProgressState = ReplicationProgressState(
            isRunning: true,
            statusMessage: "Starting 3-2-1 replication..."
        )
        let localStorage = self.storage
        let localDatabase = self.database

        Task { [weak self] in
            guard let self = self else { return }
            let copyCoordinator = BackupCopyJobCoordinator(storage: localStorage, database: localDatabase)
            await copyCoordinator.setProgressHandler { [weak self] state in
                Task { @MainActor in
                    self?.replicationProgressState = state
                }
            }

            do {
                let summary = try await copyCoordinator.executeReplication(profile: prof)
                await MainActor.run {
                    self.lastReplicationSummary = summary
                    self.isReplicationRunning = false
                    self.refreshLogs()
                }
            } catch {
                await MainActor.run {
                    self.isReplicationRunning = false
                    self.showError("3-2-1 Replication Error: \(error.localizedDescription)")
                    self.refreshLogs()
                }
            }
        }
    }

    public func openDestinationEditor(destination: RemoteDestination?) {
        destinationEditorTestSuccessMessage = nil
        destinationEditorTestErrorMessage = nil
        destinationEditorIsTesting = false
        if let dest = destination {
            destinationEditorTargetId = dest.id
            destinationEditorName = dest.name
            destinationEditorIsClientEncryptionEnabled = dest.isClientEncryptionEnabled
            destinationEditorIsEnabled = dest.isEnabled
            destinationEditorArchivePackagingEnabled = dest.archivePackagingEnabled
            destinationEditorArchiveCompressionLevel = dest.archiveCompressionLevel
            switch dest.type {
            case .s3(let cfg):
                destinationEditorTypeIndex = 0
                destinationEditorS3Endpoint = cfg.endpoint
                destinationEditorS3Bucket = cfg.bucket
                destinationEditorS3Region = cfg.region
                destinationEditorS3AccessKeyId = cfg.accessKeyId
                destinationEditorS3PathPrefix = cfg.pathPrefix
                destinationEditorS3ForcePathStyle = cfg.forcePathStyle
                destinationEditorS3SecretAccessKey = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
            case .smb(let cfg):
                destinationEditorTypeIndex = 1
                destinationEditorSmbShareURL = cfg.shareURL
                destinationEditorSmbMountPath = cfg.subfolder
                destinationEditorSmbUsername = cfg.username
                destinationEditorSmbPassword = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
            case .webdav(let cfg):
                destinationEditorTypeIndex = 2
                destinationEditorWebDAVURL = cfg.serverURL
                destinationEditorWebDAVPath = cfg.destinationPath
                destinationEditorWebDAVUsername = cfg.username
                destinationEditorWebDAVPassword = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
            case .sftp(let cfg):
                destinationEditorTypeIndex = 3
                destinationEditorSFTPHost = cfg.host
                destinationEditorSFTPPort = cfg.port
                destinationEditorSFTPUsername = cfg.username
                destinationEditorSFTPPath = cfg.remotePath
                let sec = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
                destinationEditorSFTPPasswordOrKey = sec
                destinationEditorSFTPAuthModeIndex = (sec.hasPrefix("/") || sec.hasPrefix("~")) ? 1 : 0
            case .backblazeB2(let cfg):
                destinationEditorTypeIndex = 4
                destinationEditorB2KeyId = cfg.keyId
                destinationEditorB2BucketName = cfg.bucketName
                destinationEditorB2Region = cfg.region
                destinationEditorB2CustomEndpoint = cfg.customEndpoint ?? ""
                destinationEditorB2PathPrefix = cfg.pathPrefix
                destinationEditorB2AppKey = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
            }
        } else {
            destinationEditorTargetId = nil
            destinationEditorName = L10n.t(.remoteS3Title)
            destinationEditorTypeIndex = 0
            destinationEditorS3Endpoint = "https://s3.amazonaws.com"
            destinationEditorS3Bucket = ""
            destinationEditorS3Region = "eu-central-1"
            destinationEditorS3AccessKeyId = ""
            destinationEditorS3SecretAccessKey = ""
            destinationEditorS3PathPrefix = "otterkeep"
            destinationEditorS3ForcePathStyle = true
            destinationEditorSmbShareURL = "smb://nas.local/backups"
            destinationEditorSmbMountPath = ""
            destinationEditorSmbUsername = ""
            destinationEditorSmbPassword = ""
            destinationEditorWebDAVURL = "https://nas.local:5006"
            destinationEditorWebDAVPath = "/backups"
            destinationEditorWebDAVUsername = ""
            destinationEditorWebDAVPassword = ""
            destinationEditorSFTPHost = "nas.local"
            destinationEditorSFTPPort = 22
            destinationEditorSFTPUsername = ""
            destinationEditorSFTPPasswordOrKey = ""
            destinationEditorSFTPAuthModeIndex = 0
            destinationEditorSFTPPath = "/var/backups/otterkeep"
            destinationEditorArchivePackagingEnabled = false
            destinationEditorArchiveCompressionLevel = 3
            destinationEditorIsClientEncryptionEnabled = true
            destinationEditorIsEnabled = true
        }
        showRemoteDestinationEditorSheet = true
    }

    public func saveDestinationEditor() {
        guard var profile = selectedProfile else { return }
        let destId = destinationEditorTargetId ?? UUID()
        let finalType: RemoteDestinationType

        let account: String
        if destinationEditorTypeIndex == 0 {
            let s3Config = S3Configuration(
                endpoint: destinationEditorS3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                bucket: destinationEditorS3Bucket.trimmingCharacters(in: .whitespacesAndNewlines),
                region: destinationEditorS3Region.trimmingCharacters(in: .whitespacesAndNewlines),
                accessKeyId: destinationEditorS3AccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
                pathPrefix: destinationEditorS3PathPrefix.trimmingCharacters(in: .whitespacesAndNewlines),
                forcePathStyle: destinationEditorS3ForcePathStyle
            )
            finalType = .s3(s3Config)

            account = "s3_\(destId.uuidString)"
            if !destinationEditorS3SecretAccessKey.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorS3SecretAccessKey, for: account)
            }
        } else if destinationEditorTypeIndex == 1 {
            let smbConfig = NetworkShareConfiguration(
                shareURL: destinationEditorSmbShareURL.trimmingCharacters(in: .whitespacesAndNewlines),
                username: destinationEditorSmbUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                subfolder: destinationEditorSmbMountPath.trimmingCharacters(in: .whitespacesAndNewlines),
                useSparsebundle: false
            )
            finalType = .smb(smbConfig)

            account = "smb_\(destId.uuidString)"
            if !destinationEditorSmbPassword.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorSmbPassword, for: account)
            }
        } else if destinationEditorTypeIndex == 2 {
            let urlString = destinationEditorWebDAVURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let webdavConfig = WebDAVConfiguration(
                serverURL: urlString,
                destinationPath: destinationEditorWebDAVPath.trimmingCharacters(in: .whitespacesAndNewlines),
                username: destinationEditorWebDAVUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                useSSL: urlString.lowercased().hasPrefix("https")
            )
            finalType = .webdav(webdavConfig)

            account = "webdav_\(destId.uuidString)"
            if !destinationEditorWebDAVPassword.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorWebDAVPassword, for: account)
            }
        } else if destinationEditorTypeIndex == 3 {
            let auth: SFTPAuthMethod
            let secret = destinationEditorSFTPPasswordOrKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if secret.hasPrefix("/") || secret.hasPrefix("~") || FileManager.default.fileExists(atPath: secret) {
                auth = .privateKey(keyPath: secret)
            } else {
                auth = .password
            }
            let sftpConfig = SFTPConfiguration(
                host: destinationEditorSFTPHost.trimmingCharacters(in: .whitespacesAndNewlines),
                port: destinationEditorSFTPPort,
                username: destinationEditorSFTPUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                remotePath: destinationEditorSFTPPath.trimmingCharacters(in: .whitespacesAndNewlines),
                authMethod: auth
            )
            finalType = .sftp(sftpConfig)

            account = "sftp_\(destId.uuidString)"
            if !destinationEditorSFTPPasswordOrKey.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorSFTPPasswordOrKey, for: account)
            }
        } else {
            let b2Config = B2Configuration(
                keyId: destinationEditorB2KeyId.trimmingCharacters(in: .whitespacesAndNewlines),
                bucketName: destinationEditorB2BucketName.trimmingCharacters(in: .whitespacesAndNewlines),
                region: destinationEditorB2Region.trimmingCharacters(in: .whitespacesAndNewlines),
                customEndpoint: destinationEditorB2CustomEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : destinationEditorB2CustomEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                pathPrefix: destinationEditorB2PathPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            finalType = .backblazeB2(b2Config)

            account = "b2_\(destId.uuidString)"
            if !destinationEditorB2AppKey.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorB2AppKey, for: account)
            }
        }

        let updatedDestination = RemoteDestination(
            id: destId,
            name: destinationEditorName.trimmingCharacters(in: .whitespacesAndNewlines),
            type: finalType,
            isClientEncryptionEnabled: destinationEditorIsClientEncryptionEnabled,
            keychainAccount: account,
            isEnabled: destinationEditorIsEnabled,
            archivePackagingEnabled: destinationEditorArchivePackagingEnabled,
            archiveCompressionLevel: destinationEditorArchiveCompressionLevel
        )

        if let idx = profile.copyJobConfig.destinations.firstIndex(where: { $0.id == destId }) {
            profile.copyJobConfig.destinations[idx] = updatedDestination
        } else {
            profile.copyJobConfig.destinations.append(updatedDestination)
        }

        selectedProfile = profile
        if let pIdx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[pIdx] = profile
        }
        saveProfiles()
        showRemoteDestinationEditorSheet = false
    }

    public func deleteDestinationEditor(destinationId: UUID) {
        guard var profile = selectedProfile else { return }
        profile.copyJobConfig.destinations.removeAll(where: { $0.id == destinationId })
        KeychainManager.deleteSecret(for: "s3_\(destinationId.uuidString)")
        KeychainManager.deleteSecret(for: "smb_\(destinationId.uuidString)")
        KeychainManager.deleteSecret(for: "webdav_\(destinationId.uuidString)")
        KeychainManager.deleteSecret(for: "sftp_\(destinationId.uuidString)")
        KeychainManager.deleteSecret(for: "b2_\(destinationId.uuidString)")
        selectedProfile = profile
        if let pIdx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[pIdx] = profile
        }
        saveProfiles()
        showRemoteDestinationEditorSheet = false
    }

    public func testDestinationEditorConnection() {
        destinationEditorIsTesting = true
        destinationEditorTestSuccessMessage = nil
        destinationEditorTestErrorMessage = nil

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.destinationEditorTypeIndex == 0 {
                let config = S3Configuration(
                    endpoint: self.destinationEditorS3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                    bucket: self.destinationEditorS3Bucket.trimmingCharacters(in: .whitespacesAndNewlines),
                    region: self.destinationEditorS3Region.trimmingCharacters(in: .whitespacesAndNewlines),
                    accessKeyId: self.destinationEditorS3AccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
                    pathPrefix: self.destinationEditorS3PathPrefix.trimmingCharacters(in: .whitespacesAndNewlines),
                    forcePathStyle: self.destinationEditorS3ForcePathStyle
                )
                let provider = S3StorageProvider(config: config, secretAccessKey: self.destinationEditorS3SecretAccessKey)
                do {
                    _ = try await provider.testConnection()
                    self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessS3Format, config.bucket)
                } catch {
                    self.destinationEditorTestErrorMessage = L10n.format(.s3ConnectionErrorFormat, error.localizedDescription)
                }
            } else if self.destinationEditorTypeIndex == 1 {
                let shareTrimmed = self.destinationEditorSmbShareURL.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    let components = try NetworkShareMounter.parseShareURL(shareTrimmed)
                    guard !components.host.isEmpty else {
                        self.destinationEditorTestErrorMessage = L10n.t(.testConnectionMissingSMBHost)
                        self.destinationEditorIsTesting = false
                        return
                    }

                    if !NetworkReachability.shared.isConnected {
                        self.destinationEditorTestErrorMessage = L10n.t(.testConnectionNoNetwork)
                        self.destinationEditorIsTesting = false
                        return
                    }

                    let portReachable = NetworkShareMounter.testTCPPort(host: components.host, port: 445, timeoutSeconds: 3.0)
                    if portReachable {
                        self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessSMBFormat, components.host)
                    } else {
                        self.destinationEditorTestErrorMessage = "A NAS szerver ('\(components.host)') nem érhető el a 445-ös (SMB) porton."
                    }
                } catch {
                    self.destinationEditorTestErrorMessage = error.localizedDescription
                }
            } else if self.destinationEditorTypeIndex == 2 {
                let urlString = self.destinationEditorWebDAVURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let base = URL(string: urlString), base.scheme != nil else {
                    self.destinationEditorTestErrorMessage = "Érvénytelen WebDAV URL cím."
                    self.destinationEditorIsTesting = false
                    return
                }
                let config = WebDAVConfiguration(
                    serverURL: urlString,
                    destinationPath: self.destinationEditorWebDAVPath.trimmingCharacters(in: .whitespacesAndNewlines),
                    username: self.destinationEditorWebDAVUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    useSSL: urlString.lowercased().hasPrefix("https")
                )
                let provider = WebDAVStorageProvider(config: config, password: self.destinationEditorWebDAVPassword)
                do {
                    _ = try await provider.testConnection()
                    self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessWebDAVFormat, urlString)
                } catch {
                    self.destinationEditorTestErrorMessage = error.localizedDescription
                }
            } else if self.destinationEditorTypeIndex == 3 {
                let host = self.destinationEditorSFTPHost.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !host.isEmpty else {
                    self.destinationEditorTestErrorMessage = "A megadott SFTP szerver cím érvénytelen."
                    self.destinationEditorIsTesting = false
                    return
                }
                let secret = self.destinationEditorSFTPPasswordOrKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let auth: SFTPAuthMethod
                if secret.hasPrefix("/") || secret.hasPrefix("~") || FileManager.default.fileExists(atPath: secret) {
                    auth = .privateKey(keyPath: secret)
                } else {
                    auth = .password
                }
                let config = SFTPConfiguration(
                    host: host,
                    port: self.destinationEditorSFTPPort,
                    username: self.destinationEditorSFTPUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    remotePath: self.destinationEditorSFTPPath.trimmingCharacters(in: .whitespacesAndNewlines),
                    authMethod: auth
                )
                let provider = SFTPStorageProvider(config: config)
                do {
                    _ = try await provider.testConnection()
                    self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessSFTPFormat, host)
                } catch {
                    self.destinationEditorTestErrorMessage = error.localizedDescription
                }
            } else {
                let config = B2Configuration(
                    keyId: self.destinationEditorB2KeyId.trimmingCharacters(in: .whitespacesAndNewlines),
                    bucketName: self.destinationEditorB2BucketName.trimmingCharacters(in: .whitespacesAndNewlines),
                    region: self.destinationEditorB2Region.trimmingCharacters(in: .whitespacesAndNewlines),
                    customEndpoint: self.destinationEditorB2CustomEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self.destinationEditorB2CustomEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                    pathPrefix: self.destinationEditorB2PathPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let provider = B2StorageProvider(config: config, applicationKey: self.destinationEditorB2AppKey)
                do {
                    _ = try await provider.testConnection()
                    self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessS3Format, config.bucketName)
                } catch {
                    self.destinationEditorTestErrorMessage = L10n.format(.s3ConnectionErrorFormat, error.localizedDescription)
                }
            }
            self.destinationEditorIsTesting = false
        }
    }


}
