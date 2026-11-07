import Foundation
import OtterKeepApplication
import OtterKeepDomain

/// Storage-layer adapter probing remote destinations through the concrete provider implementations.
public struct RemoteDestinationProbe: RemoteDestinationProbing {
    /// Creates a new probe adapter.
    public init() {}

    public func probeS3(configuration: S3Configuration, secretAccessKey: String) async -> RemoteDestinationProbeResult {
        let provider = S3StorageProvider(config: configuration, secretAccessKey: secretAccessKey)
        do {
            _ = try await provider.testConnection()
            return .success(.s3Bucket(configuration.bucket))
        } catch {
            return .failure(.underlying(error.localizedDescription))
        }
    }

    public func probeB2(configuration: B2Configuration, applicationKey: String) async -> RemoteDestinationProbeResult {
        let provider = B2StorageProvider(config: configuration, applicationKey: applicationKey)
        do {
            _ = try await provider.testConnection()
            return .success(.b2Bucket(configuration.bucketName))
        } catch {
            return .failure(.underlying(error.localizedDescription))
        }
    }

    public func probeNetworkShare(configuration: NetworkShareConfiguration) async -> RemoteDestinationProbeResult {
        let shareTrimmed = configuration.shareURL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let components = try NetworkShareMounter.parseShareURL(shareTrimmed)
            guard !components.host.isEmpty else {
                return .failure(.missingSMBHost)
            }
            guard NetworkReachability.shared.isConnected else {
                return .failure(.noNetwork)
            }
            let portReachable = NetworkShareMounter.testTCPPort(host: components.host, port: 445, timeoutSeconds: 3.0)
            guard portReachable else {
                return .failure(.smbPortUnreachable(components.host))
            }
            return .success(.networkShareHost(components.host))
        } catch {
            return .failure(.underlying(error.localizedDescription))
        }
    }

    public func probeWebDAV(configuration: WebDAVConfiguration, password: String) async -> RemoteDestinationProbeResult {
        let urlString = configuration.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: urlString), base.scheme != nil else {
            return .failure(.invalidWebDAVURL)
        }
        let provider = WebDAVStorageProvider(config: configuration, password: password)
        do {
            _ = try await provider.testConnection()
            return .success(.webDAVEndpoint(urlString))
        } catch {
            return .failure(.underlying(error.localizedDescription))
        }
    }

    public func probeSFTP(configuration: SFTPConfiguration, secret: String) async -> RemoteDestinationProbeResult {
        let host = configuration.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return .failure(.invalidSFTPHost)
        }
        let provider = SFTPStorageProvider(config: configuration, password: secret.isEmpty ? nil : secret)
        do {
            _ = try await provider.testConnection()
            return .success(.sftpHost(host))
        } catch {
            return .failure(.underlying(error.localizedDescription))
        }
    }
}
