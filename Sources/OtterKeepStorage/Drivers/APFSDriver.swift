import Foundation
import OtterKeepDomain
import Darwin

/// Apple APFS driver providing block-level Copy-on-Write cloning (`clonefile`),
/// nanosecond timestamp precision, BSD file immutability flags, and full extended attribute support.
public final class APFSDriver: BasePOSIXFileSystemDriver, @unchecked Sendable {

    public override var fsTypeName: String {
        "apfs"
    }

    public override init() {
        super.init()
    }

    public override func capabilities(at url: URL) async throws -> FileSystemCapabilities {
        let (_, fstype, isReadOnly) = try statfsInfo(at: url)
        let path = normalizedPath(for: url)
        let linkMax = pathconf(path, _PC_LINK_MAX)

        return FileSystemCapabilities(
            fsTypeName: fstype.isEmpty ? "apfs" : fstype,
            supportsAPFSClone: true,
            supportsHardLinks: linkMax > 1 || true,
            supportsExtendedAttributes: true,
            supportsSymlinks: true,
            supportsFileFlags: true,
            isReadOnly: isReadOnly
        )
    }

    public override func cloneOrCopyItem(
        at source: URL,
        to destination: URL,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws {
        let srcPath = normalizedPath(for: source)
        let dstPath = normalizedPath(for: destination)

        if FileManager.default.fileExists(atPath: dstPath) {
            throw FileSystemError.itemAlreadyExists(path: dstPath)
        }

        let flags = UInt32(CLONE_NOFOLLOW)
        let res = clonefile(srcPath, dstPath, flags)
        if res == 0 {
            if let progress = progress {
                var st = stat()
                if lstat(dstPath, &st) == 0 {
                    progress(Int64(st.st_size))
                } else {
                    progress(0)
                }
            }
            return
        }

        let err = errno
        if err == ENOENT {
            throw FileSystemError.itemNotFound(path: srcPath)
        } else if err == EEXIST {
            throw FileSystemError.itemAlreadyExists(path: dstPath)
        } else if err == EACCES || err == EPERM {
            throw FileSystemError.permissionDenied(path: dstPath)
        } else if err == ENOSPC {
            throw FileSystemError.notEnoughSpace(requiredBytes: 0, availableBytes: 0)
        } else if err == EXDEV || err == ENOTSUP {
            // Cross-device or unsupported APFS clone; fall back to stream copying with metadata preservation
            try await copyfileStream(
                at: source,
                to: destination,
                cloneAllowed: true,
                fallbackToDataStat: true,
                progress: progress
            )
            return
        }

        throw FileSystemError.cloneFailed(
            path: srcPath,
            errno: err,
            message: String(cString: strerror(err))
        )
    }

    public override func setImmutable(at url: URL, immutable: Bool, recursive: Bool) throws {
        try darwinSetImmutable(at: url, immutable: immutable, recursive: recursive, allowUnsupportedIgnore: false)
    }

    public override func setImmutable(at url: URL, immutable: Bool) throws {
        try setImmutable(at: url, immutable: immutable, recursive: false)
    }
}
