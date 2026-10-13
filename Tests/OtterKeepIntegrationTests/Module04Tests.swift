//
//  Module04Tests.swift
//  OtterKeepIntegrationTests
//
//  Module 4: Incremental Backup Lifecycle & Change Detection
//  Migrated verbatim from the legacy OtterKeepTestRunner harness (module 4).
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
struct Module04Tests {
    @Test func test4_1_GitIgnoreRuleParser() throws {
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

    @Test func test4_2_ChangeDetectorPrecision() throws {
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

    @Test func test4_3_RansomwareAnomalyGuard() throws {
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

    @Test func test4_4_EndToEndBackupLifecycle() async throws {
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

    @Test func test4_5_CooperativeFileTreeScanner() async throws {
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

    @Test func test4_6_FullSnapshotEntireRestore() async throws {
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
}
