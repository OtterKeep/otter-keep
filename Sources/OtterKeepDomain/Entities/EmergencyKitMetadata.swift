import Foundation

/// Metadata representation for an offsite recovery target documented in the Emergency Kit.
public struct EmergencyRemoteDestination: Sendable, Codable, Equatable {
    public let name: String
    public let serviceType: String
    public let endpointOrHost: String
    public let bucketOrPath: String
    public let isEncrypted: Bool

    public init(
        name: String,
        serviceType: String,
        endpointOrHost: String,
        bucketOrPath: String,
        isEncrypted: Bool
    ) {
        self.name = name
        self.serviceType = serviceType
        self.endpointOrHost = endpointOrHost
        self.bucketOrPath = bucketOrPath
        self.isEncrypted = isEncrypted
    }
}

/// Structured snapshot metadata compiled into the downloadable and printable Emergency Recovery Kit.
public struct EmergencyKitMetadata: Sendable, Codable, Equatable {
    /// Backup profile identifier.
    public let profileId: UUID
    /// Profile display name.
    public let profileName: String
    /// Kit generation timestamp.
    public let generatedAt: Date
    /// Source filesystem directory path.
    public let sourceDirectory: String
    /// Primary local backup destination path or volume description.
    public let destinationDescription: String
    /// Client-side zero-knowledge encryption cipher and key derivation info.
    public let encryptionAlgorithm: String
    /// Cryptographic key fingerprint for verifying archive authenticity.
    public let keyFingerprint: String
    /// Cryptographic PBKDF2 salt in hexadecimal string representation.
    public let saltHex: String
    /// List of configured offsite secondary replication destinations (S3, B2, SFTP, WebDAV).
    public let remoteDestinations: [EmergencyRemoteDestination]
    /// Exact terminal command to restore files from scratch using the `otterkeep` CLI.
    public let cliRestoreCommand: String
    /// Text payload encoded inside the printable recovery QR code.
    public let qrPayload: String
    /// Optional embedded plaintext passphrase (only present if explicitly requested at creation time).
    public let embeddedPassphrase: String?

    public init(
        profileId: UUID,
        profileName: String,
        generatedAt: Date = Date(),
        sourceDirectory: String,
        destinationDescription: String,
        encryptionAlgorithm: String = "OKENC2 (PBKDF2-HMAC-SHA256 600,000 + AES-256-GCM)",
        keyFingerprint: String,
        saltHex: String,
        remoteDestinations: [EmergencyRemoteDestination] = [],
        cliRestoreCommand: String,
        qrPayload: String,
        embeddedPassphrase: String? = nil
    ) {
        self.profileId = profileId
        self.profileName = profileName
        self.generatedAt = generatedAt
        self.sourceDirectory = sourceDirectory
        self.destinationDescription = destinationDescription
        self.encryptionAlgorithm = encryptionAlgorithm
        self.keyFingerprint = keyFingerprint
        self.saltHex = saltHex
        self.remoteDestinations = remoteDestinations
        self.cliRestoreCommand = cliRestoreCommand
        self.qrPayload = qrPayload
        self.embeddedPassphrase = embeddedPassphrase
    }
}
