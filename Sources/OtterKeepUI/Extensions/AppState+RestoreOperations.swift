import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension AppState {
    // MARK: - Snapshot & File Tree Loading

    @MainActor
    public func loadSnapshots(force: Bool = false) {
        guard let profile = selectedProfile else {
            self.snapshots = []
            self.snapshotFiles = []
            self.snapshotTreeNodes = []
            self.timelinePaths = []
            self.timelineTreeNodes = []
            self.selectedPathVersions = []
            self.loadedProfileId = nil
            self.loadedSnapshotId = nil
            return
        }
        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path(percentEncoded: false)

        let profileChanged = self.loadedProfileId != profile.id
        if profileChanged {
            self.loadedProfileId = profile.id
            self.loadedSnapshotId = nil
        }

        Task {
            do {
                let list: [SnapshotRecord]
                if FileManager.default.fileExists(atPath: dbPath) {
                    try await database.open(at: dbPath)
                    list = try await database.listSnapshots()
                    try? CentralDatabase.shared.cacheSnapshots(list, forProfileId: profile.id.uuidString)
                } else {
                    list = try CentralDatabase.shared.listCachedSnapshots(forProfileId: profile.id.uuidString)
                }

                Task { @MainActor in
                    let snapshotsChanged = profileChanged || (self.snapshots.map(\.id) != list.map(\.id))
                    if snapshotsChanged || self.snapshots.isEmpty {
                        self.snapshots = list
                    }
                    self.profileLatestSnapshots[profile.id] = list.first
                    self.profileSnapshotCounts[profile.id] = list.count

                    if self.selectedSnapshotId == nil || !list.contains(where: { $0.id == self.selectedSnapshotId }) {
                        self.selectedSnapshotId = list.first?.id
                    }

                    // Only reload file tree if forced, snapshots list changed, tree is empty, or selected snapshot doesn't match loaded snapshot
                    if force || snapshotsChanged || self.snapshotTreeNodes.isEmpty || self.loadedSnapshotId != self.selectedSnapshotId {
                        self.loadFilesForSelectedSnapshot(force: force)
                        self.searchTimelinePaths(query: self.timelineSearchQuery, force: force)
                    }
                }
            } catch {
                Task { @MainActor in
                    self.snapshots = []
                    self.snapshotFiles = []
                    self.snapshotTreeNodes = []
                    self.timelinePaths = []
                    self.timelineTreeNodes = []
                    self.selectedPathVersions = []
                    self.loadedSnapshotId = nil
                    self.profileLatestSnapshots[profile.id] = nil
                    self.profileSnapshotCounts[profile.id] = 0
                }
            }
        }
    }

    /// Preloads recent snapshot headers and counts for all configured profiles to support instant ambient sidebar status.
    @MainActor
    public func preloadAllProfilesStatus() {
        for profile in profiles {
            let dbURL = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite")
            if FileManager.default.fileExists(atPath: dbURL.path) {
                Task {
                    let probeDB = DatabaseEngine()
                    do {
                        try await probeDB.open(at: dbURL.path)
                        let snaps = try await probeDB.listSnapshots()
                        await probeDB.close()
                        try? CentralDatabase.shared.cacheSnapshots(snaps, forProfileId: profile.id.uuidString)
                        Task { @MainActor in
                            self.profileLatestSnapshots[profile.id] = snaps.first
                            self.profileSnapshotCounts[profile.id] = snaps.count
                        }
                    } catch {}
                }
            } else if let cached = try? CentralDatabase.shared.listCachedSnapshots(forProfileId: profile.id.uuidString), !cached.isEmpty {
                self.profileLatestSnapshots[profile.id] = cached.first
                self.profileSnapshotCounts[profile.id] = cached.count
            }
        }
    }

    @MainActor
    public func loadFilesForSelectedSnapshot(force: Bool = false) {
        guard let snapshotId = selectedSnapshotId else {
            self.snapshotFiles = []
            self.snapshotTreeNodes = []
            self.loadedSnapshotId = nil
            return
        }

        if !force && self.loadedSnapshotId == snapshotId && !self.snapshotTreeNodes.isEmpty {
            return
        }

        let currentProfileId = selectedProfile?.id.uuidString ?? ""

        Task {
            let isDbAvailable = await database.isOpen
            do {
                let files: [FileCatalogRecord]
                if isDbAvailable {
                    files = try await database.listFiles(forSnapshotId: snapshotId)
                } else {
                    files = try CentralDatabase.shared.listCachedFiles(forSnapshotId: snapshotId, profileId: currentProfileId)
                }
                let tree = FileTreeBuilder.buildTree(from: files)
                Task { @MainActor in
                    self.loadedSnapshotId = snapshotId
                    self.snapshotFiles = files
                    self.snapshotTreeNodes = tree
                    let previousSelectedPath = self.selectedFile?.relativePath
                    if let previousSelectedPath = previousSelectedPath,
                       let matching = files.first(where: { $0.relativePath == previousSelectedPath }) {
                        self.selectedFile = matching
                    } else if self.selectedFile == nil || !files.contains(where: { $0.id == self.selectedFile?.id }) {
                        self.selectedFile = files.first
                    }
                }
            } catch {
                Task { @MainActor in
                    self.snapshotFiles = []
                    self.snapshotTreeNodes = []
                    self.loadedSnapshotId = nil
                }
            }
        }
    }

    // MARK: - File Timeline Tree & Search

    @MainActor
    public func searchTimelinePaths(query: String, force: Bool = false) {
        if !force && self.timelineSearchQuery == query && !self.timelineTreeNodes.isEmpty {
            return
        }
        self.timelineSearchQuery = query
        let currentProfileId = selectedProfile?.id.uuidString ?? ""

        Task {
            let isDbAvailable = await database.isOpen
            do {
                let paths: [String]
                if isDbAvailable {
                    paths = try await database.searchDistinctRelativePaths(matching: query)
                } else {
                    paths = try CentralDatabase.shared.searchCachedRelativePaths(matching: query, profileId: currentProfileId)
                }
                let tree = FileTreeBuilder.buildTree(from: paths)
                Task { @MainActor in
                    self.timelinePaths = paths
                    self.timelineTreeNodes = tree
                    if self.selectedTimelinePath == nil || !paths.contains(where: { $0 == self.selectedTimelinePath }) {
                        self.selectedTimelinePath = paths.first
                    }
                    if let path = self.selectedTimelinePath {
                        self.loadTimelineVersions(for: path)
                    } else {
                        self.selectedPathVersions = []
                        self.selectedTimelineVersion = nil
                    }
                }
            } catch {
                Task { @MainActor in
                    self.timelinePaths = []
                    self.timelineTreeNodes = []
                    self.selectedPathVersions = []
                    self.selectedTimelineVersion = nil
                }
            }
        }
    }

    @MainActor
    public func loadTimelineVersions(for relativePath: String) {
        self.selectedTimelinePath = relativePath
        let currentProfileId = selectedProfile?.id.uuidString ?? ""

        Task {
            let isDbAvailable = await database.isOpen
            do {
                let versions: [(snapshot: SnapshotRecord, file: FileCatalogRecord)]
                if isDbAvailable {
                    versions = try await database.listVersions(ofRelativePath: relativePath)
                } else {
                    versions = try CentralDatabase.shared.listCachedVersions(ofRelativePath: relativePath, profileId: currentProfileId)
                }
                Task { @MainActor in
                    self.selectedPathVersions = versions
                    self.selectedTimelineVersion = versions.first
                }
            } catch {
                Task { @MainActor in
                    self.selectedPathVersions = []
                    self.selectedTimelineVersion = nil
                }
            }
        }
    }

    // MARK: - Cross-Snapshot Global Search

    @MainActor
    public func searchGlobalSnapshots(query: String) {
        self.globalSearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.globalSearchResults = []
            self.selectedGlobalSearchResult = nil
            self.isGlobalSearching = false
            return
        }

        self.isGlobalSearching = true
        Task {
            do {
                let results = try await database.searchFilesAcrossSnapshots(query: trimmed, limit: 200)
                Task { @MainActor in
                    guard self.globalSearchQuery == query else { return }
                    self.globalSearchResults = results
                    self.selectedGlobalSearchResult = results.first
                    self.isGlobalSearching = false
                    self.updateQuickLookForCurrentSelection()
                }
            } catch {
                Task { @MainActor in
                    guard self.globalSearchQuery == query else { return }
                    self.globalSearchResults = []
                    self.selectedGlobalSearchResult = nil
                    self.isGlobalSearching = false
                }
            }
        }
    }

    @MainActor
    public func revealGlobalSearchResultInSnapshot(_ result: GlobalSearchResult) {
        self.restoreBrowseMode = .snapshot
        self.selectedSnapshotId = result.snapshotId
        self.loadFilesForSelectedSnapshot(force: true)
        self.selectedFile = result.fileRecord
        self.updateQuickLookForCurrentSelection()
    }

    @MainActor
    public func restoreGlobalSearchResult(
        _ result: GlobalSearchResult,
        to targetDirectory: URL,
        collision: CollisionResolution = .keepBoth
    ) {
        let fakeSnapshot = SnapshotRecord(
            id: result.snapshotId,
            timestamp: result.snapshotTimestamp,
            status: "completed",
            totalFiles: 0,
            totalBytes: 0,
            snapshotPath: result.snapshotPath,
            backupType: "incremental"
        )
        restoreVersion(snapshot: fakeSnapshot, file: result.fileRecord, to: targetDirectory, collision: collision)
    }

    // MARK: - Snapshot Diff Operations

    @MainActor
    public func loadSnapshotDiff(targetId: String? = nil, baseId: String? = nil) {
        guard let profile = selectedProfile else { return }
        let target = targetId ?? selectedSnapshotId ?? snapshots.first?.id
        guard let effectiveTarget = target else {
            self.snapshotDiffReport = nil
            return
        }

        self.selectedDiffTargetSnapshotId = effectiveTarget
        self.selectedDiffBaseSnapshotId = baseId
        self.isLoadingDiff = true

        Task {
            do {
                let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
                try await self.database.open(at: dbPath)
                let report = try await SnapshotDiffEngine.shared.diff(
                    database: self.database,
                    targetSnapshotId: effectiveTarget,
                    baseSnapshotId: baseId
                )
                Task { @MainActor in
                    self.snapshotDiffReport = report
                    self.isLoadingDiff = false
                }
            } catch {
                Task { @MainActor in
                    self.snapshotDiffReport = nil
                    self.isLoadingDiff = false
                    LogManager.shared.log("Failed to compute snapshot diff: \(error.localizedDescription)", level: .warning, category: "Diff")
                }
            }
        }
    }

    @MainActor
    public func openSideBySideDiff(for item: SnapshotDiffItem) {
        guard let profile = selectedProfile else { return }
        self.activeSideBySideDiffItem = item
        self.showSideBySideDiffModal = true
        self.isLoadingSideBySideDiff = true
        self.activeSideBySideDiffComparison = nil

        let targetSnapId = selectedDiffTargetSnapshotId ?? snapshots.first?.id
        let baseSnapId = selectedDiffBaseSnapshotId ?? (snapshots.count > 1 ? snapshots[1].id : nil)

        guard let tId = targetSnapId, let bId = baseSnapId,
              let snapTarget = snapshots.first(where: { $0.id == tId }),
              let snapBase = snapshots.first(where: { $0.id == bId }) else {
            self.isLoadingSideBySideDiff = false
            return
        }

        let urlA = profile.destinationURL.appendingPathComponent(snapBase.snapshotPath).appendingPathComponent("root").appendingPathComponent(item.relativePath)
        let urlB = profile.destinationURL.appendingPathComponent(snapTarget.snapshotPath).appendingPathComponent("root").appendingPathComponent(item.relativePath)

        Task {
            let result = try? TextDiffEngine().diffFiles(leftURL: urlA, rightURL: urlB, relativePath: item.relativePath)
            Task { @MainActor in
                self.activeSideBySideDiffComparison = result
                self.isLoadingSideBySideDiff = false
            }
        }
    }

    @MainActor
    public func openSideBySideDiff(forGlobalSearchResult result: GlobalSearchResult) {
        guard let profile = selectedProfile else { return }

        let diffItem = SnapshotDiffItem(
            relativePath: result.relativePath,
            changeType: .modified,
            oldRecord: nil,
            newRecord: result.fileRecord,
            sizeDelta: 0
        )
        self.activeSideBySideDiffItem = diffItem
        self.showSideBySideDiffModal = true
        self.isLoadingSideBySideDiff = true
        self.activeSideBySideDiffComparison = nil

        Task {
            do {
                let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
                try await self.database.open(at: dbPath)
                let versions = try await self.database.listVersions(ofRelativePath: result.relativePath)

                let targetSnap: SnapshotRecord
                let baseSnap: SnapshotRecord?

                if let idx = versions.firstIndex(where: { $0.snapshot.id == result.snapshotId }) {
                    targetSnap = versions[idx].snapshot
                    // The preceding historical version is idx + 1 (older)
                    if idx + 1 < versions.count {
                        baseSnap = versions[idx + 1].snapshot
                    } else if idx - 1 >= 0 {
                        // If it's the oldest snapshot, compare with the newer one
                        baseSnap = versions[idx - 1].snapshot
                    } else {
                        baseSnap = nil
                    }
                } else {
                    targetSnap = self.snapshots.first(where: { $0.id == result.snapshotId }) ?? SnapshotRecord(
                        id: result.snapshotId,
                        timestamp: result.snapshotTimestamp,
                        status: "completed",
                        totalFiles: 0,
                        totalBytes: result.fileSize,
                        snapshotPath: result.snapshotPath
                    )
                    baseSnap = versions.first(where: { $0.snapshot.id != result.snapshotId })?.snapshot
                }

                let urlTarget = profile.destinationURL
                    .appendingPathComponent(targetSnap.snapshotPath)
                    .appendingPathComponent("root")
                    .appendingPathComponent(result.relativePath)

                let urlBase: URL?
                if let base = baseSnap {
                    urlBase = profile.destinationURL
                        .appendingPathComponent(base.snapshotPath)
                        .appendingPathComponent("root")
                        .appendingPathComponent(result.relativePath)
                } else {
                    urlBase = nil
                }

                let comparison = try TextDiffEngine().diffFiles(
                    leftURL: urlBase,
                    rightURL: urlTarget,
                    relativePath: result.relativePath
                )

                Task { @MainActor in
                    self.activeSideBySideDiffComparison = comparison
                    self.isLoadingSideBySideDiff = false
                }
            } catch {
                Task { @MainActor in
                    self.isLoadingSideBySideDiff = false
                }
            }
        }
    }

    @MainActor
    public func openSideBySideDiff(forFileRecord record: FileCatalogRecord, inSnapshotId snapshotId: String) {
        guard selectedProfile != nil else { return }
        let snap = snapshots.first(where: { $0.id == snapshotId })
        let hit = GlobalSearchResult(
            snapshotId: snapshotId,
            snapshotTimestamp: snap?.timestamp ?? record.modificationTime,
            snapshotPath: snap?.snapshotPath ?? snapshotId,
            relativePath: record.relativePath,
            fileSize: record.fileSize,
            modificationDate: record.modificationTime,
            sha256: record.checksum ?? ""
        )
        openSideBySideDiff(forGlobalSearchResult: hit)
    }


}
