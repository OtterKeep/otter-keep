import Foundation
import OtterKeepDatabase

/// Summary output of differential change detection comparing current scanned items against a previous snapshot catalog.
public struct ChangeDetectionResult: Sendable {
    /// Pairs of unmodified scanned items and their previous catalog records.
    public let unmodified: [(current: ScannedItem, previous: FileCatalogRecord)]
    /// Newly added items that did not exist in the previous snapshot.
    public let added: [ScannedItem]
    /// Existing items whose modification date or byte size changed.
    public let modified: [ScannedItem]
    /// Catalog items from the previous snapshot that no longer exist on the filesystem.
    public let deleted: [FileCatalogRecord]

    /// Total byte size of added and modified items requiring physical data transfer.
    public let totalChangedBytes: Int64

    /// Total count of items that will be represented in the new snapshot.
    public var totalItemsToProcess: Int {
        unmodified.count + added.count + modified.count
    }

    /// Initializes a `ChangeDetectionResult`.
    public init(
        unmodified: [(current: ScannedItem, previous: FileCatalogRecord)],
        added: [ScannedItem],
        modified: [ScannedItem],
        deleted: [FileCatalogRecord]
    ) {
        self.unmodified = unmodified
        self.added = added
        self.modified = modified
        self.deleted = deleted

        let addedBytes = added.reduce(0) { $0 + $1.metadata.size }
        let modifiedBytes = modified.reduce(0) { $0 + $1.metadata.size }
        self.totalChangedBytes = addedBytes + modifiedBytes
    }
}

/// Differential comparison engine identifying added, modified, unmodified, and deleted files.
public struct ChangeDetector: Sendable {
    /// Initializes a `ChangeDetector` instance.
    public init() {}

    /// Performs differential analysis by matching scanned filesystem items against previous snapshot catalog records.
    /// - Parameters:
    ///   - scannedItems: List of items discovered during the current file tree scan.
    ///   - previousCatalog: Lookup dictionary of relative paths to previous catalog records.
    ///   - hashMode: Hash verification strategy mode (default: `.smartHash`).
    ///   - timestampTolerance: Modification time comparison tolerance in seconds (default: `0.001` for APFS, `0.02` for exFAT, `2.0` for FAT).
    /// - Returns: A `ChangeDetectionResult` categorizing every scanned and removed item.
    public func detectChanges(
        scannedItems: [ScannedItem],
        previousCatalog: [String: FileCatalogRecord],
        hashMode: HashVerificationMode = .smartHash,
        timestampTolerance: Double = 0.001
    ) -> ChangeDetectionResult {
        var unmodified: [(current: ScannedItem, previous: FileCatalogRecord)] = []
        var added: [ScannedItem] = []
        var modified: [ScannedItem] = []
        var currentPaths = Set<String>()

        for item in scannedItems {
            currentPaths.insert(item.relativePath)

            if let prev = previousCatalog[item.relativePath] {
                // If item type changed (file <-> directory or symlink <-> regular), force re-backup
                if item.metadata.isDirectory != prev.isDirectory || item.metadata.isSymlink != prev.isSymlink {
                    modified.append(item)
                    continue
                }

                // Directory matching by structure
                if item.metadata.isDirectory && prev.isDirectory {
                    unmodified.append((current: item, previous: prev))
                    continue
                }

                // File comparison using modification time and file size
                let sizeMatches = item.metadata.size == prev.fileSize
                let timeDiff = abs(item.metadata.modificationTime.timeIntervalSince(prev.modificationTime))
                let mtimeMatches = timeDiff <= max(0.001, timestampTolerance)

                // If previous record had non-zero expected size but an empty SHA-256 hash (placeholder fallback),
                // force physical re-transfer so actual content is backed up!
                let wasEmptyPlaceholder = prev.fileSize > 0 && prev.checksum == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                if wasEmptyPlaceholder {
                    modified.append(item)
                    continue
                }


                if sizeMatches && mtimeMatches {
                    if item.isDatalessICloud {
                        // Dataless iCloud items: Size and modification time match.
                        // Strictly bypass content hashing or sampling to prevent kernel APFS faults / unintentional downloads.
                        unmodified.append((current: item, previous: prev))
                    } else if hashMode == .thoroughSampling && !item.metadata.isDirectory && !item.metadata.isSymlink {
                        // Thorough sampling mode: verify content hash against previous checksum
                        if let prevSample = prev.sampleHash, !prevSample.isEmpty {
                            if FastHashCalculator.samplingMatches(sourceURL: item.url, expectedSamplingHash: prevSample) {
                                unmodified.append((current: item, previous: prev))
                            } else {
                                modified.append(item)
                            }
                        } else if let prevChecksum = prev.checksum, !prevChecksum.isEmpty {
                            if FastHashCalculator.contentMatches(sourceURL: item.url, expectedChecksum: prevChecksum) {
                                unmodified.append((current: item, previous: prev))
                            } else {
                                modified.append(item)
                            }
                        } else {
                            unmodified.append((current: item, previous: prev))
                        }
                    } else {
                        unmodified.append((current: item, previous: prev))
                    }
                } else if sizeMatches && !mtimeMatches && hashMode != .metadataOnly && !item.metadata.isDirectory && !item.metadata.isSymlink {
                    if item.isDatalessICloud {
                        // Dataless iCloud file with changed modification time indicates remote cloud modification.
                        // Mark as modified directly without reading sample bytes to prevent premature download faults.
                        modified.append(item)
                    } else if let prevSample = prev.sampleHash, !prevSample.isEmpty {
                        // Smart Hash: Size matches but mtime changed (e.g. touch, git checkout, meta touch).
                        // Fast path: Check 64 KB sparse sample hash first for sub-millisecond check!
                        if FastHashCalculator.samplingMatches(sourceURL: item.url, expectedSamplingHash: prevSample) {
                            unmodified.append((current: item, previous: prev))
                        } else {
                            modified.append(item)
                        }
                    } else if let prevChecksum = prev.checksum, !prevChecksum.isEmpty {
                        // Fallback to full cryptographic checksum if no sample hash was persisted
                        if FastHashCalculator.contentMatches(sourceURL: item.url, expectedChecksum: prevChecksum) {
                            unmodified.append((current: item, previous: prev))
                        } else {
                            modified.append(item)
                        }
                    } else {
                        modified.append(item)
                    }
                } else {
                    modified.append(item)
                }
            } else {
                added.append(item)
            }
        }

        // Identify deleted items present in the previous snapshot but absent now
        var deleted: [FileCatalogRecord] = []
        for (prevPath, prevRecord) in previousCatalog {
            if !currentPaths.contains(prevPath) {
                deleted.append(prevRecord)
            }
        }

        return ChangeDetectionResult(
            unmodified: unmodified,
            added: added,
            modified: modified,
            deleted: deleted
        )
    }
}
