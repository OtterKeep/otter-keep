//
//  Module12Tests.swift
//  OtterKeepIntegrationTests
//
//  Module 12: Backend Architecture, Layering & Catalog Services
//  Migrated verbatim from the legacy OtterKeepTestRunner harness (module 12).
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
struct Module12Tests {
    @Test func test12_1_ComplianceEvaluatorScenarios() throws {
        // 1. Local-only profile (no copy jobs enabled)
        let localProfile = BackupProfile(
            name: "Local Only",
            sourceURL: URL(fileURLWithPath: "/tmp/src"),
            destinationURL: URL(fileURLWithPath: "/tmp/dst")
        )
        let report1 = ComplianceEvaluator.evaluate(profile: localProfile)
        try assertEqual(report1.status, ComplianceStatus.localOnly)
        try assertEqual(report1.rule321Status, Rule321Compliance.localOnly(description: L10n.t(.rule321StatusLocalOnly)))
        try assertEqual(report1.copiesCount, 2)
        try assertEqual(report1.mediaTypesCount, 2)
        try assertFalse(report1.hasOffsite)

        // 2. Fully compliant profile (source + dest + S3 remote)
        var s3Dest = RemoteDestination(
            name: "AWS S3 Offsite",
            type: .s3(S3Configuration(
                endpoint: "https://s3.amazonaws.com",
                bucket: "my-bucket",
                region: "us-east-1",
                accessKeyId: "key"
            ))
        )
        s3Dest.isEnabled = true
        let compliantProfile = BackupProfile(
            name: "Compliant S3",
            sourceURL: URL(fileURLWithPath: "/tmp/src"),
            destinationURL: URL(fileURLWithPath: "/tmp/dst"),
            copyJobConfig: BackupCopyJobConfiguration(
                isEnabled: true,
                trigger: .onPrimarySuccess,
                destinations: [s3Dest]
            )
        )
        let report2 = ComplianceEvaluator.evaluate(profile: compliantProfile)
        try assertEqual(report2.status, ComplianceStatus.compliant)
        try assertEqual(report2.rule321Status, Rule321Compliance.compliant(description: "\(L10n.t(.rule321StatusCompliant)): \(s3Dest.name)"))
        try assertEqual(report2.copiesCount, 3)
        try assertEqual(report2.mediaTypesCount, 3)
        try assertTrue(report2.hasOffsite)

        // 3. Partial compliance (copy job config disabled, or destination disabled)
        var disabledDest = s3Dest
        disabledDest.isEnabled = false
        let partialProfile = BackupProfile(
            name: "Partial Profile",
            sourceURL: URL(fileURLWithPath: "/tmp/src"),
            destinationURL: URL(fileURLWithPath: "/tmp/dst"),
            copyJobConfig: BackupCopyJobConfiguration(
                isEnabled: true,
                trigger: .onPrimarySuccess,
                destinations: [disabledDest]
            )
        )
        let report3 = ComplianceEvaluator.evaluate(profile: partialProfile)
        try assertEqual(report3.status, ComplianceStatus.localOnly)
        try assertEqual(report3.rule321Status, Rule321Compliance.localOnly(description: L10n.t(.rule321StatusLocalOnly)))
    }

    @Test func test12_2_SnapshotCatalogServiceLifecycle() async throws {
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

    @Test func test12_3_CleanArchitecturePortsAndAdapters() async throws {
        let tempDir = try createTempDirectory(prefix: "CleanArchPortsTest")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("manifest.sqlite").path

        // Initialize SQLite database schema
        let db = DatabaseEngine()
        try await db.open(at: dbPath)
        await db.close()

        // Treat repositories strictly via abstract Clean Architecture ports
        let snapshotPort: SnapshotRepositoryProtocol = SQLiteSnapshotRepository(databasePath: dbPath)
        let fileCatalogPort: FileCatalogRepositoryProtocol = SQLiteFileCatalogRepository(databasePath: dbPath)

        // Verify initial empty state through port
        let initialList = try await snapshotPort.listSnapshots()
        try assertEqual(initialList.count, 0)

        // Insert snapshot record via port
        let snap1 = SnapshotRecord(
            id: "snap-clean-01",
            timestamp: Date(),
            status: "completed",
            totalFiles: 2,
            totalBytes: 2048,
            snapshotPath: "snap-clean-01",
            backupType: "incremental"
        )
        try await snapshotPort.insertSnapshot(snap1)

        // Insert file catalog entries via port
        let file1 = FileCatalogRecord(
            snapshotId: "snap-clean-01",
            relativePath: "Documents/notes.txt",
            fileSize: 1024,
            modificationTime: Date(),
            inode: 1001,
            checksum: "a1b2c3d4",
            isDirectory: false,
            isSymlink: false
        )
        let file2 = FileCatalogRecord(
            snapshotId: "snap-clean-01",
            relativePath: "Documents/summary.pdf",
            fileSize: 1024,
            modificationTime: Date(),
            inode: 1002,
            checksum: "e5f6g7h8",
            isDirectory: false,
            isSymlink: false
        )
        try await fileCatalogPort.insertBatch([file1, file2])

        // Verify Use Case execution via injected ports
        let listUseCase = ListSnapshotsUseCase(repository: snapshotPort)
        let retrievedSnaps = try await listUseCase.execute()
        try assertEqual(retrievedSnaps.count, 1)
        try assertEqual(retrievedSnaps[0].id, "snap-clean-01")

        let detailsUseCase = GetSnapshotDetailsUseCase(
            snapshotRepository: snapshotPort,
            fileRepository: fileCatalogPort
        )
        let details = try await detailsUseCase.execute(snapshotId: "snap-clean-01")
        try assertNotNil(details)
        try assertEqual(details?.snapshot.id, "snap-clean-01")
        try assertEqual(details?.files.count, 2)

        // Verify WORM lock mutation through port
        let lockDate = Date().addingTimeInterval(3600)
        try await snapshotPort.updateSnapshotLockedUntil(id: "snap-clean-01", lockedUntil: lockDate)
        let locked = try await snapshotPort.getSnapshot(id: "snap-clean-01")
        try assertTrue(locked?.isLocked == true)

        // Verify search through port
        let searchResults = try await fileCatalogPort.searchGlobal(query: "notes")
        try assertEqual(searchResults.count, 1)
        try assertEqual(searchResults[0].relativePath, "Documents/notes.txt")

        // Verify snapshot deletion via port
        try await snapshotPort.deleteSnapshot(id: "snap-clean-01")
        let afterDelete = try await snapshotPort.listSnapshots()
        try assertEqual(afterDelete.count, 0)
    }

    @Test func test12_4_RetentionPolicyDomainRules() throws {
        let now = Date()
        let snapNew = SnapshotRecord(
            id: "snap-new",
            timestamp: now,
            status: "completed",
            totalFiles: 1,
            totalBytes: 100,
            snapshotPath: "snap-new"
        )
        let snapOldUnlocked = SnapshotRecord(
            id: "snap-old-unlocked",
            timestamp: now.addingTimeInterval(-10 * 86400), // 10 days ago
            status: "completed",
            totalFiles: 1,
            totalBytes: 100,
            snapshotPath: "snap-old-unlocked",
            lockedUntil: nil
        )
        let snapOldLocked = SnapshotRecord(
            id: "snap-old-locked",
            timestamp: now.addingTimeInterval(-10 * 86400), // 10 days ago
            status: "completed",
            totalFiles: 1,
            totalBytes: 100,
            snapshotPath: "snap-old-locked",
            lockedUntil: now.addingTimeInterval(86400) // Locked for 1 more day
        )

        // Evaluate pure domain rules
        let decision = RetentionPolicyCalculator.evaluate(
            snapshots: [snapNew, snapOldUnlocked, snapOldLocked],
            now: now,
            keepDailyDays: 7
        )

        // Newest must be kept
        try assertTrue(decision.keepSnapshotIds.contains("snap-new"))
        // Locked must be kept even if older than keepDailyDays
        try assertTrue(decision.keepSnapshotIds.contains("snap-old-locked"))
        // Unlocked older than 7 days must be pruned
        try assertTrue(decision.pruneSnapshotIds.contains("snap-old-unlocked"))
        try assertFalse(decision.pruneSnapshotIds.contains("snap-old-locked"))
    }
}

