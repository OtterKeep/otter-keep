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

    @Test func test12_5_CentralDatabaseProfileStorageAndMigration() throws {
        let tempDir = try createTempDirectory(prefix: "CentralDBProfileTest")
        defer { removeTempDirectory(tempDir) }

        let centralDBPath = tempDir.appendingPathComponent("central.sqlite").path
        let centralDB = CentralDatabase(databasePath: centralDBPath)

        // 1. Save and retrieve profiles in CentralDatabase
        let profile1 = BackupProfile(
            name: "Work Documents",
            sourceURL: URL(fileURLWithPath: "/Users/test/Work"),
            destinationURL: URL(fileURLWithPath: "/Volumes/ExtBackup/Work")
        )
        let profile2 = BackupProfile(
            name: "Personal Photos",
            sourceURL: URL(fileURLWithPath: "/Users/test/Pictures"),
            destinationURL: URL(fileURLWithPath: "/Volumes/ExtBackup/Photos")
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let p1Data = try encoder.encode(profile1)
        let p2Data = try encoder.encode(profile2)

        let rec1 = CentralProfileRecord(id: profile1.id.uuidString, name: profile1.name, jsonData: String(data: p1Data, encoding: .utf8)!)
        let rec2 = CentralProfileRecord(id: profile2.id.uuidString, name: profile2.name, jsonData: String(data: p2Data, encoding: .utf8)!)

        try centralDB.saveProfileRecords([rec1, rec2])

        let loaded = try centralDB.loadProfileRecords()
        try assertEqual(loaded.count, 2)
        try assertTrue(loaded.contains(where: { $0.id == profile1.id.uuidString && $0.name == "Work Documents" }))
        try assertTrue(loaded.contains(where: { $0.id == profile2.id.uuidString && $0.name == "Personal Photos" }))

        // 2. Test JSON export/import preservation
        let exportURL = tempDir.appendingPathComponent("config_backup.json")
        let settings = AppSettings(language: .english, launchAtLogin: false, startMinimized: false, debugFileLoggingEnabled: true, finderIntegrationEnabled: true, themeMode: .system)
        try ConfigurationBackupManager.shared.exportConfiguration(
            to: exportURL,
            profiles: [profile1, profile2],
            settings: settings
        )

        try assertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        let imported = try ConfigurationBackupManager.shared.parseArchive(from: exportURL)
        try assertEqual(imported.profiles.count, 2)
        try assertEqual(imported.profiles.map(\.name).sorted(), ["Personal Photos", "Work Documents"])
        try assertTrue(imported.settings.debugFileLoggingEnabled)

        // 3. Test delete cascade in CentralDatabase
        try centralDB.deleteProfileRecord(id: profile1.id.uuidString)
        let afterDelete = try centralDB.loadProfileRecords()
        try assertEqual(afterDelete.count, 1)
        try assertEqual(afterDelete.first?.id, profile2.id.uuidString)

        centralDB.close()
    }

    @Test func test12_6_CentralDatabaseOfflineSnapshotInspection() async throws {
        let tempDir = try createTempDirectory(prefix: "OfflineInspectionTest")
        defer { removeTempDirectory(tempDir) }

        let centralDBPath = tempDir.appendingPathComponent("central.sqlite").path
        let centralDB = CentralDatabase(databasePath: centralDBPath)

        let profileId = UUID()
        let snap1 = SnapshotRecord(
            id: "snap-offline-101",
            timestamp: Date(),
            status: "completed",
            totalFiles: 2,
            totalBytes: 5000,
            snapshotPath: "2026-10-13-101",
            backupType: "incremental"
        )
        let file1 = FileCatalogRecord(
            snapshotId: "snap-offline-101",
            relativePath: "Projects/otter-keep/README.md",
            fileSize: 2000,
            modificationTime: Date(),
            inode: 5501,
            checksum: "sha256-readme",
            isDirectory: false,
            isSymlink: false
        )
        let file2 = FileCatalogRecord(
            snapshotId: "snap-offline-101",
            relativePath: "Projects/otter-keep/Package.swift",
            fileSize: 3000,
            modificationTime: Date(),
            inode: 5502,
            checksum: "sha256-package",
            isDirectory: false,
            isSymlink: false
        )

        // Cache snapshot and files into CentralDatabase
        try centralDB.cacheSnapshotWithFiles(snap1, files: [file1, file2], forProfileId: profileId.uuidString)

        // Query offline cached snapshots
        let cachedSnaps = try centralDB.listCachedSnapshots(forProfileId: profileId.uuidString)
        try assertEqual(cachedSnaps.count, 1)
        try assertEqual(cachedSnaps.first?.id, "snap-offline-101")
        try assertEqual(cachedSnaps.first?.totalBytes, 5000)

        // Query offline cached files
        let cachedFiles = try centralDB.listCachedFiles(forSnapshotId: "snap-offline-101", profileId: profileId.uuidString)
        try assertEqual(cachedFiles.count, 2)
        try assertTrue(cachedFiles.contains(where: { $0.relativePath == "Projects/otter-keep/README.md" }))

        // Search cached relative paths
        let searchedPaths = try centralDB.searchCachedRelativePaths(matching: "README", profileId: profileId.uuidString)
        try assertEqual(searchedPaths.count, 1)
        try assertEqual(searchedPaths.first, "Projects/otter-keep/README.md")

        // Query cached point-in-time version history
        let versions = try centralDB.listCachedVersions(ofRelativePath: "Projects/otter-keep/Package.swift", profileId: profileId.uuidString)
        try assertEqual(versions.count, 1)
        try assertEqual(versions.first?.snapshot.id, "snap-offline-101")
        try assertEqual(versions.first?.file.fileSize, 3000)

        // Verify SnapshotCatalogService fallback when destination drive is disconnected
        let detachedProfile = BackupProfile(
            id: profileId,
            name: "Detached External SSD",
            sourceURL: tempDir.appendingPathComponent("src"),
            destinationURL: tempDir.appendingPathComponent("nonexistent_unmounted_volume")
        )

        // Also cache into CentralDatabase.shared so SnapshotCatalogService can find it
        try CentralDatabase.shared.cacheSnapshotWithFiles(snap1, files: [file1, file2], forProfileId: profileId.uuidString)

        let offlineSnapshots = try await SnapshotCatalogService.shared.listSnapshots(for: detachedProfile)
        try assertTrue(offlineSnapshots.contains(where: { $0.id == "snap-offline-101" }))

        let offlineFiles = try await SnapshotCatalogService.shared.listFiles(forSnapshotId: "snap-offline-101", in: detachedProfile)
        try assertEqual(offlineFiles.count, 2)

        let offlineSpecific = try await SnapshotCatalogService.shared.getSnapshot(id: "snap-offline-101", in: detachedProfile)
        try assertNotNil(offlineSpecific)
        try assertEqual(offlineSpecific?.id, "snap-offline-101")

        // Clean up cached snapshot from CentralDatabase.shared
        try CentralDatabase.shared.deleteCachedSnapshot(id: "snap-offline-101", forProfileId: profileId.uuidString)
        centralDB.close()
    }
}

