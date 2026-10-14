import Foundation
import os
import Darwin
import OtterKeepStorage

/// Representation of a scanned filesystem item discovered during directory enumeration.
public struct ScannedItem: Sendable, Equatable {
    /// Full standardized file URL.
    public let url: URL
    /// Relative path from the backup source root.
    public let relativePath: String
    /// POSIX and Darwin metadata for the item.
    public let metadata: FileMetadata
    /// Indicates whether the item is a dataless/ubiquitous iCloud Drive file not stored locally.
    public let isDatalessICloud: Bool

    /// Initializes a `ScannedItem`.
    public init(
        url: URL,
        relativePath: String,
        metadata: FileMetadata,
        isDatalessICloud: Bool = false
    ) {
        self.url = url
        self.relativePath = relativePath
        self.metadata = metadata
        self.isDatalessICloud = isDatalessICloud
    }
}

/// Representation of an unreadable or skipped item encountered during scanning.
public struct SkippedItem: Sendable, Equatable, Identifiable {
    /// Stable identifier for SwiftUI collections.
    public var id: String { relativePath + "_" + reason }
    /// Item file URL.
    public let url: URL
    /// Relative path from source root.
    public let relativePath: String
    /// Human-readable explanation of why the item was skipped.
    public let reason: String
    /// Indicates whether the error was caused by missing macOS Full Disk Access / TCC permissions.
    public let isPermissionError: Bool

    /// Initializes a `SkippedItem`.
    public init(
        url: URL,
        relativePath: String,
        reason: String,
        isPermissionError: Bool
    ) {
        self.url = url
        self.relativePath = relativePath
        self.reason = reason
        self.isPermissionError = isPermissionError
    }
}

/// Aggregated result of a directory tree scan containing both readable and skipped items.
public struct ScanResult: Sendable, Equatable {
    /// Array of successfully enumerated and accessible items.
    public let items: [ScannedItem]
    /// Array of skipped items that could not be accessed.
    public let skippedItems: [SkippedItem]

    /// Initializes a `ScanResult`.
    public init(items: [ScannedItem], skippedItems: [SkippedItem]) {
        self.items = items
        self.skippedItems = skippedItems
    }
}

/// Pattern matching rule for filtering and excluding specific files or directories from backups.
public struct ExclusionRule: Sendable, Equatable {
    /// Supported rule matching strategies.
    public enum RuleType: Sendable, Equatable {
        /// Exact filename or path match.
        case exact(String)
        /// Prefix pattern match (e.g. `temp*`).
        case prefix(String)
        /// Suffix/extension pattern match (e.g. `*.log`).
        case suffix(String)
        /// Substring containment match (e.g. `*cache*`).
        case contains(String)
    }

    /// Raw input pattern string.
    public let pattern: String
    /// Categorized rule type.
    public let ruleType: RuleType

    /// Initializes an `ExclusionRule` by parsing wildcard characters in the pattern.
    /// - Parameter pattern: Pattern string (e.g. `*.tmp`, `node_modules`, `.DS_Store`).
    public init(pattern: String) {
        self.pattern = pattern
        if pattern.hasPrefix("*") && !pattern.dropFirst().contains("*") {
            self.ruleType = .suffix(String(pattern.dropFirst()))
        } else if pattern.hasSuffix("*") && !pattern.dropLast().contains("*") {
            self.ruleType = .prefix(String(pattern.dropLast()))
        } else if pattern.hasPrefix("*") && pattern.hasSuffix("*") {
            let inner = String(pattern.dropFirst().dropLast())
            self.ruleType = .contains(inner)
        } else {
            self.ruleType = .exact(pattern)
        }
    }

    /// Evaluates whether a filename or relative path matches this exclusion rule.
    /// - Parameters:
    ///   - name: The item's last path component.
    ///   - relativePath: The relative path from the root directory.
    /// - Returns: True if the item should be excluded.
    public func matches(name: String, relativePath: String) -> Bool {
        switch ruleType {
        case .exact(let p):
            return name == p || relativePath == p
        case .prefix(let p):
            return name.hasPrefix(p) || relativePath.hasPrefix(p)
        case .suffix(let p):
            return name.hasSuffix(p) || relativePath.hasSuffix(p)
        case .contains(let p):
            return name.contains(p) || relativePath.contains(p)
        }
    }
}

/// High-performance recursive filesystem scanner with exclusion rule filtering, permission tracking, and iCloud ubiquitous detection.
public final class FileTreeScanner: Sendable {
    private let storage: FileSystemProvider
    private let exclusionRules: [ExclusionRule]
    private let enableIgnoreFiles: Bool
    private let respectGitIgnore: Bool

    /// Default system filenames always excluded from backups.
    public static let defaultExcludedNames: Set<String> = [
        ".DS_Store",
        ".Spotlight-V100",
        ".fseventsd",
        ".Trash",
        ".Trashes",
        ".otterkeep"
    ]

    /// Initializes a `FileTreeScanner`.
    /// - Parameters:
    ///   - storage: Low-level filesystem provider.
    ///   - excludePatterns: List of user-configured exclusion patterns.
    ///   - enableIgnoreFiles: Whether to respect .nobackup, CACHEDIR.TAG, and .otterkeepignore files.
    ///   - respectGitIgnore: Whether to automatically honor .gitignore files in repositories.
    public init(
        storage: FileSystemProvider,
        excludePatterns: [String] = [],
        enableIgnoreFiles: Bool = true,
        respectGitIgnore: Bool = false
    ) {
        self.storage = storage
        self.exclusionRules = excludePatterns.map { ExclusionRule(pattern: $0) }
        self.enableIgnoreFiles = enableIgnoreFiles
        self.respectGitIgnore = respectGitIgnore
    }

    private static func computeRelativePath(for url: URL, rootPath: String) -> String {
        let fullPath = url.standardizedFileURL.path(percentEncoded: false)
        if fullPath.hasPrefix(rootPath) {
            var trimmed = String(fullPath.dropFirst(rootPath.count))
            while trimmed.hasPrefix("/") { trimmed.removeFirst() }
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
            return trimmed
        } else {
            var name = url.lastPathComponent
            while name.hasSuffix("/") { name.removeLast() }
            return name
        }
    }

    private func parseIgnoreFile(at url: URL) -> [GitIgnoreRule] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.components(separatedBy: .newlines).compactMap { GitIgnoreRule(pattern: $0) }
    }

    /// Performs a detailed recursive directory scan, collecting both scanned items and skipped items.
    /// - Parameter rootURL: Source directory URL to scan.
    /// - Returns: A `ScanResult` containing all items and any skipped entries.
    public func scanDetailed(rootURL: URL) async throws -> ScanResult {
        var results: [ScannedItem] = []
        let fileManager = FileManager.default
        let rootPath = rootURL.standardizedFileURL.path(percentEncoded: false)

        let skippedCollector = OSAllocatedUnfairLock(initialState: [SkippedItem]())

        var ignoreContexts: [DirectoryIgnoreContext] = []
        if enableIgnoreFiles {
            var rootRules: [GitIgnoreRule] = []
            let rootDsIgnore = rootURL.appendingPathComponent(".otterkeepignore")
            if fileManager.fileExists(atPath: rootDsIgnore.path) {
                rootRules.append(contentsOf: parseIgnoreFile(at: rootDsIgnore))
            }
            if respectGitIgnore {
                let rootGitIgnore = rootURL.appendingPathComponent(".gitignore")
                if fileManager.fileExists(atPath: rootGitIgnore.path) {
                    rootRules.append(contentsOf: parseIgnoreFile(at: rootGitIgnore))
                }
            }
            if !rootRules.isEmpty {
                ignoreContexts.append(DirectoryIgnoreContext(baseRelativePath: "", rules: rootRules, isExclusionMarkerPresent: false))
            }
        }

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isPackageKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ],
            options: [.producesRelativePathURLs],
            errorHandler: { url, error in
                let relPath = Self.computeRelativePath(for: url, rootPath: rootPath)
                let isPerm: Bool
                if let cocoaError = error as? CocoaError {
                    isPerm = cocoaError.code == .fileReadNoPermission
                } else {
                    let nsErr = error as NSError
                    isPerm = (nsErr.domain == NSPOSIXErrorDomain && (nsErr.code == EACCES || nsErr.code == EPERM))
                }
                skippedCollector.withLock {
                    $0.append(SkippedItem(
                        url: url,
                        relativePath: relPath,
                        reason: error.localizedDescription,
                        isPermissionError: isPerm
                    ))
                }
                return true
            }
        ) else {
            return ScanResult(items: [], skippedItems: [])
        }

        var currentDatalessPackagePath: String? = nil
        var itemCount: Int = 0

        while let fileURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            itemCount += 1
            if itemCount % 250 == 0 {
                await Task.yield()
            }

            let lastComponent = fileURL.lastPathComponent
            let relativePath = Self.computeRelativePath(for: fileURL, rootPath: rootPath)
            let itemAbsoluteURL = rootURL.appendingPathComponent(relativePath)

            let itemPath = itemAbsoluteURL.path(percentEncoded: false)
            var statBuf = stat()
            guard lstat(itemPath, &statBuf) == 0 else { continue }
            let isDirectory = (statBuf.st_mode & S_IFMT) == S_IFDIR

            if Self.defaultExcludedNames.contains(lastComponent) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            // Check exclusion markers and directory ignore rules when encountering directories
            if isDirectory && enableIgnoreFiles {
                let noBackupFile = itemAbsoluteURL.appendingPathComponent(".nobackup")
                let cacheDirTagFile = itemAbsoluteURL.appendingPathComponent("CACHEDIR.TAG")
                let dsIgnoreFile = itemAbsoluteURL.appendingPathComponent(".otterkeepignore")

                if fileManager.fileExists(atPath: noBackupFile.path) || fileManager.fileExists(atPath: cacheDirTagFile.path) {
                    LogManager.shared.log("Skipping directory '\(relativePath)' due to exclusion marker (.nobackup / CACHEDIR.TAG)", level: .debug, category: "Scanner")
                    enumerator.skipDescendants()
                    continue
                }

                if fileManager.fileExists(atPath: dsIgnoreFile.path) {
                    if let content = try? String(contentsOf: dsIgnoreFile, encoding: .utf8) {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || trimmed == "*" {
                            LogManager.shared.log("Skipping directory '\(relativePath)' due to .otterkeepignore exclusion marker", level: .debug, category: "Scanner")
                            enumerator.skipDescendants()
                            continue
                        }
                    }
                }

                // Collect directory-specific ignore rules
                var dirRules: [GitIgnoreRule] = []
                if fileManager.fileExists(atPath: dsIgnoreFile.path) {
                    dirRules.append(contentsOf: parseIgnoreFile(at: dsIgnoreFile))
                }
                if respectGitIgnore {
                    let gitIgnoreFile = itemAbsoluteURL.appendingPathComponent(".gitignore")
                    if fileManager.fileExists(atPath: gitIgnoreFile.path) {
                        dirRules.append(contentsOf: parseIgnoreFile(at: gitIgnoreFile))
                    }
                }
                if !dirRules.isEmpty {
                    let baseRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    ignoreContexts.append(DirectoryIgnoreContext(baseRelativePath: baseRel, rules: dirRules, isExclusionMarkerPresent: false))
                }
            }

            // Evaluate exclusion rules
            let isExcluded = exclusionRules.contains { rule in
                rule.matches(name: lastComponent, relativePath: relativePath)
            }
            if isExcluded {
                LogManager.shared.log("Excluding '\(lastComponent)' (path: '\(relativePath)') matching configured exclusion rules", level: .debug, category: "Scanner")
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            // Evaluate hierarchical ignore rules (.otterkeepignore and .gitignore)
            if enableIgnoreFiles && !ignoreContexts.isEmpty {
                var isIgnoredByRules = false
                for context in ignoreContexts {
                    let baseRel = context.baseRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let inScope: Bool
                    let pathInContext: String
                    if baseRel.isEmpty {
                        inScope = true
                        pathInContext = relativePath
                    } else if relativePath == baseRel {
                        inScope = true
                        pathInContext = lastComponent
                    } else if relativePath.hasPrefix(baseRel + "/") {
                        inScope = true
                        pathInContext = String(relativePath.dropFirst(baseRel.count + 1))
                    } else {
                        inScope = false
                        pathInContext = ""
                    }

                    if inScope {
                        for rule in context.rules {
                            if rule.matches(relativePath: pathInContext, isDirectory: isDirectory) {
                                if rule.isNegative {
                                    isIgnoredByRules = false
                                } else {
                                    isIgnoredByRules = true
                                }
                            }
                        }
                    }
                }

                if isIgnoredByRules {
                    LogManager.shared.log("Excluding '\(lastComponent)' (path: '\(relativePath)') matching ignore file rules", level: .debug, category: "Scanner")
                    if isDirectory {
                        enumerator.skipDescendants()
                    }
                    continue
                }
            }

            let isSymlink = (try? itemAbsoluteURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true

            // Verify POSIX and effective readability (skip access check on symlinks as access follows targets)
            let filePath = itemAbsoluteURL.standardizedFileURL.path(percentEncoded: false)
            if !isSymlink && access(filePath, R_OK) != 0 {
                // access() evaluates real UID/GID; check effective access and FileManager before declaring unreadable
                let isEffectiveReadable = faccessat(AT_FDCWD, filePath, R_OK, AT_EACCESS) == 0 || fileManager.isReadableFile(atPath: filePath)
                if !isEffectiveReadable {
                    let err = errno
                    let isPerm = (err == EACCES || err == EPERM)
                    LogManager.shared.log("Skipping unreadable item '\(relativePath)': \(String(cString: strerror(err)))", level: .debug, category: "Scanner")
                    skippedCollector.withLock {
                        $0.append(SkippedItem(
                            url: itemAbsoluteURL,
                            relativePath: relativePath,
                            reason: String(cString: strerror(err)),
                            isPermissionError: isPerm
                        ))
                    }
                    if (try? itemAbsoluteURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
            }

            // Query filesystem metadata
            let meta: FileMetadata
            do {
                meta = try storage.metadata(at: itemAbsoluteURL)
            } catch {
                let isPerm: Bool
                if case FileSystemError.permissionDenied = error {
                    isPerm = true
                } else {
                    let nsErr = error as NSError
                    isPerm = (nsErr.domain == NSPOSIXErrorDomain && (nsErr.code == EACCES || nsErr.code == EPERM))
                }
                skippedCollector.withLock {
                    $0.append(SkippedItem(
                        url: itemAbsoluteURL,
                        relativePath: relativePath,
                        reason: error.localizedDescription,
                        isPermissionError: isPerm
                    ))
                }
                continue
            }

            var isDataless = false
            let resValues = try? itemAbsoluteURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .isPackageKey])
            let isUbiq = resValues?.isUbiquitousItem == true
            let downloadStatus = resValues?.ubiquitousItemDownloadingStatus

            var st = stat()
            let statAvailable = lstat(filePath, &st) == 0
            let isDatalessByStat = statAvailable && ((st.st_flags & UInt32(0x40000000)) != 0)

            if isDatalessByStat {
                isDataless = true
            } else if isUbiq && downloadStatus == .notDownloaded {
                isDataless = true
            }

            let isPackage = resValues?.isPackage == true
            if isPackage && isDataless {
                currentDatalessPackagePath = filePath
            } else if let activePkg = currentDatalessPackagePath {
                if filePath.hasPrefix(activePkg + "/") {
                    // Descendants inside a dataless package inherit its dataless state
                    isDataless = true
                } else {
                    currentDatalessPackagePath = nil
                }
            }

            results.append(ScannedItem(
                url: itemAbsoluteURL,
                relativePath: relativePath,
                metadata: meta,
                isDatalessICloud: isDataless
            ))
        }

        let skippedItems = skippedCollector.withLock { $0 }
        return ScanResult(items: results, skippedItems: skippedItems)
    }

    /// Convenience scan method returning only readable items.
    /// - Parameter rootURL: Source directory URL.
    /// - Returns: Array of `ScannedItem` records.
    public func scan(rootURL: URL) async throws -> [ScannedItem] {
        try await scanDetailed(rootURL: rootURL).items
    }
}
