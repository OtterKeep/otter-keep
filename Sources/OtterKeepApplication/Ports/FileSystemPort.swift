import Foundation

/// Abstract storage port for filesystem operations, CoW reflink clones, and immutability controls.
public protocol FileSystemPort: Sendable {
    /// Checks whether an item exists at the specified URL.
    func fileExists(at url: URL) -> Bool

    /// Checks whether an item at the specified URL is a directory.
    func isDirectory(at url: URL) -> Bool

    /// Creates a directory and intermediate parent directories.
    func createDirectory(at url: URL) throws

    /// Creates an APFS Copy-on-Write clonefile or hardlink fallback.
    func cloneFile(source: URL, destination: URL) throws

    /// Creates a POSIX hardlink.
    func hardlink(source: URL, destination: URL) throws

    /// Atomically moves or renames an item from source to destination.
    func move(from source: URL, to destination: URL) throws

    /// Removes an item at the specified URL.
    func remove(at url: URL) throws

    /// Sets or clears BSD UF_IMMUTABLE (uchg) flags on the filesystem item.
    func setImmutable(at url: URL, immutable: Bool, recursive: Bool) throws
}
