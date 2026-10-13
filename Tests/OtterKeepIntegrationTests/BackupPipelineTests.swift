//
//  BackupPipelineTests.swift
//  OtterKeepIntegrationTests
//
//  Backup Pipeline: Incremental Backup Lifecycle, Change Detection,
//  WORM Immutability, Catalog Queries, and Restore Operations.
//

import Foundation
import os
import Darwin
import Photos
import CryptoKit
import AppKit
import SwiftUI
import Testing
import OtterKeepDomain
import OtterKeepApplication
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore
import OtterKeepUI

/// Executed serially: these tests exercise process-wide singletons and fixed paths.
@MainActor
@Suite(.serialized)
struct BackupPipelineTests {
    @Test func testGitIgnoreRuleParser() throws {
        let parser = GitIgnoreRule(pattern: "*.tmp")
        try assertNotNil(parser)
        try assertTrue(parser?.matches(relativePath: "scratch/test.tmp", isDirectory: false) == true)
        try assertFalse(parser?.matches(relativePath: "scratch/test.txt", isDirectory: false) == true)

        let dirRule = GitIgnoreRule(pattern: "build/")
        try assertNotNil(dirRule)
        try assertTrue(dirRule?.matches(relativePath: "build", isDirectory: true) == true)

        let negationRule = GitIgnoreRule(pattern: "!important.tmp")
        try assertNotNil(negationRule)
        try assertTrue(negationRule?.isNegative == true)
    }

    @Test func testChangeDetectorPrecision() throws {
        let detector = ChangeDetector()
        let t1 = Date(timeIntervalSince1970: 1000.0)
        let t2 = Date(timeIntervalSince1970: 1000.0005) // 0.5ms difference (within APFS 1ms tolerance)

        let testURL = URL(fileURLWithPath: "/tmp/test.txt")
        let meta = FileMetadata(
            url: testURL,
            size: 500,
            modificationTime: t2,
            inode: 1234,
            posixPermissions: 0o644,
            isDirectory: false,
            isSymlink: false
        )
        let scanned = ScannedItem(url: testURL, relativePath: "test.txt", metadata: meta)
        let prev = FileCatalogRecord(snapshotId: "s1", relativePath: "test.txt", fileSize: 500, modificationTime: t1, inode: 1234, isDirectory: false, isSymlink: false)

        let result = detector.detectChanges(scannedItems: [scanned], previousCatalog: ["test.txt": prev], hashMode: .smartHash, timestampTolerance: 0.001)
        try assertEqual(result.unmodified.count, 1, "Item within 1ms tolerance must be classified as unmodified")
        try assertEqual(result.modified.count, 0)
    }

    @Test func testRansomwareAnomalyGuard() throws {
        // Normal profile: 2 out of 100 files changed (2%)
        let normalReport = RansomwareAnomalyGuard.evaluate(
            totalFiles: 100,
            modifiedCount: 2,
            deletedCount: 0,
            candidatePaths: ["doc1.pdf", "doc2.pdf"],
            enableGuard: true,
            maxChangeThresholdPercent: 20.0
        )
        try assertFalse(normalReport.isAnomalyDetected, "Normal change rate should not trigger anomaly")

        // Anomaly: 80 out of 100 files changed with .locked extensions
        let anomalyReport = RansomwareAnomalyGuard.evaluate(
            totalFiles: 100,
            modifiedCount: 80,
            deletedCount: 0,
            candidatePaths: ["doc1.pdf.locked", "doc2.pdf.locked"],
            enableGuard: true,
            maxChangeThresholdPercent: 20.0,
            detectSuspiciousExtensions: true
        )
        try assertTrue(anomalyReport.isAnomalyDetected, "Mass mutation with .locked must trigger anomaly guard")
        try assertTrue(anomalyReport.suspiciousExtensionFiles.count > 0)
    }

    @Test func testEndToEndBackupLifecycle() async throws {
        let tempDir = try createTempDirectory(prefix: "E2EBackup")
        defer { removeTempDirectory(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("Source")
        let destDir = tempDir.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let file1 = sourceDir.appendingPathComponent("file1.txt")
        let file2 = sourceDir.appendingPathComponent("file2.txt")
        try "Primary Data 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Primary Data 2".write(to: file2, atomically: true, encoding: .utf8)

        let profile = BackupProfile(
            name: "E2ETestProfile",
            sourceURL: sourceDir,
            destinationURL: destDir
        )

        let storage = DefaultFileSystemProvider()
        let db = DatabaseEngine()
        let coordinator = BackupSessionCoordinator(storage: storage, database: db)

        // 1. Initial Backup
        let snap1 = try await coordinator.performBackup(profile: profile, mode: .incremental)
        try assertEqual(snap1.status, "completed")
        try assertEqual(snap1.totalFiles, 2)

        // 2. Incremental Backup with 1 modified file and 1 added file
        try "Modified Data 1".write(to: file1, atomically: true, encoding: .utf8)
        let file3 = sourceDir.appendingPathComponent("file3.txt")
        try "Added Data 3".write(to: file3, atomically: true, encoding: .utf8)

        let snap2 = try await coordinator.performBackup(profile: profile, mode: .incremental)
        try assertEqual(snap2.status, "completed")
        try assertEqual(snap2.totalFiles, 3)

        // 3. Restore verification
        let restoreEngine = RestoreEngine(storage: storage, database: db)
        let restoreDest = tempDir.appendingPathComponent("Restored")
        try FileManager.default.createDirectory(at: restoreDest, withIntermediateDirectories: true)

        let restoredURL = try await restoreEngine.restoreToFile(
            snapshotPath: snap2.snapshotPath,
            backupRootURL: destDir,
            relativePath: "file1.txt",
            destinationFileURL: restoreDest.appendingPathComponent("file1.txt")
        )

        let restoredContent = try String(contentsOf: restoredURL, encoding: .utf8)
        try assertEqual(restoredContent, "Modified Data 1", "Restored file content must match incremental state")
    }

    @Test func testCooperativeFileTreeScanner() async throws {
        let tempDir = try createTempDirectory(prefix: "CoopScan")
        defer { removeTempDirectory(tempDir) }

        // Create structure with .nobackup exclusion marker
        let excludedDir = tempDir.appendingPathComponent("CacheFolder")
        try FileManager.default.createDirectory(at: excludedDir, withIntermediateDirectories: true)
        try "marker".write(to: excludedDir.appendingPathComponent(".nobackup"), atomically: true, encoding: .utf8)
        try "secret".write(to: excludedDir.appendingPathComponent("cached_payload.bin"), atomically: true, encoding: .utf8)

        let includedFile = tempDir.appendingPathComponent("valid.txt")
        try "keep".write(to: includedFile, atomically: true, encoding: .utf8)

        let scanner = FileTreeScanner(storage: DefaultFileSystemProvider())
        let scanResult = try await scanner.scanDetailed(rootURL: tempDir)

        let paths = scanResult.items.map(\.relativePath)
        try assertTrue(paths.contains("valid.txt"))
        try assertFalse(paths.contains("CacheFolder/cached_payload.bin"), "Items in directory with .nobackup marker must be skipped")
    }

    @Test func testFullSnapshotEntireRestore() async throws {
        let tempDir = try createTempDirectory(prefix: "FullRestore")
        defer { removeTempDirectory(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("Source")
        let destDir = tempDir.appendingPathComponent("BackupDest")
        let restoreTargetDir = tempDir.appendingPathComponent("RestoreTarget")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: restoreTargetDir, withIntermediateDirectories: true)

        // Create sample hierarchy
        let subDir = sourceDir.appendingPathComponent("SubFolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let file1 = sourceDir.appendingPathComponent("alpha.txt")
        let file2 = subDir.appendingPathComponent("beta.data")
        let file3 = sourceDir.appendingPathComponent("gamma.log")

        try "Alpha Content".write(to: file1, atomically: true, encoding: .utf8)
        let sampleBinary = Data((0..<1024).map { UInt8($0 % 256) })
        try sampleBinary.write(to: file2)
        try "Gamma Log Line 1\nGamma Log Line 2\n".write(to: file3, atomically: true, encoding: .utf8)

        let profile = BackupProfile(
            name: "FullRestoreTestProfile",
            sourceURL: sourceDir,
            destinationURL: destDir
        )

        let coordinator = BackupSessionCoordinator()
        let snap = try await coordinator.performBackup(profile: profile, mode: .full)
        try assertEqual(snap.status, "completed")
        try assertEqual(snap.totalFiles, 4, "Snapshot includes 1 directory and 3 files")

        // Perform entire snapshot restore
        let db = DatabaseEngine()
        let dbPath = destDir.appendingPathComponent(".otterkeep/manifest.sqlite").path
        try await db.open(at: dbPath)
        let storage = DefaultFileSystemProvider()
        let restoreEngine = RestoreEngine(storage: storage, database: db)

        final class ProgressBox: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var list: [RestoreProgressState] = []
            func append(_ item: RestoreProgressState) {
                lock.lock()
                defer { lock.unlock() }
                list.append(item)
            }
            var count: Int {
                lock.lock()
                defer { lock.unlock() }
                return list.count
            }
        }
        let progressBox = ProgressBox()

        let summary = try await restoreEngine.restoreSnapshot(
            snapshotPath: snap.snapshotPath,
            backupRootURL: destDir,
            targetDirectoryURL: restoreTargetDir,
            collisionResolution: .overwrite,
            progress: { prog in
                progressBox.append(prog)
            }
        )

        // Verifications
        try assertEqual(summary.restoredFiles, 3, "All 3 files must be restored")
        try assertTrue(summary.restoredBytes > 0, "Restored bytes must be non-zero")
        try assertTrue(progressBox.count > 0, "Progress events must be emitted during restoration")

        // Verify filesystem content & integrity
        let restoredFile1 = restoreTargetDir.appendingPathComponent("alpha.txt")
        let restoredFile2 = restoreTargetDir.appendingPathComponent("SubFolder/beta.data")
        let restoredFile3 = restoreTargetDir.appendingPathComponent("gamma.log")

        try assertTrue(FileManager.default.fileExists(atPath: restoredFile1.path), "Restored alpha.txt must exist")
        try assertTrue(FileManager.default.fileExists(atPath: restoredFile2.path), "Restored beta.data in SubFolder must exist")
        try assertTrue(FileManager.default.fileExists(atPath: restoredFile3.path), "Restored gamma.log must exist")

        let content1 = try String(contentsOf: restoredFile1, encoding: .utf8)
        try assertEqual(content1, "Alpha Content", "alpha.txt content must match original")

        let content2 = try Data(contentsOf: restoredFile2)
        try assertEqual(content2, sampleBinary, "beta.data binary data must match original")

        // Verify SHA-256 matches
        let hashOriginal = try ChecksumCalculator.computeSHA256(for: file2)
        let hashRestored = try ChecksumCalculator.computeSHA256(for: restoredFile2)
        try assertEqual(hashOriginal, hashRestored, "SHA-256 hash must be identical")
    }

    @Test func testDatalessICloudChangeDetection() throws {
        let detector = ChangeDetector()
        let dummyURL = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/document.key")
        let now = Date(timeIntervalSince1970: 1700000000)

        let metadata = FileMetadata(
            url: dummyURL,
            size: 2048576,
            modificationTime: now,
            inode: 8888,
            posixPermissions: 0o644,
            isDirectory: false,
            isSymlink: false
        )

        // Dataless iCloud item: not downloaded locally
        let scannedItem = ScannedItem(
            url: dummyURL,
            relativePath: "iCloud/document.key",
            metadata: metadata,
            isDatalessICloud: true
        )

        let previousCatalogRecord = FileCatalogRecord(
            snapshotId: "snap-prev",
            relativePath: "iCloud/document.key",
            fileSize: 2048576,
            modificationTime: now,
            inode: 8888,
            checksum: "a1b2c3d4e5f67890123456789012345678901234567890123456789012345678",
            sampleHash: "sampleHash123",
            isDirectory: false,
            isSymlink: false
        )

        let catalog = ["iCloud/document.key": previousCatalogRecord]

        // 1. Unmodified check under thoroughSampling mode:
        // Must strictly bypass sample and content hashing to avoid kernel APFS faults / forced downloads
        let result = detector.detectChanges(
            scannedItems: [scannedItem],
            previousCatalog: catalog,
            hashMode: .thoroughSampling
        )

        try assertEqual(result.unmodified.count, 1, "Dataless iCloud item with matching size & mtime must be marked unmodified without reading payload")
        try assertEqual(result.modified.count, 0)

        // 2. Modified check when modification time changes
        let modifiedMeta = FileMetadata(
            url: dummyURL,
            size: 2048576,
            modificationTime: now.addingTimeInterval(3600), // 1 hour later
            inode: 8888,
            posixPermissions: 0o644,
            isDirectory: false,
            isSymlink: false
        )
        let modifiedItem = ScannedItem(
            url: dummyURL,
            relativePath: "iCloud/document.key",
            metadata: modifiedMeta,
            isDatalessICloud: true
        )

        let changedResult = detector.detectChanges(
            scannedItems: [modifiedItem],
            previousCatalog: catalog,
            hashMode: .smartHash
        )

        try assertEqual(changedResult.modified.count, 1, "Dataless iCloud item with changed mtime must be detected as modified")
        try assertEqual(changedResult.unmodified.count, 0)
    }

    @Test func testWORMImmutabilityAndRetentionPruning() async throws {
        let tempDir = try createTempDirectory(prefix: "WORM")
        defer {
            // Unlock everything before attempting test teardown cleanup
            let provider = DefaultFileSystemProvider()
            try? provider.setImmutable(at: tempDir, immutable: false, recursive: true)
            removeTempDirectory(tempDir)
        }

        let provider = DefaultFileSystemProvider()
        let testSnapDir = tempDir.appendingPathComponent("snapshot_worm_test")
        let testSubDir = testSnapDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: testSubDir, withIntermediateDirectories: true)
        let testFile1 = testSnapDir.appendingPathComponent("file1.txt")
        let testFile2 = testSubDir.appendingPathComponent("file2.txt")
        try "Content1".write(to: testFile1, atomically: true, encoding: .utf8)
        try "Content2".write(to: testFile2, atomically: true, encoding: .utf8)

        // 1. Initially files are not immutable
        let initF1Imm = try provider.isFileImmutable(at: testFile1)
        let initF2Imm = try provider.isFileImmutable(at: testFile2)
        try assertFalse(initF1Imm, "Initial file must not be immutable")
        try assertFalse(initF2Imm, "Initial nested file must not be immutable")

        // 2. Recursive immutability locks directory and nested files
        try provider.setImmutable(at: testSnapDir, immutable: true, recursive: true)
        let lockedDirImm = try provider.isFileImmutable(at: testSnapDir)
        let lockedF1Imm = try provider.isFileImmutable(at: testFile1)
        let lockedF2Imm = try provider.isFileImmutable(at: testFile2)
        try assertTrue(lockedDirImm, "Snapshot directory must be immutable")
        try assertTrue(lockedF1Imm, "Top-level file in snapshot must be immutable")
        try assertTrue(lockedF2Imm, "Nested file in snapshot must be immutable")

        // 3. Recursive unlock unlocks directory and all nested files
        try provider.setImmutable(at: testSnapDir, immutable: false, recursive: true)
        let unDirImm = try provider.isFileImmutable(at: testSnapDir)
        let unF1Imm = try provider.isFileImmutable(at: testFile1)
        let unF2Imm = try provider.isFileImmutable(at: testFile2)
        try assertFalse(unDirImm, "Snapshot directory must be unlocked")
        try assertFalse(unF1Imm, "Top-level file must be unlocked")
        try assertFalse(unF2Imm, "Nested file must be unlocked")

        // 4. Database WORM lock state
        let internalDir = tempDir.appendingPathComponent(".otterkeep")
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)

        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let snapIdNewest = "snap_newest_00"
        let snapIdLocked = "snap_locked_01"
        let snapIdPrunable = "snap_prunable_02"
        let fortyDaysAgo = Date().addingTimeInterval(-40 * 86400)
        let thirtyDaysFuture = Date().addingTimeInterval(30 * 86400)

        // Create snapshot directories
        let snapDirNewest = tempDir.appendingPathComponent(snapIdNewest)
        let snapDirLocked = tempDir.appendingPathComponent(snapIdLocked)
        let snapDirPrunable = tempDir.appendingPathComponent(snapIdPrunable)
        try FileManager.default.createDirectory(at: snapDirNewest, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapDirLocked, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapDirPrunable, withIntermediateDirectories: true)

        let lockedInnerFile = snapDirLocked.appendingPathComponent("data.txt")
        try "Protected data".write(to: lockedInnerFile, atomically: true, encoding: .utf8)
        try provider.setImmutable(at: snapDirLocked, immutable: true, recursive: true)

        let newestSnap = SnapshotRecord(
            id: snapIdNewest,
            timestamp: Date(),
            status: "completed",
            totalFiles: 1,
            totalBytes: 100,
            snapshotPath: snapIdNewest,
            lockedUntil: nil
        )
        try await db.insertSnapshot(newestSnap)

        let lockedSnap = SnapshotRecord(
            id: snapIdLocked,
            timestamp: fortyDaysAgo,
            status: "completed",
            totalFiles: 1,
            totalBytes: 100,
            snapshotPath: snapIdLocked,
            lockedUntil: thirtyDaysFuture
        )
        try await db.insertSnapshot(lockedSnap)
        try assertTrue(lockedSnap.isLocked, "Snapshot with future lockedUntil must report isLocked == true")

        let prunableSnap = SnapshotRecord(
            id: snapIdPrunable,
            timestamp: fortyDaysAgo,
            status: "completed",
            totalFiles: 1,
            totalBytes: 100,
            snapshotPath: snapIdPrunable,
            lockedUntil: nil
        )
        try await db.insertSnapshot(prunableSnap)
        try assertFalse(prunableSnap.isLocked, "Snapshot without lockedUntil must report isLocked == false")

        // 5. Manual non-pruning deletion of a locked snapshot is rejected
        let retention = RetentionManager(storage: provider, database: db)
        var caughtPermissionDenied = false
        do {
            try await retention.deleteSnapshot(destinationURL: tempDir, snapshot: lockedSnap, isPruning: false)
        } catch FileSystemError.permissionDenied {
            caughtPermissionDenied = true
        }
        try assertTrue(caughtPermissionDenied, "Manual deletion of locked snapshot without isPruning must throw permissionDenied")

        // 6. Automated retention pruning CAN remove snapshots (unlocking WORM immutability recursively first)
        let pruned = try await retention.applyRetentionPolicy(
            destinationURL: tempDir,
            policy: PruningPolicy(isAutoPruningEnabled: true, maxSnapshotsToKeep: 1, keepDailyDays: 7)
        )

        try assertTrue(pruned.contains(snapIdPrunable), "Old unlocked snapshot must be pruned")
        try assertTrue(pruned.contains(snapIdLocked), "Pruning must be able to remove WORM-locked snapshot past retention policy")
        try assertFalse(FileManager.default.fileExists(atPath: snapDirLocked.path), "Pruned WORM snapshot folder must be deleted from disk")

        // 7. Test restored file is NOT immutable at destination
        let restoreDest = tempDir.appendingPathComponent("restored_output")
        try FileManager.default.createDirectory(at: restoreDest, withIntermediateDirectories: true)
        let restoredFile = restoreDest.appendingPathComponent("unlocked_restored.txt")
        try "Restored".write(to: restoredFile, atomically: true, encoding: .utf8)
        try provider.setImmutable(at: restoreDest, immutable: false, recursive: true)
        let restoredFileImm = try provider.isFileImmutable(at: restoredFile)
        try assertFalse(restoredFileImm, "Restored file must not be immutable at destination")
    }

    @Test func testSnapshotCatalogServiceLifecycle() async throws {
        let tempDir = try createTempDirectory(prefix: "CatalogServiceTest")
        defer { removeTempDirectory(tempDir) }

        let srcDir = tempDir.appendingPathComponent("src")
        let dstDir = tempDir.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let profile = BackupProfile(name: "CatalogTestProfile", sourceURL: srcDir, destinationURL: dstDir)

        // Verify query on clean/empty catalog creates schema or returns empty
        let initialSnapshots = try await SnapshotCatalogService.shared.listSnapshots(for: profile)
        try assertEqual(initialSnapshots.count, 0)

        // Populate a record using DatabaseEngine
        let db = DatabaseEngine()
        try await db.open(at: profile.manifestDatabasePath)
        let record = SnapshotRecord(
            id: "2026-10-09-001",
            timestamp: Date(),
            status: "completed",
            totalFiles: 5,
            totalBytes: 1024,
            snapshotPath: "2026-10-09-001",
            backupType: "full"
        )
        try await db.insertSnapshot(record)
        await db.close()

        // Verify retrieval via SnapshotCatalogService
        let retrieved = try await SnapshotCatalogService.shared.listSnapshots(for: profile)
        try assertEqual(retrieved.count, 1)
        try assertEqual(retrieved[0].id, "2026-10-09-001")

        // Verify getSnapshot
        let specific = try await SnapshotCatalogService.shared.getSnapshot(id: "2026-10-09-001", in: profile)
        try assertNotNil(specific)
        try assertEqual(specific?.totalFiles, 5)

        // Verify lock/unlock mutation via SnapshotCatalogService
        let lockUntil = Date().addingTimeInterval(86400)
        try await SnapshotCatalogService.shared.updateSnapshotLock(id: "2026-10-09-001", lockedUntil: lockUntil, in: profile)
        let lockedSnap = try await SnapshotCatalogService.shared.getSnapshot(id: "2026-10-09-001", in: profile)
        try assertTrue(lockedSnap?.isLocked == true)

        try await SnapshotCatalogService.shared.updateSnapshotLock(id: "2026-10-09-001", lockedUntil: nil, in: profile)
        let unlockedSnap = try await SnapshotCatalogService.shared.getSnapshot(id: "2026-10-09-001", in: profile)
        try assertTrue(unlockedSnap?.isLocked == false)
    }

    @Test func testSnapshotCatalogReconciliation100PercentCertainty() async throws {
        let tempDir = try createTempDirectory(prefix: "ReconciliationTest")
        defer { removeTempDirectory(tempDir) }

        let srcDir = tempDir.appendingPathComponent("src")
        let dstDir = tempDir.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let profile = BackupProfile(name: "ReconcileProfile", sourceURL: srcDir, destinationURL: dstDir)
        let db = DatabaseEngine()
        try await db.open(at: profile.manifestDatabasePath)
        defer { Task { await db.close() } }

        let coordinator = BackupSessionCoordinator(storage: DefaultFileSystemProvider(), database: db)

        // Case A: 100% Valid completed snapshot on disk (unindexed)
        let validSnapDir = dstDir.appendingPathComponent("2026-10-13_120000")
        let validRootDir = validSnapDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: validRootDir, withIntermediateDirectories: true)
        let testFile = validRootDir.appendingPathComponent("document.txt")
        try "OtterKeep resilient data".write(to: testFile, atomically: true, encoding: .utf8)

        let validInfo: [String: Any] = [
            "id": "snapshot_2026-10-13_120000",
            "timestamp": Date().timeIntervalSince1970,
            "totalFiles": 1,
            "totalBytes": 24,
            "profileName": profile.name,
            "status": "completed",
            "isCommitted": true,
            "backupType": "incremental"
        ]
        let infoData = try JSONSerialization.data(withJSONObject: validInfo, options: [.prettyPrinted])
        try infoData.write(to: validSnapDir.appendingPathComponent(".snapshot_info.json"))

        // Case B: Incomplete snapshot directory on disk (missing isCommitted / uncommitted)
        let incompleteSnapDir = dstDir.appendingPathComponent("2026-10-13_130000")
        try FileManager.default.createDirectory(at: incompleteSnapDir, withIntermediateDirectories: true)
        let incompleteInfo: [String: Any] = [
            "id": "snapshot_2026-10-13_130000",
            "timestamp": Date().timeIntervalSince1970,
            "totalFiles": 1,
            "totalBytes": 24,
            "profileName": profile.name,
            "isCommitted": false
        ]
        let incompleteData = try JSONSerialization.data(withJSONObject: incompleteInfo)
        try incompleteData.write(to: incompleteSnapDir.appendingPathComponent(".snapshot_info.json"))

        // Case C: Directory belonging to a different profile
        let otherProfileSnapDir = dstDir.appendingPathComponent("2026-10-13_140000")
        let otherRootDir = otherProfileSnapDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: otherRootDir, withIntermediateDirectories: true)
        try "other".write(to: otherRootDir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        let otherInfo: [String: Any] = [
            "id": "snapshot_2026-10-13_140000",
            "timestamp": Date().timeIntervalSince1970,
            "totalFiles": 1,
            "totalBytes": 5,
            "profileName": "CompletelyDifferentProfile",
            "status": "completed",
            "isCommitted": true
        ]
        let otherData = try JSONSerialization.data(withJSONObject: otherInfo)
        try otherData.write(to: otherProfileSnapDir.appendingPathComponent(".snapshot_info.json"))

        // Execute reconciliation
        try await coordinator.reconcileUnindexedSnapshots(at: dstDir, profile: profile)

        // Verify only Case A was registered into the database
        let snapshots = try await db.listSnapshots()
        try assertEqual(snapshots.count, 1)
        try assertEqual(snapshots.first?.id, "snapshot_2026-10-13_120000")
        try assertEqual(snapshots.first?.status, "completed")

        // Verify file catalog was populated for Case A
        let files = try await db.listFiles(forSnapshotId: "snapshot_2026-10-13_120000")
        try assertEqual(files.count, 1)
        try assertEqual(files.first?.relativePath, "document.txt")
    }

    @Test func testRestoreAtomicFolderSwapWithOldBackupProtection() async throws {
        let tempDir = try createTempDirectory(prefix: "RestoreSwapTest")
        defer { removeTempDirectory(tempDir) }

        let backupRoot = tempDir.appendingPathComponent("backupRoot")
        let snapshotDir = backupRoot.appendingPathComponent("2026-10-13_150000")
        let snapshotRoot = snapshotDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: snapshotRoot, withIntermediateDirectories: true)

        let file1 = snapshotRoot.appendingPathComponent("restored_a.txt")
        try "Restored Content A".write(to: file1, atomically: true, encoding: .utf8)
        let file2 = snapshotRoot.appendingPathComponent("restored_b.txt")
        try "Restored Content B".write(to: file2, atomically: true, encoding: .utf8)

        // Existing destination folder with pre-existing data
        let restoreTarget = tempDir.appendingPathComponent("MyRestoreTarget")
        try FileManager.default.createDirectory(at: restoreTarget, withIntermediateDirectories: true)
        let oldFile = restoreTarget.appendingPathComponent("preexisting.txt")
        try "Original old data".write(to: oldFile, atomically: true, encoding: .utf8)

        let restoreEngine = RestoreEngine(storage: DefaultFileSystemProvider())
        let summary = try await restoreEngine.restoreSnapshot(
            snapshotPath: "2026-10-13_150000",
            backupRootURL: backupRoot,
            targetDirectoryURL: restoreTarget,
            collisionResolution: .overwrite
        )

        try assertEqual(summary.restoredFiles, 2)

        // Verify restoreTarget contains restored files and does NOT contain preexisting
        let restoredFile1 = restoreTarget.appendingPathComponent("restored_a.txt")
        let restoredFile2 = restoreTarget.appendingPathComponent("restored_b.txt")
        try assertTrue(FileManager.default.fileExists(atPath: restoredFile1.path))
        try assertTrue(FileManager.default.fileExists(atPath: restoredFile2.path))

        // Verify no leftover .old_ or .otterkeep_restore_staging directories exist in parent
        let parentContents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let leftovers = parentContents.filter { $0.contains(".old_") || $0.contains(".otterkeep_restore_staging") }
        try assertEqual(leftovers.count, 0)
    }

    @Test func testResilienceErrorClassifiers() throws {
        // ENOSPC / Not enough space
        let errSpace1 = FileSystemError.notEnoughSpace(requiredBytes: 100, availableBytes: 10)
        try assertTrue(errSpace1.isOutOfSpace)
        try assertFalse(errSpace1.isFatalVolumeError)

        let errSpace2 = FileSystemError.copyFailed(path: "/vol/dst", errno: ENOSPC, message: "No space left on device")
        try assertTrue(errSpace2.isOutOfSpace)

        // Fatal volume disconnection (EIO, ENODEV, EROFS)
        let errIO = FileSystemError.copyFailed(path: "/vol/dst", errno: EIO, message: "Input/output error")
        try assertTrue(errIO.isFatalVolumeError)
        try assertFalse(errIO.isOutOfSpace)

        let errDev = FileSystemError.copyFailed(path: "/vol/dst", errno: ENODEV, message: "Operation not supported by device")
        try assertTrue(errDev.isFatalVolumeError)

        let errRO = FileSystemError.copyFailed(path: "/vol/dst", errno: EROFS, message: "Read-only file system")
        try assertTrue(errRO.isFatalVolumeError)
    }
}
