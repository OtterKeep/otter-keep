import Foundation
import OtterKeepDomain
import Darwin

/// Protocol for filesystem-specific drivers providing low-level operations.
public protocol FileSystemDriver: Sendable {
    /// Filesystem format identifier (e.g. "apfs", "exfat", "ntfs", "msdos", "generic").
    var fsTypeName: String { get }

    /// Returns the capabilities of the filesystem at the given URL.
    func capabilities(at url: URL) async throws -> FileSystemCapabilities

    /// Queries total, free, and available storage capacities on the volume hosting the specified URL.
    func storageCapacity(at url: URL) throws -> StorageCapacity

    /// Retrieves detailed metadata for an item.
    func metadata(at url: URL) throws -> FileMetadata

    /// Clones or copies a file using the optimal method supported by the filesystem (CoW reflink or stream copy).
    func cloneOrCopyItem(
        at source: URL,
        to destination: URL,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws

    /// Creates a hard link if supported by the filesystem.
    func createHardLink(at source: URL, to destination: URL) async throws

    /// Atomically moves or renames an item within the same filesystem.
    func atomicMove(from source: URL, to destination: URL) async throws

    /// Retrieves extended attributes for an item.
    func getExtendedAttributes(at url: URL) throws -> [String: Data]

    /// Writes extended attributes to an item.
    func setExtendedAttributes(_ attributes: [String: Data], at url: URL) throws

    /// Removes an item.
    func removeItem(at url: URL) throws

    /// Creates a directory and parent folders as needed.
    func createDirectory(at url: URL) throws

    /// Sets or clears immutability / protection flags.
    func setImmutable(at url: URL, immutable: Bool, recursive: Bool) throws

    /// Queries whether the item is immutable.
    func isFileImmutable(at url: URL) throws -> Bool
}

public extension FileSystemDriver {
    /// Convenience overload default for non-recursive immutability flag manipulation.
    func setImmutable(at url: URL, immutable: Bool) throws {
        try setImmutable(at: url, immutable: immutable, recursive: false)
    }
}


/// Abstract base POSIX implementation providing shared low-level utilities for filesystem drivers.
open class BasePOSIXFileSystemDriver: FileSystemDriver, @unchecked Sendable {

    open var fsTypeName: String {
        "generic"
    }

    public init() {}

    // MARK: - Path Helpers

    public func normalizedPath(for url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    // MARK: - statfs & Capacity

    public func statfsInfo(at url: URL) throws -> (fs: statfs, fstype: String, isReadOnly: Bool) {
        var fs = statfs()
        let path = normalizedPath(for: url)
        let result = statfs(path, &fs)
        guard result == 0 else {
            let err = errno
            throw FileSystemError.unknown("statfs error (\(path)): [errno \(err)] \(String(cString: strerror(err)))")
        }

        let fstype = withUnsafePointer(to: &fs.f_fstypename) { ptr -> String in
            let rawPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            return String(cString: rawPtr)
        }
        let isReadOnly = (fs.f_flags & UInt32(MNT_RDONLY)) != 0
        return (fs, fstype, isReadOnly)
    }

    open func capabilities(at url: URL) async throws -> FileSystemCapabilities {
        let (_, fstype, isReadOnly) = try statfsInfo(at: url)
        let path = normalizedPath(for: url)
        let linkMax = pathconf(path, _PC_LINK_MAX)

        return FileSystemCapabilities(
            fsTypeName: fstype,
            supportsAPFSClone: false,
            supportsHardLinks: linkMax > 1,
            supportsExtendedAttributes: true,
            supportsSymlinks: true,
            supportsFileFlags: false,
            isReadOnly: isReadOnly
        )
    }

    open func storageCapacity(at url: URL) throws -> StorageCapacity {
        let (fs, _, _) = try statfsInfo(at: url)
        let blockSize = Int64(fs.f_bsize)
        let total = Int64(fs.f_blocks) * blockSize
        let free = Int64(fs.f_bfree) * blockSize
        let avail = Int64(fs.f_bavail) * blockSize

        return StorageCapacity(
            totalBytes: max(0, total),
            freeBytes: max(0, free),
            availableBytes: max(0, avail)
        )
    }

    // MARK: - Metadata

    open func metadata(at url: URL) throws -> FileMetadata {
        let path = normalizedPath(for: url)
        var st = stat()
        let res = lstat(path, &st)
        guard res == 0 else {
            let err = errno
            if err == ENOENT {
                throw FileSystemError.itemNotFound(path: path)
            } else if err == EACCES {
                throw FileSystemError.permissionDenied(path: path)
            }
            throw FileSystemError.unknown("lstat error (\(path)): [errno \(err)] \(String(cString: strerror(err)))")
        }

        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        let isLnk = (st.st_mode & S_IFMT) == S_IFLNK
        let mtime = Date(
            timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000.0
        )

        return FileMetadata(
            url: url,
            size: Int64(st.st_size),
            modificationTime: mtime,
            inode: UInt64(st.st_ino),
            posixPermissions: UInt16(st.st_mode & 0o7777),
            isDirectory: isDir,
            isSymlink: isLnk
        )
    }

    // MARK: - Stream & CoW Copying

    private final class ProgressContext {
        let callback: (@Sendable (Int64) -> Void)?
        init(callback: (@Sendable (Int64) -> Void)?) {
            self.callback = callback
        }
    }

    public func copyfileStream(
        at source: URL,
        to destination: URL,
        cloneAllowed: Bool,
        fallbackToDataStat: Bool,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws {
        let srcPath = normalizedPath(for: source)
        let dstPath = normalizedPath(for: destination)

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: srcPath, isDirectory: &isDir), isDir.boolValue {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                progress?(0)
                return
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }

        guard let state = copyfile_state_alloc() else {
            throw FileSystemError.copyFailed(path: srcPath, errno: ENOMEM, message: "copyfile_state_alloc failed")
        }
        defer {
            copyfile_state_free(state)
        }

        let context = ProgressContext(callback: progress)

        if progress != nil {
            let callback: copyfile_callback_t = { (what, stage, state, src, dst, ctx) -> Int32 in
                guard let ctx = ctx else { return COPYFILE_CONTINUE }
                let progressCtx = Unmanaged<ProgressContext>.fromOpaque(ctx).takeUnretainedValue()

                if what == COPYFILE_COPY_DATA && stage == COPYFILE_PROGRESS {
                    var bytesCopied: off_t = 0
                    copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &bytesCopied)
                    progressCtx.callback?(Int64(bytesCopied))
                }
                return COPYFILE_CONTINUE
            }

            let ctxPointer = Unmanaged.passUnretained(context).toOpaque()
            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), ctxPointer)
        }

        var baseFlags = COPYFILE_ALL | COPYFILE_NOFOLLOW
        if cloneAllowed {
            baseFlags |= COPYFILE_CLONE
        }

        var res = copyfile(srcPath, dstPath, state, copyfile_flags_t(baseFlags))
        if res != 0 && fallbackToDataStat {
            let initialErr = errno
            if initialErr == ENOTSUP || initialErr == EOPNOTSUPP || initialErr == EINVAL || initialErr == EPERM {
                let fallbackFlags = copyfile_flags_t(COPYFILE_DATA | COPYFILE_STAT | COPYFILE_NOFOLLOW)
                res = copyfile(srcPath, dstPath, state, fallbackFlags)
            }
        }

        guard res == 0 else {
            let err = errno
            _ = unlink(dstPath)
            if err == ENOENT {
                throw FileSystemError.itemNotFound(path: srcPath)
            } else if err == EEXIST {
                throw FileSystemError.itemAlreadyExists(path: dstPath)
            } else if err == EACCES || err == EPERM {
                throw FileSystemError.permissionDenied(path: dstPath)
            } else if err == ENOSPC {
                throw FileSystemError.notEnoughSpace(requiredBytes: 0, availableBytes: 0)
            }
            throw FileSystemError.copyFailed(
                path: srcPath,
                errno: err,
                message: String(cString: strerror(err))
            )
        }

        if let progress = progress {
            var bytesCopied: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &bytesCopied)
            if bytesCopied == 0 {
                var st = stat()
                if lstat(dstPath, &st) == 0 {
                    bytesCopied = st.st_size
                }
            }
            progress(Int64(bytesCopied))
        }
    }

    open func cloneOrCopyItem(
        at source: URL,
        to destination: URL,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws {
        try await copyfileStream(
            at: source,
            to: destination,
            cloneAllowed: false,
            fallbackToDataStat: true,
            progress: progress
        )
    }

    // MARK: - Hard Links

    public func posixHardLink(at source: URL, to destination: URL) async throws {
        let srcPath = normalizedPath(for: source)
        let dstPath = normalizedPath(for: destination)

        let res = link(srcPath, dstPath)
        guard res == 0 else {
            let err = errno
            if err == ENOENT {
                throw FileSystemError.itemNotFound(path: srcPath)
            } else if err == EEXIST {
                throw FileSystemError.itemAlreadyExists(path: dstPath)
            } else if err == EACCES || err == EPERM {
                throw FileSystemError.permissionDenied(path: dstPath)
            } else if err == EXDEV {
                throw FileSystemError.hardLinkFailed(
                    path: srcPath,
                    errno: err,
                    message: "Cross-device hard links are not supported by POSIX (EXDEV)"
                )
            }
            throw FileSystemError.hardLinkFailed(
                path: srcPath,
                errno: err,
                message: String(cString: strerror(err))
            )
        }
    }

    open func createHardLink(at source: URL, to destination: URL) async throws {
        try await posixHardLink(at: source, to: destination)
    }

    // MARK: - Atomic Rename

    open func atomicMove(from source: URL, to destination: URL) async throws {
        let srcPath = normalizedPath(for: source)
        let dstPath = normalizedPath(for: destination)

        let res = rename(srcPath, dstPath)
        guard res == 0 else {
            let err = errno
            throw FileSystemError.atomicMoveFailed(
                source: srcPath,
                destination: dstPath,
                errno: err,
                message: String(cString: strerror(err))
            )
        }
    }

    // MARK: - Extended Attributes

    public func darwinGetXattrs(at url: URL) throws -> [String: Data] {
        let path = normalizedPath(for: url)
        let bufferSize = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard bufferSize >= 0 else {
            let err = errno
            if err == ENOENT { throw FileSystemError.itemNotFound(path: path) }
            if err == ENOTSUP || err == EOPNOTSUPP || err == EPERM {
                return [:]
            }
            throw FileSystemError.attributeOperationFailed(
                path: path,
                name: "*list*",
                errno: err,
                message: String(cString: strerror(err))
            )
        }

        if bufferSize == 0 {
            return [:]
        }

        var nameBuffer = [CChar](repeating: 0, count: bufferSize)
        let fetchedSize = listxattr(path, &nameBuffer, bufferSize, XATTR_NOFOLLOW)
        guard fetchedSize >= 0 else {
            let err = errno
            if err == ENOTSUP || err == EOPNOTSUPP || err == EPERM {
                return [:]
            }
            throw FileSystemError.attributeOperationFailed(
                path: path,
                name: "*list*",
                errno: err,
                message: String(cString: strerror(err))
            )
        }

        var attributes: [String: Data] = [:]
        var currentIndex = 0
        while currentIndex < fetchedSize {
            let name = nameBuffer.withUnsafeBufferPointer { buf in
                String(cString: buf.baseAddress! + currentIndex)
            }
            currentIndex += name.utf8.count + 1

            let valSize = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            if valSize > 0 {
                var dataBuffer = Data(count: valSize)
                let readSize = dataBuffer.withUnsafeMutableBytes { ptr in
                    getxattr(path, name, ptr.baseAddress, valSize, 0, XATTR_NOFOLLOW)
                }
                if readSize >= 0 {
                    attributes[name] = dataBuffer
                }
            } else if valSize == 0 {
                attributes[name] = Data()
            }
        }

        return attributes
    }

    public func darwinSetXattrs(
        _ attributes: [String: Data],
        at url: URL,
        allowUnsupportedIgnore: Bool
    ) throws {
        let path = normalizedPath(for: url)
        for (name, data) in attributes {
            let res: Int32 = data.withUnsafeBytes { rawPtr in
                setxattr(path, name, rawPtr.baseAddress, data.count, 0, XATTR_NOFOLLOW)
            }
            guard res == 0 else {
                let err = errno
                if (err == ENOTSUP || err == EOPNOTSUPP || err == EPERM || err == EINVAL) && allowUnsupportedIgnore {
                    continue
                }
                throw FileSystemError.attributeOperationFailed(
                    path: path,
                    name: name,
                    errno: err,
                    message: String(cString: strerror(err))
                )
            }
        }
    }

    open func getExtendedAttributes(at url: URL) throws -> [String: Data] {
        try darwinGetXattrs(at: url)
    }

    open func setExtendedAttributes(_ attributes: [String: Data], at url: URL) throws {
        try darwinSetXattrs(attributes, at: url, allowUnsupportedIgnore: true)
    }

    // MARK: - Directory & Immutability

    open func removeItem(at url: URL) throws {
        let path = normalizedPath(for: url)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    open func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func darwinSetImmutable(
        at url: URL,
        immutable: Bool,
        recursive: Bool = false,
        allowUnsupportedIgnore: Bool = true
    ) throws {
        let path = normalizedPath(for: url)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        guard exists else {
            throw FileSystemError.itemNotFound(path: path)
        }

        if !recursive || !isDir.boolValue {
            try applyDarwinImmutability(toPath: path, isDir: isDir.boolValue, immutable: immutable, allowUnsupportedIgnore: allowUnsupportedIgnore)
            return
        }

        // Recursive application
        if !immutable {
            // Unlocking: unlock root directory first so contents can be accessed and modified
            try applyDarwinImmutability(toPath: path, isDir: true, immutable: false, allowUnsupportedIgnore: allowUnsupportedIgnore)

            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
                for case let itemURL as URL in enumerator {
                    let subPath = normalizedPath(for: itemURL)
                    var subIsDir: ObjCBool = false
                    _ = FileManager.default.fileExists(atPath: subPath, isDirectory: &subIsDir)
                    try applyDarwinImmutability(toPath: subPath, isDir: subIsDir.boolValue, immutable: false, allowUnsupportedIgnore: allowUnsupportedIgnore)
                }
            }
        } else {
            // Locking: lock descendants first, then lock root directory
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
                for case let itemURL as URL in enumerator {
                    let subPath = normalizedPath(for: itemURL)
                    var subIsDir: ObjCBool = false
                    _ = FileManager.default.fileExists(atPath: subPath, isDirectory: &subIsDir)
                    try applyDarwinImmutability(toPath: subPath, isDir: subIsDir.boolValue, immutable: true, allowUnsupportedIgnore: allowUnsupportedIgnore)
                }
            }
            try applyDarwinImmutability(toPath: path, isDir: true, immutable: true, allowUnsupportedIgnore: allowUnsupportedIgnore)
        }
    }

    private func applyDarwinImmutability(
        toPath path: String,
        isDir: Bool,
        immutable: Bool,
        allowUnsupportedIgnore: Bool
    ) throws {
        if !immutable && isDir {
            var st = stat()
            if lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                _ = chmod(path, st.st_mode | mode_t(0o700))
            }
        }

        let flags: UInt32 = immutable ? UInt32(UF_IMMUTABLE) : 0
        let res = lchflags(path, flags)
        guard res == 0 else {
            let err = errno
            if (err == ENOTSUP || err == EOPNOTSUPP || err == EINVAL || err == EPERM) && allowUnsupportedIgnore {
                return
            }
            throw FileSystemError.attributeOperationFailed(
                path: path,
                name: "flags",
                errno: err,
                message: String(cString: strerror(err))
            )
        }

        if immutable && isDir {
            var st = stat()
            if lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                _ = chmod(path, st.st_mode & ~mode_t(0o222))
            }
        }
    }

    public func darwinIsImmutable(at url: URL) throws -> Bool {
        let path = normalizedPath(for: url)
        var st = stat()
        guard lstat(path, &st) == 0 else {
            let err = errno
            if err == ENOENT {
                throw FileSystemError.itemNotFound(path: path)
            }
            throw FileSystemError.unknown(String(cString: strerror(err)))
        }
        let immutableMask = UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)
        return (st.st_flags & immutableMask) != 0
    }

    open func isFileImmutable(at url: URL) throws -> Bool {
        try darwinIsImmutable(at: url)
    }

    open func setImmutable(at url: URL, immutable: Bool, recursive: Bool) throws {
        try darwinSetImmutable(at: url, immutable: immutable, recursive: recursive, allowUnsupportedIgnore: true)
    }

    open func setImmutable(at url: URL, immutable: Bool) throws {
        try setImmutable(at: url, immutable: immutable, recursive: false)
    }
}

