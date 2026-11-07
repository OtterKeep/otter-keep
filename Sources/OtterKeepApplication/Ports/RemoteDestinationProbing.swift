import Foundation
import OtterKeepDomain

/// Semantic success outcome of probing a remote destination.
public enum RemoteProbeSuccess: Sendable, Equatable {
    /// An S3-compatible bucket was reachable and credentials were accepted.
    case s3Bucket(String)
    /// A Backblaze B2 bucket was reachable and credentials were accepted.
    case b2Bucket(String)
    /// A network share host responded on the SMB port.
    case networkShareHost(String)
    /// A WebDAV endpoint was reachable and credentials were accepted.
    case webDAVEndpoint(String)
    /// An SFTP endpoint was reachable and credentials were accepted.
    case sftpHost(String)
}

/// Semantic failure outcome of probing a remote destination.
public enum RemoteProbeFailure: Sendable, Equatable {
    /// The SMB share URL did not contain a host component.
    case missingSMBHost
    /// No active network path is available.
    case noNetwork
    /// The SMB host did not respond on TCP port 445.
    case smbPortUnreachable(String)
    /// The WebDAV server URL is not a valid absolute URL.
    case invalidWebDAVURL
    /// The SFTP host field was empty.
    case invalidSFTPHost
    /// The underlying provider reported an error.
    case underlying(String)
}

/// Outcome of probing a remote destination's connectivity and credentials.
public enum RemoteDestinationProbeResult: Sendable, Equatable {
    /// The probe succeeded.
    case success(RemoteProbeSuccess)
    /// The probe failed.
    case failure(RemoteProbeFailure)

    /// Indicates whether the probe succeeded.
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Port probing remote storage destinations (S3, B2, SMB, WebDAV, SFTP) for reachability and credentials.
public protocol RemoteDestinationProbing: Sendable {
    /// Probes an S3-compatible bucket with the supplied secret access key.
    func probeS3(configuration: S3Configuration, secretAccessKey: String) async -> RemoteDestinationProbeResult

    /// Probes a Backblaze B2 bucket with the supplied application key.
    func probeB2(configuration: B2Configuration, applicationKey: String) async -> RemoteDestinationProbeResult

    /// Probes an SMB / NFS network share for host resolution and TCP port 445 reachability.
    func probeNetworkShare(configuration: NetworkShareConfiguration) async -> RemoteDestinationProbeResult

    /// Probes a WebDAV endpoint with the supplied password.
    func probeWebDAV(configuration: WebDAVConfiguration, password: String) async -> RemoteDestinationProbeResult

    /// Probes an SFTP endpoint with the supplied password or private key passphrase.
    func probeSFTP(configuration: SFTPConfiguration, secret: String) async -> RemoteDestinationProbeResult
}
