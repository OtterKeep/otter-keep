import SwiftUI
import AppKit
import Photos
import OtterKeepDatabase
import OtterKeepCore

/// Forwarding accessors exposing the 3-2-1 replication runtime state and the remote destination
/// editor fields owned by ``ReplicationDestinationStore`` on `AppState` so views keep their existing call sites.
extension AppState {
    // MARK: - 3-2-1 Replication State
    /// Indicates an ongoing 3-2-1 replication job.
    public var isReplicationRunning: Bool {
        get { replicationDestinations.isReplicationRunning }
        set { replicationDestinations.isReplicationRunning = newValue }
    }
    /// Live progress of the ongoing replication job.
    public var replicationProgressState: ReplicationProgressState {
        get { replicationDestinations.replicationProgressState }
        set { replicationDestinations.replicationProgressState = newValue }
    }
    /// Summary of the last completed replication job.
    public var lastReplicationSummary: ReplicationJobSummary? {
        get { replicationDestinations.lastReplicationSummary }
        set { replicationDestinations.lastReplicationSummary = newValue }
    }

    // MARK: - Remote Destination Editor Sheet State
    /// Controls presentation of the remote destination editor sheet.
    public var showRemoteDestinationEditorSheet: Bool {
        get { replicationDestinations.showRemoteDestinationEditorSheet }
        set { replicationDestinations.showRemoteDestinationEditorSheet = newValue }
    }
    /// Destination being edited, or `nil` when creating a new one.
    public var destinationEditorTargetId: UUID? {
        get { replicationDestinations.destinationEditorTargetId }
        set { replicationDestinations.destinationEditorTargetId = newValue }
    }
    /// Display name of the edited destination.
    public var destinationEditorName: String {
        get { replicationDestinations.destinationEditorName }
        set { replicationDestinations.destinationEditorName = newValue }
    }
    /// Selected destination type index (0: S3, 1: SMB, 2: WebDAV, 3: SFTP, 4: Backblaze B2).
    public var destinationEditorTypeIndex: Int {
        get { replicationDestinations.destinationEditorTypeIndex }
        set { replicationDestinations.destinationEditorTypeIndex = newValue }
    }
    /// S3-compatible endpoint URL.
    public var destinationEditorS3Endpoint: String {
        get { replicationDestinations.destinationEditorS3Endpoint }
        set { replicationDestinations.destinationEditorS3Endpoint = newValue }
    }
    /// S3 bucket name.
    public var destinationEditorS3Bucket: String {
        get { replicationDestinations.destinationEditorS3Bucket }
        set { replicationDestinations.destinationEditorS3Bucket = newValue }
    }
    /// S3 region identifier.
    public var destinationEditorS3Region: String {
        get { replicationDestinations.destinationEditorS3Region }
        set { replicationDestinations.destinationEditorS3Region = newValue }
    }
    /// S3 access key identifier.
    public var destinationEditorS3AccessKeyId: String {
        get { replicationDestinations.destinationEditorS3AccessKeyId }
        set { replicationDestinations.destinationEditorS3AccessKeyId = newValue }
    }
    /// S3 secret access key.
    public var destinationEditorS3SecretAccessKey: String {
        get { replicationDestinations.destinationEditorS3SecretAccessKey }
        set { replicationDestinations.destinationEditorS3SecretAccessKey = newValue }
    }
    /// S3 object key prefix.
    public var destinationEditorS3PathPrefix: String {
        get { replicationDestinations.destinationEditorS3PathPrefix }
        set { replicationDestinations.destinationEditorS3PathPrefix = newValue }
    }
    /// Forces path-style S3 addressing.
    public var destinationEditorS3ForcePathStyle: Bool {
        get { replicationDestinations.destinationEditorS3ForcePathStyle }
        set { replicationDestinations.destinationEditorS3ForcePathStyle = newValue }
    }
    /// SMB share URL.
    public var destinationEditorSmbShareURL: String {
        get { replicationDestinations.destinationEditorSmbShareURL }
        set { replicationDestinations.destinationEditorSmbShareURL = newValue }
    }
    /// SMB mount path.
    public var destinationEditorSmbMountPath: String {
        get { replicationDestinations.destinationEditorSmbMountPath }
        set { replicationDestinations.destinationEditorSmbMountPath = newValue }
    }
    /// SMB username.
    public var destinationEditorSmbUsername: String {
        get { replicationDestinations.destinationEditorSmbUsername }
        set { replicationDestinations.destinationEditorSmbUsername = newValue }
    }
    /// SMB password.
    public var destinationEditorSmbPassword: String {
        get { replicationDestinations.destinationEditorSmbPassword }
        set { replicationDestinations.destinationEditorSmbPassword = newValue }
    }
    /// WebDAV base URL.
    public var destinationEditorWebDAVURL: String {
        get { replicationDestinations.destinationEditorWebDAVURL }
        set { replicationDestinations.destinationEditorWebDAVURL = newValue }
    }
    /// WebDAV path prefix.
    public var destinationEditorWebDAVPath: String {
        get { replicationDestinations.destinationEditorWebDAVPath }
        set { replicationDestinations.destinationEditorWebDAVPath = newValue }
    }
    /// WebDAV username.
    public var destinationEditorWebDAVUsername: String {
        get { replicationDestinations.destinationEditorWebDAVUsername }
        set { replicationDestinations.destinationEditorWebDAVUsername = newValue }
    }
    /// WebDAV password.
    public var destinationEditorWebDAVPassword: String {
        get { replicationDestinations.destinationEditorWebDAVPassword }
        set { replicationDestinations.destinationEditorWebDAVPassword = newValue }
    }
    /// SFTP host name.
    public var destinationEditorSFTPHost: String {
        get { replicationDestinations.destinationEditorSFTPHost }
        set { replicationDestinations.destinationEditorSFTPHost = newValue }
    }
    /// SFTP port.
    public var destinationEditorSFTPPort: Int {
        get { replicationDestinations.destinationEditorSFTPPort }
        set { replicationDestinations.destinationEditorSFTPPort = newValue }
    }
    /// SFTP username.
    public var destinationEditorSFTPUsername: String {
        get { replicationDestinations.destinationEditorSFTPUsername }
        set { replicationDestinations.destinationEditorSFTPUsername = newValue }
    }
    /// SFTP password or private key.
    public var destinationEditorSFTPPasswordOrKey: String {
        get { replicationDestinations.destinationEditorSFTPPasswordOrKey }
        set { replicationDestinations.destinationEditorSFTPPasswordOrKey = newValue }
    }
    /// Selected SFTP authentication mode index.
    public var destinationEditorSFTPAuthModeIndex: Int {
        get { replicationDestinations.destinationEditorSFTPAuthModeIndex }
        set { replicationDestinations.destinationEditorSFTPAuthModeIndex = newValue }
    }
    /// SFTP remote path.
    public var destinationEditorSFTPPath: String {
        get { replicationDestinations.destinationEditorSFTPPath }
        set { replicationDestinations.destinationEditorSFTPPath = newValue }
    }
    /// Backblaze B2 key identifier.
    public var destinationEditorB2KeyId: String {
        get { replicationDestinations.destinationEditorB2KeyId }
        set { replicationDestinations.destinationEditorB2KeyId = newValue }
    }
    /// Backblaze B2 application key.
    public var destinationEditorB2AppKey: String {
        get { replicationDestinations.destinationEditorB2AppKey }
        set { replicationDestinations.destinationEditorB2AppKey = newValue }
    }
    /// Backblaze B2 bucket name.
    public var destinationEditorB2BucketName: String {
        get { replicationDestinations.destinationEditorB2BucketName }
        set { replicationDestinations.destinationEditorB2BucketName = newValue }
    }
    /// Backblaze B2 region identifier.
    public var destinationEditorB2Region: String {
        get { replicationDestinations.destinationEditorB2Region }
        set { replicationDestinations.destinationEditorB2Region = newValue }
    }
    /// Backblaze B2 custom endpoint.
    public var destinationEditorB2CustomEndpoint: String {
        get { replicationDestinations.destinationEditorB2CustomEndpoint }
        set { replicationDestinations.destinationEditorB2CustomEndpoint = newValue }
    }
    /// Backblaze B2 object key prefix.
    public var destinationEditorB2PathPrefix: String {
        get { replicationDestinations.destinationEditorB2PathPrefix }
        set { replicationDestinations.destinationEditorB2PathPrefix = newValue }
    }
    /// Enables archive packaging for this destination.
    public var destinationEditorArchivePackagingEnabled: Bool {
        get { replicationDestinations.destinationEditorArchivePackagingEnabled }
        set { replicationDestinations.destinationEditorArchivePackagingEnabled = newValue }
    }
    /// Archive compression level (1-9).
    public var destinationEditorArchiveCompressionLevel: Int {
        get { replicationDestinations.destinationEditorArchiveCompressionLevel }
        set { replicationDestinations.destinationEditorArchiveCompressionLevel = newValue }
    }
    /// Enables client-side encryption for this destination.
    public var destinationEditorIsClientEncryptionEnabled: Bool {
        get { replicationDestinations.destinationEditorIsClientEncryptionEnabled }
        set { replicationDestinations.destinationEditorIsClientEncryptionEnabled = newValue }
    }
    /// Enables the destination for replication jobs.
    public var destinationEditorIsEnabled: Bool {
        get { replicationDestinations.destinationEditorIsEnabled }
        set { replicationDestinations.destinationEditorIsEnabled = newValue }
    }
    /// Indicates an ongoing connection test from the editor.
    public var destinationEditorIsTesting: Bool {
        get { replicationDestinations.destinationEditorIsTesting }
        set { replicationDestinations.destinationEditorIsTesting = newValue }
    }
    /// Success message of the last connection test.
    public var destinationEditorTestSuccessMessage: String? {
        get { replicationDestinations.destinationEditorTestSuccessMessage }
        set { replicationDestinations.destinationEditorTestSuccessMessage = newValue }
    }
    /// Error message of the last connection test.
    public var destinationEditorTestErrorMessage: String? {
        get { replicationDestinations.destinationEditorTestErrorMessage }
        set { replicationDestinations.destinationEditorTestErrorMessage = newValue }
    }
}
