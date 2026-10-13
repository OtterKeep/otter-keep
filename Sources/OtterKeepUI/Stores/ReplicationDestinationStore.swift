import Foundation
import Observation
import OtterKeepCore

/// 3-2-1 replication runtime state and the remote destination editor sheet state.
///
/// Owns live replication telemetry, the last replication job summary and every field of the remote
/// destination editor. `AppState` exposes this state through forwarding accessors so views keep
/// their existing call sites.
@MainActor
@Observable
public final class ReplicationDestinationStore: Sendable {
    // MARK: - 3-2-1 Replication State

    /// Indicates an ongoing 3-2-1 replication job.
    public var isReplicationRunning: Bool = false

    /// Live progress of the ongoing replication job.
    public var replicationProgressState: ReplicationProgressState = ReplicationProgressState()

    /// Summary of the last completed replication job.
    public var lastReplicationSummary: ReplicationJobSummary?

    // MARK: - Remote Destination Editor Sheet State

    /// Controls presentation of the remote destination editor sheet.
    public var showRemoteDestinationEditorSheet: Bool = false

    /// Destination being edited, or `nil` when creating a new one.
    public var destinationEditorTargetId: UUID? = nil

    /// Display name of the edited destination.
    public var destinationEditorName: String = ""

    /// Selected destination type index (0: S3, 1: SMB, 2: WebDAV, 3: SFTP, 4: Backblaze B2).
    public var destinationEditorTypeIndex: Int = 0

    /// S3-compatible endpoint URL.
    public var destinationEditorS3Endpoint: String = "https://s3.amazonaws.com"

    /// S3 bucket name.
    public var destinationEditorS3Bucket: String = ""

    /// S3 region identifier.
    public var destinationEditorS3Region: String = "eu-central-1"

    /// S3 access key identifier.
    public var destinationEditorS3AccessKeyId: String = ""

    /// S3 secret access key.
    public var destinationEditorS3SecretAccessKey: String = ""

    /// S3 object key prefix.
    public var destinationEditorS3PathPrefix: String = "otterkeep"

    /// Forces path-style S3 addressing.
    public var destinationEditorS3ForcePathStyle: Bool = true

    /// SMB share URL.
    public var destinationEditorSmbShareURL: String = "smb://nas.local/backups"

    /// SMB mount path.
    public var destinationEditorSmbMountPath: String = "/Volumes/backups"

    /// SMB username.
    public var destinationEditorSmbUsername: String = ""

    /// SMB password.
    public var destinationEditorSmbPassword: String = ""

    /// WebDAV base URL.
    public var destinationEditorWebDAVURL: String = "https://nas.local:5006"

    /// WebDAV path prefix.
    public var destinationEditorWebDAVPath: String = "/backups"

    /// WebDAV username.
    public var destinationEditorWebDAVUsername: String = ""

    /// WebDAV password.
    public var destinationEditorWebDAVPassword: String = ""

    /// SFTP host name.
    public var destinationEditorSFTPHost: String = "nas.local"

    /// SFTP port.
    public var destinationEditorSFTPPort: Int = 22

    /// SFTP username.
    public var destinationEditorSFTPUsername: String = ""

    /// SFTP password or private key.
    public var destinationEditorSFTPPasswordOrKey: String = ""

    /// Selected SFTP authentication mode index.
    public var destinationEditorSFTPAuthModeIndex: Int = 0

    /// SFTP remote path.
    public var destinationEditorSFTPPath: String = "/var/backups/otterkeep"

    /// Backblaze B2 key identifier.
    public var destinationEditorB2KeyId: String = ""

    /// Backblaze B2 application key.
    public var destinationEditorB2AppKey: String = ""

    /// Backblaze B2 bucket name.
    public var destinationEditorB2BucketName: String = ""

    /// Backblaze B2 region identifier.
    public var destinationEditorB2Region: String = "us-west-004"

    /// Backblaze B2 custom endpoint.
    public var destinationEditorB2CustomEndpoint: String = ""

    /// Backblaze B2 object key prefix.
    public var destinationEditorB2PathPrefix: String = "otterkeep"

    /// Enables archive packaging for this destination.
    public var destinationEditorArchivePackagingEnabled: Bool = false

    /// Archive compression level (1-9).
    public var destinationEditorArchiveCompressionLevel: Int = 3

    /// Enables client-side encryption for this destination.
    public var destinationEditorIsClientEncryptionEnabled: Bool = true

    /// Enables the destination for replication jobs.
    public var destinationEditorIsEnabled: Bool = true

    /// Indicates an ongoing connection test from the editor.
    public var destinationEditorIsTesting: Bool = false

    /// Success message of the last connection test.
    public var destinationEditorTestSuccessMessage: String? = nil

    /// Error message of the last connection test.
    public var destinationEditorTestErrorMessage: String? = nil

    /// Initializes an empty replication/destination store.
    public init() {}
}
