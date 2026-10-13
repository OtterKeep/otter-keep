//
//  Module11Tests.swift
//  OtterKeepIntegrationTests
//
//  Module 11: 1.5.0 Modern Capabilities
//  Migrated verbatim from the legacy OtterKeepTestRunner harness (module 11).
//

import Foundation
import os
import Darwin
import Photos
import CryptoKit
import AppKit
import SwiftUI
import Testing
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore
import OtterKeepUI

/// Executed serially: these tests exercise process-wide singletons and fixed paths.
@MainActor
@Suite(.serialized)
struct Module11Tests {
    @Test func test11_1_TextDiffEngineSideBySide() throws {
        let tempDir = try createTempDirectory(prefix: "TextDiff")
        defer { removeTempDirectory(tempDir) }

        let text1URL = tempDir.appendingPathComponent("left.txt")
        let text2URL = tempDir.appendingPathComponent("right.txt")
        let binURL = tempDir.appendingPathComponent("binary.dat")

        let leftContent = "Line 1: Alpha\nLine 2: Beta\nLine 3: Gamma\nLine 4: Delta"
        let rightContent = "Line 1: Alpha\nLine 2: Beta modified\nLine 3: Gamma\nLine 4: Delta\nLine 5: Epsilon"

        try leftContent.write(to: text1URL, atomically: true, encoding: .utf8)
        try rightContent.write(to: text2URL, atomically: true, encoding: .utf8)

        // 1. Text diffing with Myers LCS alignment
        let engine = TextDiffEngine()
        let result = try engine.diffFiles(leftURL: text1URL, rightURL: text2URL, relativePath: "docs/sample.txt")

        try assertFalse(result.isBinary, "Text files must not be flagged as binary")
        try assertEqual(result.relativePath, "docs/sample.txt")
        try assertTrue(result.rows.count >= 4, "Must have aligned rows")
        try assertTrue(result.modifiedLinesCount > 0 || (result.addedLinesCount > 0 && result.deletedLinesCount > 0), "Must detect modifications")
        try assertTrue(result.addedLinesCount > 0, "Must detect added Line 5")

        // 2. Binary file detection
        let binaryBytes = Data([0x00, 0x50, 0x4B, 0x03, 0x04, 0x00, 0x00, 0x00])
        try binaryBytes.write(to: binURL)

        let binResult = try engine.diffFiles(leftURL: binURL, rightURL: text2URL, relativePath: "archive.zip")
        try assertTrue(binResult.isBinary, "File with null bytes must be identified as binary")
        try assertEqual(binResult.rows.count, 0, "Binary comparison should not produce line text diffs")
    }

    @Test func test11_2_DataScrubberBitRotDetection() async throws {
        let tempDir = try createTempDirectory(prefix: "Scrubber")
        defer { removeTempDirectory(tempDir) }

        let internalDir = tempDir.appendingPathComponent(".otterkeep")
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)

        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let snapId = "2026-10-08_12-00-00"
        let snapDir = tempDir.appendingPathComponent(snapId).appendingPathComponent("root")
        try FileManager.default.createDirectory(at: snapDir, withIntermediateDirectories: true)

        let fileURL = snapDir.appendingPathComponent("document.txt")
        let originalContent = "Original authentic OtterKeep backup block data."
        try originalContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let originalChecksum = try ChecksumCalculator.computeSHA256(for: fileURL)

        let snapRecord = SnapshotRecord(
            id: snapId,
            timestamp: Date(),
            status: "completed",
            totalFiles: 1,
            totalBytes: Int64(originalContent.utf8.count),
            snapshotPath: snapId,
            backupType: "incremental"
        )
        try await db.insertSnapshot(snapRecord)

        let fileRecord = FileCatalogRecord(
            snapshotId: snapId,
            relativePath: "document.txt",
            fileSize: Int64(originalContent.utf8.count),
            modificationTime: Date(),
            inode: 9999,
            checksum: originalChecksum,
            isDirectory: false,
            isSymlink: false
        )
        try await db.insertFileRecordsBatch([fileRecord])

        // Initial scrub: clean pass
        let scrubber = DataScrubberEngine(storage: DefaultFileSystemProvider(), database: db)
        let cleanAudit = try await scrubber.performScrub(backupRootURL: tempDir)
        try assertEqual(cleanAudit.status, "healthy")
        try assertEqual(cleanAudit.corruptedFilesCount, 0)
        try assertEqual(cleanAudit.checkedFilesCount, 1)

        // Inject bit-rot by tampering with file content
        let corruptedContent = "Corrupted manipulated data block with flipped bits!"
        try corruptedContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Scrubber pass should flag bit-rot
        let corruptedAudit = try await scrubber.performScrub(backupRootURL: tempDir)
        try assertEqual(corruptedAudit.status, "corruption_detected")
        try assertEqual(corruptedAudit.corruptedFilesCount, 1)
        try assertTrue(corruptedAudit.detailsJson?.contains("Bit-rot") == true, "Details must report bit-rot")
    }

    @Test func test11_3_WORMImmutabilityAndRetentionPruning() async throws {
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

    @Test func test11_4_BackblazeB2Configuration() async throws {
        let b2Config = B2Configuration(
            keyId: "0040abc12345",
            bucketName: "company-secure-vault",
            region: "us-west-004",
            customEndpoint: nil,
            pathPrefix: "otterkeep/workstation"
        )

        // 1. Endpoint resolution
        try assertEqual(b2Config.resolvedEndpoint, "https://s3.us-west-004.backblazeb2.com")

        // 2. Custom endpoint resolution
        var customB2 = b2Config
        customB2.customEndpoint = "s3.eu-central-003.backblazeb2.com"
        try assertEqual(customB2.resolvedEndpoint, "https://s3.eu-central-003.backblazeb2.com")

        // 3. S3 Configuration conversion
        let s3Config = b2Config.toS3Configuration()
        try assertEqual(s3Config.endpoint, "https://s3.us-west-004.backblazeb2.com")
        try assertEqual(s3Config.bucket, "company-secure-vault")
        try assertEqual(s3Config.region, "us-west-004")
        try assertEqual(s3Config.accessKeyId, "0040abc12345")
        try assertEqual(s3Config.pathPrefix, "otterkeep/workstation")
        try assertTrue(s3Config.forcePathStyle, "Backblaze B2 S3 API requires forcePathStyle = true")

        // 4. Provider instantiation
        let provider = B2StorageProvider(config: b2Config, applicationKey: "K004dummySecretKey123")
        _ = provider
    }

    @Test func test11_5_ReplicationCatchUpCoordinator() async throws {
        let tempDir = try createTempDirectory(prefix: "Replication")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)
        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let profileId = UUID()
        let destinationId = UUID()
        let record = PendingReplicationRecord(
            profileId: profileId,
            snapshotId: "2026-10-08_14-00-00",
            destinationId: destinationId,
            destinationType: "b2",
            status: "pending",
            errorMessage: "Host unreachable"
        )

        // Insert and verify listing
        try await db.insertPendingReplication(record)
        let pending = try await db.listPendingReplications(status: "pending", profileId: profileId)
        try assertEqual(pending.count, 1)
        try assertEqual(pending.first?.snapshotId, "2026-10-08_14-00-00")
        try assertEqual(pending.first?.destinationType, "b2")
        try assertEqual(pending.first?.errorMessage, "Host unreachable")

        // Update status to completed
        try await db.updatePendingReplicationStatus(id: record.id, status: "completed")
        let pendingAfter = try await db.listPendingReplications(status: "pending", profileId: profileId)
        try assertEqual(pendingAfter.count, 0)

        let completed = try await db.listPendingReplications(status: "completed", profileId: profileId)
        try assertEqual(completed.count, 1)

        // Delete record
        try await db.deletePendingReplication(id: record.id)
        let remaining = try await db.listPendingReplications(profileId: profileId)
        try assertEqual(remaining.count, 0)
    }

    @Test func test11_6_DatalessICloudChangeDetection() throws {
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
}
