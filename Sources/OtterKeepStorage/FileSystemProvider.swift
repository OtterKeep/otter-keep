import Foundation
import Darwin

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

/// Volume capabilities and supported filesystem features.
public struct FileSystemCapabilities: Sendable, Equatable {
    /// Name of the underlying filesystem format (e.g. "apfs", "hfs", "msdos", "exfat", "ntfs").
    public let fsTypeName: String
    /// Indicates whether block-level Copy-on-Write (APFS cloning / reflink) is supported.
    public let supportsAPFSClone: Bool
    /// Indicates whether POSIX hard links are supported on the volume.
    public let supportsHardLinks: Bool
    /// Indicates whether extended attributes (xattrs) are supported.
    public let supportsExtendedAttributes: Bool
    /// Indicates whether symbolic links are natively supported on the volume.
    public let supportsSymlinks: Bool
    /// Indicates whether BSD file immutability flags (UF_IMMUTABLE / chflags) are supported.
    public let supportsFileFlags: Bool
    /// Indicates whether the volume is mounted in read-only mode.
    public let isReadOnly: Bool

    /// True if the filesystem is Apple APFS.
    public var isAPFS: Bool {
        fsTypeName.lowercased() == "apfs"
    }

    /// True if the filesystem is Microsoft exFAT.
    public var isExFAT: Bool {
        fsTypeName.lowercased() == "exfat"
    }

    /// True if the filesystem is Microsoft NTFS.
    public var isNTFS: Bool {
        let name = fsTypeName.lowercased()
        return name == "ntfs" || name.contains("ntfs")
    }

    /// True if the filesystem is legacy MS-DOS / FAT32.
    public var isFAT: Bool {
        let name = fsTypeName.lowercased()
        return name == "msdos" || name == "fat32" || name == "fat"
    }

    /// Modification timestamp comparison tolerance in seconds for differential change detection.
    public var timestampToleranceSeconds: Double {
        if isFAT {
            return 2.0 // FAT32 has 2-second timestamp resolution
        } else if isExFAT {
            return 0.02 // exFAT has 10-millisecond timestamp resolution
        } else {
            return 0.001 // APFS, HFS+, and NTFS have sub-millisecond / nanosecond precision
        }
    }

    /// Initializes a new `FileSystemCapabilities` instance.
    /// - Parameters:
    ///   - fsTypeName: Filesystem type identifier string.
    ///   - supportsAPFSClone: True if native APFS block cloning is supported.
    ///   - supportsHardLinks: True if POSIX hard links are supported.
    ///   - supportsExtendedAttributes: True if Darwin xattrs are supported.
    ///   - supportsSymlinks: True if symbolic links are supported.
    ///   - supportsFileFlags: True if BSD chflags (UF_IMMUTABLE) are supported.
    ///   - isReadOnly: True if the target volume is read-only.
    public init(
        fsTypeName: String,
        supportsAPFSClone: Bool,
        supportsHardLinks: Bool,
        supportsExtendedAttributes: Bool,
        supportsSymlinks: Bool = true,
        supportsFileFlags: Bool = true,
        isReadOnly: Bool
    ) {
        self.fsTypeName = fsTypeName
        self.supportsAPFSClone = supportsAPFSClone
        self.supportsHardLinks = supportsHardLinks
        self.supportsExtendedAttributes = supportsExtendedAttributes
        self.supportsSymlinks = supportsSymlinks
        self.supportsFileFlags = supportsFileFlags
        self.isReadOnly = isReadOnly
    }
}


/// Fundamental metadata attributes of a file, directory, or symbolic link.
public struct FileMetadata: Sendable, Equatable {
    /// Standardized file URL.
    public let url: URL
    /// Logical file size in bytes.
    public let size: Int64
    /// Last modification timestamp.
    public let modificationTime: Date
    /// POSIX file system inode number.
    public let inode: UInt64
    /// POSIX permission bitmask (e.g. 0o755).
    public let posixPermissions: UInt16
    /// True if the item is a directory.
    public let isDirectory: Bool
    /// True if the item is a symbolic link.
    public let isSymlink: Bool

    /// Initializes a new `FileMetadata` record.
    /// - Parameters:
    ///   - url: File URL.
    ///   - size: Size in bytes.
    ///   - modificationTime: Modification date.
    ///   - inode: Inode number.
    ///   - posixPermissions: POSIX permission bitmask.
    ///   - isDirectory: Whether the path represents a directory.
    ///   - isSymlink: Whether the path represents a symlink.
    public init(
        url: URL,
        size: Int64,
        modificationTime: Date,
        inode: UInt64,
        posixPermissions: UInt16,
        isDirectory: Bool,
        isSymlink: Bool
    ) {
        self.url = url
        self.size = size
        self.modificationTime = modificationTime
        self.inode = inode
        self.posixPermissions = posixPermissions
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
    }
}

/// Structured errors encountered during low-level filesystem operations.
public enum FileSystemError: Error, Sendable, LocalizedError, Equatable {
    /// The specified file or directory could not be found.
    case itemNotFound(path: String)
    /// A file or directory already exists at the target destination.
    case itemAlreadyExists(path: String)
    /// Permission was denied by POSIX or macOS Privacy (TCC / Full Disk Access).
    case permissionDenied(path: String)
    /// Insufficient free storage space available to complete the operation.
    case notEnoughSpace(requiredBytes: Int64, availableBytes: Int64)
    /// Native APFS `clonefile` system call failed.
    case cloneFailed(path: String, errno: Int32, message: String)
    /// File copying operation failed.
    case copyFailed(path: String, errno: Int32, message: String)
    /// POSIX `link` hardlink creation failed.
    case hardLinkFailed(path: String, errno: Int32, message: String)
    /// Atomic directory or file rename/move failed.
    case atomicMoveFailed(source: String, destination: String, errno: Int32, message: String)
    /// Extended attribute (xattr) get/set/list operation failed.
    case attributeOperationFailed(path: String, name: String, errno: Int32, message: String)
    /// The requested operation is not supported by the underlying filesystem.
    case unsupportedOperation(String)
    /// An unknown or unclassified filesystem error occurred.
    case unknown(String)

    /// Whether this error represents an out-of-disk-space condition (ENOSPC).
    public var isOutOfSpace: Bool {
        switch self {
        case .notEnoughSpace:
            return true
        case .copyFailed(_, let code, _), .cloneFailed(_, let code, _), .hardLinkFailed(_, let code, _), .atomicMoveFailed(_, _, let code, _):
            return code == ENOSPC
        default:
            return false
        }
    }

    /// Whether this error represents a fatal device disconnection or unmounted volume (EIO, ENODEV, EROFS).
    public var isFatalVolumeError: Bool {
        switch self {
        case .copyFailed(_, let code, _), .cloneFailed(_, let code, _), .hardLinkFailed(_, let code, _), .atomicMoveFailed(_, _, let code, _):
            return code == EIO || code == ENODEV || code == EROFS
        default:
            return false
        }
    }

    /// Human-readable localized error description.
    public var errorDescription: String? {
        switch self {
        case .itemNotFound(let path):
            return "Item not found: \(path)"
        case .itemAlreadyExists(let path):
            return "Item already exists: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .notEnoughSpace(let required, let available):
            return "Not enough storage space. Required: \(required) bytes, Available: \(available) bytes"
        case .cloneFailed(let path, let code, let message):
            return "APFS cloning error (\(path)): [errno \(code)] \(message)"
        case .copyFailed(let path, let code, let message):
            return "Copy error (\(path)): [errno \(code)] \(message)"
        case .hardLinkFailed(let path, let code, let message):
            return "Hard link error (\(path)): [errno \(code)] \(message)"
        case .atomicMoveFailed(let src, let dst, let code, let message):
            return "Atomic move error (\(src) -> \(dst)): [errno \(code)] \(message)"
        case .attributeOperationFailed(let path, let name, let code, let message):
            return "Extended attribute error (\(path), \(name)): [errno \(code)] \(message)"
        case .unsupportedOperation(let op):
            return "Unsupported operation: \(op)"
        case .unknown(let msg):
            return "Filesystem error: \(msg)"
        }
    }
}

/// Abstract interface for low-level macOS storage operations and filesystem abstractions.
public protocol FileSystemProvider: Sendable {
    /// Inspects and returns filesystem capabilities for the volume hosting the specified URL.
    /// - Parameter url: The URL to inspect.
    /// - Returns: A `FileSystemCapabilities` structure describing volume support flags.
    func capabilities(at url: URL) async throws -> FileSystemCapabilities

    /// Queries total, free, and available storage capacities on the volume hosting the specified URL.
    /// - Parameter url: The URL to inspect.
    /// - Returns: A `StorageCapacity` structure with capacity numbers.
    func storageCapacity(at url: URL) throws -> StorageCapacity

    /// Retrieves detailed POSIX and Darwin metadata for an item.
    /// - Parameter url: The file or directory URL.
    /// - Returns: A `FileMetadata` descriptor.
    func metadata(at url: URL) throws -> FileMetadata

    /// Clones a file or directory on the same APFS volume using Copy-on-Write (reflink).
    /// - Parameters:
    ///   - source: Source file URL.
    ///   - destination: Destination URL where the clone will be created.
    func cloneItem(at source: URL, to destination: URL) async throws

    /// Creates a POSIX hard link pointing from source to destination.
    /// - Parameters:
    ///   - source: Existing file URL.
    ///   - destination: New hard link URL.
    func createHardLink(at source: URL, to destination: URL) async throws

    /// Copies an item while preserving full metadata, ACLs, flags, and extended attributes.
    /// - Parameters:
    ///   - source: Source URL.
    ///   - destination: Destination URL.
    ///   - progress: Optional callback invoked with cumulative bytes transferred.
    func copyItemPreservingMetadata(
        at source: URL,
        to destination: URL,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws

    /// Atomically moves or renames an item within the same filesystem.
    /// - Parameters:
    ///   - source: Existing source URL.
    ///   - destination: Target destination URL.
    func atomicMove(from source: URL, to destination: URL) async throws

    /// Retrieves all extended attributes (xattrs) for the specified item.
    /// - Parameter url: Target file URL.
    /// - Returns: A dictionary mapping attribute names to raw binary Data.
    func getExtendedAttributes(at url: URL) throws -> [String: Data]

    /// Writes extended attributes (xattrs) to the specified item.
    /// - Parameters:
    ///   - attributes: Dictionary of attribute names and data values.
    ///   - url: Target file URL.
    func setExtendedAttributes(_ attributes: [String: Data], at url: URL) throws

    /// Removes a file or directory hierarchy.
    /// - Parameter url: Item URL to delete.
    func removeItem(at url: URL) throws

    /// Creates a directory and any intermediate parent folders if needed.
    /// - Parameter url: Directory URL to create.
    func createDirectory(at url: URL) throws

    /// Sets or removes the BSD file immutability flag (`UF_IMMUTABLE` / WORM protection).
    /// - Parameters:
    ///   - url: Target item URL.
    ///   - immutable: True to set `UF_IMMUTABLE`, false to clear.
    ///   - recursive: Whether to recursively set/clear the flag on all descendants.
    func setImmutable(at url: URL, immutable: Bool, recursive: Bool) throws

    /// Queries whether the BSD file immutability flag (`UF_IMMUTABLE` or `SF_IMMUTABLE`) is currently set on the target item.
    /// - Parameter url: Target item URL.
    /// - Returns: True if the file or directory is immutable.
    func isFileImmutable(at url: URL) throws -> Bool
}

public extension FileSystemProvider {
    /// Convenience overload default for non-recursive immutability flag manipulation.
    func setImmutable(at url: URL, immutable: Bool) throws {
        try setImmutable(at: url, immutable: immutable, recursive: false)
    }
}

