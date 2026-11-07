import Foundation
import OtterKeepDomain

/// Target remote backend type (S3 cloud storage, NAS network share, WebDAV, or SFTP).
public enum RemoteDestinationType: Codable, Sendable, Equatable {
    case s3(S3Configuration)
    case backblazeB2(B2Configuration)
    case smb(NetworkShareConfiguration)
    case webdav(WebDAVConfiguration)
    case sftp(SFTPConfiguration)

    enum CodingKeys: String, CodingKey {
        case type, s3Config, b2Config, smbConfig, webdavConfig, sftpConfig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeStr = try container.decode(String.self, forKey: .type)
        switch typeStr {
        case "s3":
            let config = try container.decode(S3Configuration.self, forKey: .s3Config)
            self = .s3(config)
        case "b2", "backblazeB2":
            let config = try container.decode(B2Configuration.self, forKey: .b2Config)
            self = .backblazeB2(config)
        case "smb":
            let config = try container.decode(NetworkShareConfiguration.self, forKey: .smbConfig)
            self = .smb(config)
        case "webdav":
            let config = try container.decode(WebDAVConfiguration.self, forKey: .webdavConfig)
            self = .webdav(config)
        case "sftp":
            let config = try container.decode(SFTPConfiguration.self, forKey: .sftpConfig)
            self = .sftp(config)
        default:
            let config = try container.decodeIfPresent(S3Configuration.self, forKey: .s3Config) ?? S3Configuration()
            self = .s3(config)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .s3(let config):
            try container.encode("s3", forKey: .type)
            try container.encode(config, forKey: .s3Config)
        case .backblazeB2(let config):
            try container.encode("b2", forKey: .type)
            try container.encode(config, forKey: .b2Config)
        case .smb(let config):
            try container.encode("smb", forKey: .type)
            try container.encode(config, forKey: .smbConfig)
        case .webdav(let config):
            try container.encode("webdav", forKey: .type)
            try container.encode(config, forKey: .webdavConfig)
        case .sftp(let config):
            try container.encode("sftp", forKey: .type)
            try container.encode(config, forKey: .sftpConfig)
        }
    }

    /// User-friendly display name of the remote destination type.
    public var typeDisplayName: String {
        switch self {
        case .s3: return "Cloud S3"
        case .backblazeB2: return "Backblaze B2"
        case .smb: return "NAS SMB"
        case .webdav: return "WebDAV"
        case .sftp: return "SFTP"
        }
    }
}

/// Representation of a configured remote off-site backup destination.
public struct RemoteDestination: Identifiable, Codable, Sendable, Equatable {
    /// Unique destination UUID.
    public let id: UUID
    /// User-visible display name (e.g. "AWS S3 Frankfurt", "Backblaze B2 Offsite", "Synology NAS").
    public var name: String
    /// Remote destination protocol and connection details.
    public var type: RemoteDestinationType
    /// Whether Zero-Knowledge client-side AES-256-GCM encryption is applied before transfer.
    public var isClientEncryptionEnabled: Bool
    /// Account identifier for reading secrets from the macOS Keychain.
    public var keychainAccount: String
    /// Whether replication to this destination is active.
    public var isEnabled: Bool
    /// Whether snapshots replicated to this destination are packaged as a single compressed archive (.tar.zst / .tar.gz).
    public var archivePackagingEnabled: Bool
    /// Archive compression level (1 = fastest, 3 = balanced default, 9 = ultra).
    public var archiveCompressionLevel: Int

    public init(
        id: UUID = UUID(),
        name: String,
        type: RemoteDestinationType,
        isClientEncryptionEnabled: Bool = true,
        keychainAccount: String = "",
        isEnabled: Bool = true,
        archivePackagingEnabled: Bool = false,
        archiveCompressionLevel: Int = 3
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isClientEncryptionEnabled = isClientEncryptionEnabled
        self.keychainAccount = keychainAccount.isEmpty ? id.uuidString : keychainAccount
        self.isEnabled = isEnabled
        self.archivePackagingEnabled = archivePackagingEnabled
        self.archiveCompressionLevel = archiveCompressionLevel
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, isClientEncryptionEnabled, keychainAccount, isEnabled
        case archivePackagingEnabled, archiveCompressionLevel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(RemoteDestinationType.self, forKey: .type)
        self.isClientEncryptionEnabled = try container.decodeIfPresent(Bool.self, forKey: .isClientEncryptionEnabled) ?? true
        self.keychainAccount = try container.decodeIfPresent(String.self, forKey: .keychainAccount) ?? id.uuidString
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.archivePackagingEnabled = try container.decodeIfPresent(Bool.self, forKey: .archivePackagingEnabled) ?? false
        self.archiveCompressionLevel = try container.decodeIfPresent(Int.self, forKey: .archiveCompressionLevel) ?? 3
    }
}
