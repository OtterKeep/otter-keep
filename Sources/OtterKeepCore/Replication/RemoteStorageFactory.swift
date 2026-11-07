import Foundation
import OtterKeepDomain
import OtterKeepStorage

/// Isolated factory and credential resolution boundary for remote storage providers.
/// Encapsulates Keychain secret access to prevent sensitive taint propagation into application log sinks.
public enum RemoteStorageFactory {

    /// Instantiates an authenticated `S3StorageProvider` for the given destination configuration.
    /// - Parameters:
    ///   - destination: The remote destination model containing the keychain account identifier.
    ///   - config: S3 connection and bucket configuration.
    /// - Returns: Initialized `S3StorageProvider` instance.
    public static func makeS3Provider(
        for destination: RemoteDestination,
        config: S3Configuration
    ) -> S3StorageProvider {
        let secretKey = KeychainManager.getSecret(for: destination.keychainAccount) ?? ""
        return S3StorageProvider(config: config, secretAccessKey: secretKey)
    }

    /// Instantiates an authenticated `B2StorageProvider` for the given destination configuration.
    /// - Parameters:
    ///   - destination: The remote destination model containing the keychain account identifier.
    ///   - config: Backblaze B2 connection and bucket configuration.
    /// - Returns: Initialized `B2StorageProvider` instance.
    public static func makeB2Provider(
        for destination: RemoteDestination,
        config: B2Configuration
    ) -> B2StorageProvider {
        let appKey = KeychainManager.getSecret(for: destination.keychainAccount) ?? ""
        return B2StorageProvider(config: config, applicationKey: appKey)
    }

    /// Instantiates an authenticated `SFTPStorageProvider` for the given destination configuration.
    /// - Parameters:
    ///   - destination: The remote destination model containing the keychain account identifier.
    ///   - config: SFTP connection and SSH configuration.
    /// - Returns: Initialized `SFTPStorageProvider` instance.
    public static func makeSFTPProvider(
        for destination: RemoteDestination,
        config: SFTPConfiguration
    ) -> SFTPStorageProvider {
        let password = KeychainManager.getSecret(for: destination.keychainAccount)
        return SFTPStorageProvider(config: config, password: password)
    }

    /// Instantiates an authenticated `WebDAVStorageProvider` for the given destination configuration.
    /// - Parameters:
    ///   - destination: The remote destination model containing the keychain account identifier.
    ///   - config: WebDAV server and path configuration.
    /// - Returns: Initialized `WebDAVStorageProvider` instance.
    public static func makeWebDAVProvider(
        for destination: RemoteDestination,
        config: WebDAVConfiguration
    ) -> WebDAVStorageProvider {
        let password = KeychainManager.getSecret(for: destination.keychainAccount)
        return WebDAVStorageProvider(config: config, password: password)
    }

    /// Mounts an SMB/NFS network share and returns the local mount point URL and subpath.
    /// - Parameters:
    ///   - destination: The remote destination model containing the keychain account identifier.
    ///   - config: Network share configuration.
    /// - Returns: Tuple containing the local mount point URL and resolved subpath.
    public static func mountNetworkShare(
        for destination: RemoteDestination,
        config: NetworkShareConfiguration
    ) async throws -> (mountPoint: URL, resolvedSubpath: String) {
        if config.shareURL.hasPrefix("file://") || config.shareURL.hasPrefix("/") {
            let localPath = config.shareURL.replacingOccurrences(of: "file://", with: "")
            let mountPoint = URL(fileURLWithPath: localPath)
            let resolvedSubpath = config.subfolder.isEmpty ? "OtterKeep_Backups" : config.subfolder
            return (mountPoint, resolvedSubpath)
        }

        let password = KeychainManager.getSecret(for: destination.keychainAccount)
        let mounter = NetworkShareMounter()
        let result = try await mounter.mountShare(config: config, password: password)
        return (result.mountPoint, result.resolvedSubpath)
    }

    /// Resolves the encryption passphrase for client-side encrypted replication or restoration.
    /// - Parameters:
    ///   - destination: The remote destination model.
    ///   - profileId: The associated backup profile UUID.
    ///   - explicitPassphrase: An optional explicit passphrase provided by the user (overriding stored secrets).
    /// - Returns: The resolved passphrase string.
    public static func resolveEncryptionPassphrase(
        for destination: RemoteDestination,
        profileId: UUID,
        explicitPassphrase: String? = nil
    ) -> String {
        if let explicit = explicitPassphrase, !explicit.isEmpty {
            return explicit
        }
        return KeychainManager.getPassphrase(for: profileId)
            ?? KeychainManager.getSecret(for: destination.keychainAccount)
            ?? "OtterKeepDefaultCloudSecret"
    }
}
