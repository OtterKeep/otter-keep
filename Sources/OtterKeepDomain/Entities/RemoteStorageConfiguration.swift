import Foundation

/// Storage capacity metrics for a filesystem or volume.
public struct StorageCapacity: Sendable, Equatable {
    /// Total capacity in bytes.
    public let totalBytes: Int64
    /// Free storage space in bytes.
    public let freeBytes: Int64
    /// Available storage space in bytes (accounting for system reservations).
    public let availableBytes: Int64

    /// Initializes a new `StorageCapacity` instance.
    /// - Parameters:
    ///   - totalBytes: Total capacity in bytes.
    ///   - freeBytes: Free bytes available on disk.
    ///   - availableBytes: Available bytes usable by unprivileged applications.
    public init(totalBytes: Int64, freeBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.availableBytes = availableBytes
    }
}

/// S3 Configuration parameters.
public struct S3Configuration: Sendable, Codable, Equatable {
    /// S3 REST API endpoint URL string (e.g. "https://s3.eu-central-1.amazonaws.com" or "https://<accountid>.r2.cloudflarestorage.com").
    public var endpoint: String
    /// Target bucket name.
    public var bucket: String
    /// S3 Region (e.g. "eu-central-1", "us-east-1", "auto").
    public var region: String
    /// S3 Access Key ID.
    public var accessKeyId: String
    /// Base prefix folder in the bucket (e.g. "OtterKeep/MacBookPro").
    public var pathPrefix: String
    /// Whether to force path-style addressing (`endpoint/bucket/key`) instead of virtual hosted style (`bucket.endpoint/key`).
    public var forcePathStyle: Bool

    public init(
        endpoint: String = "https://s3.amazonaws.com",
        bucket: String = "",
        region: String = "us-east-1",
        accessKeyId: String = "",
        pathPrefix: String = "",
        forcePathStyle: Bool = true
    ) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.accessKeyId = accessKeyId
        self.pathPrefix = pathPrefix
        self.forcePathStyle = forcePathStyle
    }
}

/// Configuration settings for Backblaze B2 cloud storage.
public struct B2Configuration: Sendable, Codable, Equatable {
    /// Backblaze Application Key ID (Key ID).
    public var keyId: String
    /// Target B2 bucket name.
    public var bucketName: String
    /// B2 S3 Region (e.g. "us-west-004", "eu-central-003").
    public var region: String
    /// Optional custom B2 S3 endpoint URL (defaults to "https://s3.<region>.backblazeb2.com").
    public var customEndpoint: String?
    /// Path prefix inside the bucket (e.g. "OtterKeep/MacBook").
    public var pathPrefix: String

    public init(
        keyId: String = "",
        bucketName: String = "",
        region: String = "us-west-004",
        customEndpoint: String? = nil,
        pathPrefix: String = ""
    ) {
        self.keyId = keyId
        self.bucketName = bucketName
        self.region = region
        self.customEndpoint = customEndpoint
        self.pathPrefix = pathPrefix
    }

    /// Resolves the effective B2 S3 REST endpoint URL.
    public var resolvedEndpoint: String {
        if let custom = customEndpoint, !custom.isEmpty {
            return custom.hasPrefix("http") ? custom : "https://\(custom)"
        }
        return "https://s3.\(region).backblazeb2.com"
    }

    /// Converts this `B2Configuration` into an `S3Configuration` for S3-compatible protocol execution.
    public func toS3Configuration() -> S3Configuration {
        S3Configuration(
            endpoint: resolvedEndpoint,
            bucket: bucketName,
            region: region,
            accessKeyId: keyId,
            pathPrefix: pathPrefix,
            forcePathStyle: true
        )
    }
}

/// SMB / NFS Network Share Configuration.
public struct NetworkShareConfiguration: Sendable, Codable, Equatable {
    /// Remote share URL string (e.g. "smb://synology.local/Backups" or "nfs://192.168.1.50/volume1/backup").
    public var shareURL: String
    /// Username for SMB authentication.
    public var username: String
    /// Specific subfolder on the share.
    public var subfolder: String
    /// Whether to encapsulate backups inside an APFS Sparsebundle for full CoW and metadata preservation.
    public var useSparsebundle: Bool

    public init(
        shareURL: String = "",
        username: String = "",
        subfolder: String = "",
        useSparsebundle: Bool = true
    ) {
        self.shareURL = shareURL
        self.username = username
        self.subfolder = subfolder
        self.useSparsebundle = useSparsebundle
    }
}

/// Configuration options for connecting to a WebDAV remote storage backend.
public struct WebDAVConfiguration: Sendable, Codable, Equatable {
    /// Remote server base URL string (e.g. "https://nas.local:5006" or "https://cloud.example.com").
    public var serverURL: String
    /// Base destination subfolder path on the WebDAV server (e.g. "/remote.php/dav/files/user/OtterKeep").
    public var destinationPath: String
    /// Username for HTTP Basic Authentication.
    public var username: String
    /// Whether TLS / HTTPS is enforced.
    public var useSSL: Bool

    public init(
        serverURL: String = "https://",
        destinationPath: String = "/backups",
        username: String = "",
        useSSL: Bool = true
    ) {
        self.serverURL = serverURL
        self.destinationPath = destinationPath
        self.username = username
        self.useSSL = useSSL
    }
}

/// Authentication method for SFTP connection.
public enum SFTPAuthMethod: Sendable, Codable, Equatable {
    case password
    case privateKey(keyPath: String)

    enum CodingKeys: String, CodingKey {
        case type, keyPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeStr = try container.decode(String.self, forKey: .type)
        if typeStr == "privateKey" {
            let path = try container.decode(String.self, forKey: .keyPath)
            self = .privateKey(keyPath: path)
        } else {
            self = .password
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .password:
            try container.encode("password", forKey: .type)
        case .privateKey(let path):
            try container.encode("privateKey", forKey: .type)
            try container.encode(path, forKey: .keyPath)
        }
    }
}

/// Configuration options for connecting to an SFTP (SSH File Transfer Protocol) remote storage server.
public struct SFTPConfiguration: Sendable, Codable, Equatable {
    /// Remote server hostname or IP address (e.g. "nas.local", "192.168.1.100", "sftp.example.com").
    public var host: String
    /// SSH port number (default: 22).
    public var port: Int
    /// Username for SSH authentication.
    public var username: String
    /// Base destination subfolder path on the remote filesystem (e.g. "/data/backups/otterkeep").
    public var remotePath: String
    /// Selected authentication mechanism (password or private key).
    public var authMethod: SFTPAuthMethod

    public init(
        host: String = "",
        port: Int = 22,
        username: String = "",
        remotePath: String = "/backups",
        authMethod: SFTPAuthMethod = .password
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.remotePath = remotePath
        self.authMethod = authMethod
    }
}
