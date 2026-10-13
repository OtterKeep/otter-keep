//
//  CleanArchitectureTests.swift
//  OtterKeepIntegrationTests
//
//  Clean Architecture & Layer Integrity: Domain Entities & Business Rules,
//  Repository Ports & Adapters, DTO Data Transfer, Use Cases, and Central Profile Storage.
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
struct CleanArchitectureTests {
    @Test func testCleanArchitecturePortsAndAdapters() async throws {
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

    @Test func testRetentionPolicyDomainRules() throws {
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

    @Test func testCentralDatabaseProfileStorageAndMigration() throws {
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

    @Test func testDTODataTransferAndMapping() throws {
        let now = Date()
        let lockTime = now.addingTimeInterval(7200)

        // 1. SnapshotRecord <-> SnapshotDTO mapping
        let snapEntity = SnapshotRecord(
            id: "snap-dto-01",
            timestamp: now,
            status: "completed",
            totalFiles: 42,
            totalBytes: 1048576,
            snapshotPath: "2026-10-13-dto",
            backupType: "incremental",
            lockedUntil: lockTime
        )
        let snapDTO = SnapshotDTO(from: snapEntity)
        try assertEqual(snapDTO.id, "snap-dto-01")
        try assertEqual(snapDTO.totalFiles, 42)
        try assertEqual(snapDTO.totalBytes, 1048576)
        try assertTrue(snapDTO.isLocked)
        try assertEqual(snapDTO.backupType, "incremental")

        let domainMapped = snapDTO.toDomain()
        try assertEqual(domainMapped.id, snapEntity.id)
        try assertEqual(domainMapped.totalFiles, snapEntity.totalFiles)
        try assertEqual(domainMapped.totalBytes, snapEntity.totalBytes)
        try assertEqual(domainMapped.lockedUntil, snapEntity.lockedUntil)

        // 2. FileCatalogRecord <-> FileCatalogDTO mapping
        let fileEntity = FileCatalogRecord(
            snapshotId: "snap-dto-01",
            relativePath: "Projects/app.swift",
            fileSize: 4096,
            modificationTime: now,
            inode: 12345,
            checksum: "a1b2c3d4e5f6",
            sampleHash: "s1s2",
            isDirectory: false,
            isSymlink: false
        )
        let fileDTO = FileCatalogDTO(from: fileEntity)
        try assertEqual(fileDTO.relativePath, "Projects/app.swift")
        try assertEqual(fileDTO.fileSize, 4096)
        try assertEqual(fileDTO.checksum, "a1b2c3d4e5f6")
        try assertFalse(fileDTO.isDirectory)

        let fileDomainMapped = fileDTO.toDomain()
        try assertEqual(fileDomainMapped.relativePath, fileEntity.relativePath)
        try assertEqual(fileDomainMapped.fileSize, fileEntity.fileSize)
        try assertEqual(fileDomainMapped.checksum, fileEntity.checksum)

        // 3. SnapshotDetailsDTO aggregation mapping
        let detailsDTO = SnapshotDetailsDTO(snapshot: snapDTO, files: [fileDTO])
        try assertEqual(detailsDTO.snapshot.id, "snap-dto-01")
        try assertEqual(detailsDTO.files.count, 1)
        try assertEqual(detailsDTO.files[0].relativePath, "Projects/app.swift")

        let detailsDomain = detailsDTO.toDomain()
        try assertEqual(detailsDomain.snapshot.id, "snap-dto-01")
        try assertEqual(detailsDomain.files.count, 1)

        // 4. ProfileConfigurationDTO mapping
        let profile = BackupProfile(
            name: "DTO Test Profile",
            sourceURL: URL(fileURLWithPath: "/tmp/src"),
            destinationURL: URL(fileURLWithPath: "/tmp/dst")
        )
        let profileDTO = profile.toDTO()
        try assertEqual(profileDTO.id, profile.id)
        try assertEqual(profileDTO.name, "DTO Test Profile")
        try assertEqual(profileDTO.sourcePath, "/tmp/src")
        try assertEqual(profileDTO.destinationPath, "/tmp/dst")

        let profileFromDTO = BackupProfile(from: profileDTO)
        try assertEqual(profileFromDTO.id, profile.id)
        try assertEqual(profileFromDTO.name, profile.name)

        // 5. RetentionEvaluationDTO mapping
        let decision = RetentionDecision(
            keepSnapshotIds: Set(["snap-keep-1", "snap-keep-2"]),
            pruneSnapshotIds: ["snap-prune-1"]
        )
        let retentionDTO = RetentionEvaluationDTO(from: decision)
        try assertEqual(retentionDTO.keepSnapshotIds.count, 2)
        try assertEqual(retentionDTO.pruneSnapshotIds.count, 1)
        try assertEqual(retentionDTO.toDomain().keepSnapshotIds, decision.keepSnapshotIds)
    }

    @Test func testSnapshotCatalogUseCasesWithDTOs() async throws {
        let tempDir = try createTempDirectory(prefix: "DTOCatalogUseCaseTest")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("manifest.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)
        await db.close()

        let snapshotPort: SnapshotRepositoryProtocol = SQLiteSnapshotRepository(databasePath: dbPath)
        let fileCatalogPort: FileCatalogRepositoryProtocol = SQLiteFileCatalogRepository(databasePath: dbPath)

        let snap1 = SnapshotRecord(
            id: "snap-dto-usecase-01",
            timestamp: Date(),
            status: "completed",
            totalFiles: 1,
            totalBytes: 512,
            snapshotPath: "snap-dto-usecase-01",
            backupType: "full"
        )
        try await snapshotPort.insertSnapshot(snap1)

        let file1 = FileCatalogRecord(
            snapshotId: "snap-dto-usecase-01",
            relativePath: "index.html",
            fileSize: 512,
            modificationTime: Date(),
            inode: 2001,
            checksum: "deadbeef",
            isDirectory: false,
            isSymlink: false
        )
        try await fileCatalogPort.insertBatch([file1])

        // Verify Use Case DTO retrieval
        let listUseCase = ListSnapshotsUseCase(repository: snapshotPort)
        let dtos: [SnapshotDTO] = try await listUseCase.executeDTOs()
        try assertEqual(dtos.count, 1)
        try assertEqual(dtos[0].id, "snap-dto-usecase-01")
        try assertEqual(dtos[0].totalFiles, 1)

        let detailsUseCase = GetSnapshotDetailsUseCase(
            snapshotRepository: snapshotPort,
            fileRepository: fileCatalogPort
        )
        let detailsDTO: SnapshotDetailsDTO? = try await detailsUseCase.executeDTO(snapshotId: "snap-dto-usecase-01")
        try assertNotNil(detailsDTO)
        try assertEqual(detailsDTO?.snapshot.id, "snap-dto-usecase-01")
        try assertEqual(detailsDTO?.files.count, 1)
        try assertEqual(detailsDTO?.files[0].relativePath, "index.html")
    }
}
