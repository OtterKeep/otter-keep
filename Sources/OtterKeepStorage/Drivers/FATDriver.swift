import Foundation
import OtterKeepDomain
import Darwin

/// Legacy MS-DOS / FAT32 filesystem driver.
/// Handles 2-second timestamp resolution and FAT volume constraints.
public final class FATDriver: BasePOSIXFileSystemDriver, @unchecked Sendable {

    public override var fsTypeName: String {
        "msdos"
    }

    public override init() {
        super.init()
    }

    public override func capabilities(at url: URL) async throws -> FileSystemCapabilities {
        let (_, fstype, isReadOnly) = try statfsInfo(at: url)

        return FileSystemCapabilities(
            fsTypeName: fstype.isEmpty ? "msdos" : fstype,
            supportsAPFSClone: false,
            supportsHardLinks: false,
            supportsExtendedAttributes: false,
            supportsSymlinks: false,
            supportsFileFlags: false,
            isReadOnly: isReadOnly
        )
    }

    public override func cloneOrCopyItem(
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

    public override func createHardLink(at source: URL, to destination: URL) async throws {
        throw FileSystemError.unsupportedOperation("Hard links are not supported on MS-DOS/FAT32 volumes.")
    }

    public override func getExtendedAttributes(at url: URL) throws -> [String: Data] {
        return [:]
    }

    public override func setExtendedAttributes(_ attributes: [String: Data], at url: URL) throws {
        // Ignored on FAT
    }

    public override func setImmutable(at url: URL, immutable: Bool, recursive: Bool) throws {
        // Ignored on FAT
    }

    public override func setImmutable(at url: URL, immutable: Bool) throws {
        // Ignored on FAT
    }

    public override func isFileImmutable(at url: URL) throws -> Bool {
        return false
    }
}
