//
//  DatabaseEngineTests.swift
//  OtterKeepIntegrationTests
//
//  SQLite Database Engine, Cataloging, Text Diff & Central Storage Suite
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
struct DatabaseEngineTests {
    @Test func test_SQLiteSchemaInitialization() async throws {
        let tempDir = try createTempDirectory(prefix: "DBInit")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("catalog.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)
        let open1 = await db.isOpen
        try assertTrue(open1)

        let snapshots = try await db.listSnapshots()
        try assertEqual(snapshots.count, 0)
        await db.close()
        let open2 = await db.isOpen
        try assertFalse(open2)
    }

    @Test func test_BatchCatalogIndexing() async throws {
        let tempDir = try createTempDirectory(prefix: "BatchCatalog")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("catalog.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)
        defer { Task { await db.close() } }

        let snapId = "snapshot_2026-10-07_120000"
        let snapshot = SnapshotRecord(
            id: snapId,
            timestamp: Date(),
            status: "completed",
            totalFiles: 10,
            totalBytes: 5000,
            snapshotPath: "2026-10-07_120000",
            backupType: "incremental"
        )
        try await db.insertSnapshot(snapshot)

        var records: [FileCatalogRecord] = []
        for i in 1...10 {
            records.append(FileCatalogRecord(
                snapshotId: snapId,
                relativePath: "docs/file_\(i).txt",
                fileSize: Int64(i * 100),
                modificationTime: Date(),
                inode: UInt64(1000 + i),
                checksum: "hash_\(i)",
                sampleHash: "sample_\(i)",
                isDirectory: false,
                isSymlink: false
            ))
        }
        try await db.insertFileRecordsBatch(records)

        let retrieved = try await db.listFiles(forSnapshotId: snapId)
        try assertEqual(retrieved.count, 10)
        try assertEqual(retrieved.first?.relativePath, "docs/file_1.txt")
    }

    @Test func test_SnapshotDiffEngine() async throws {
        let snap1Files = [
            FileCatalogRecord(snapshotId: "s1", relativePath: "a.txt", fileSize: 10, modificationTime: Date(timeIntervalSince1970: 100), inode: 1, isDirectory: false, isSymlink: false),
            FileCatalogRecord(snapshotId: "s1", relativePath: "b.txt", fileSize: 20, modificationTime: Date(timeIntervalSince1970: 100), inode: 2, isDirectory: false, isSymlink: false)
        ]
        let snap2Files = [
            FileCatalogRecord(snapshotId: "s2", relativePath: "a.txt", fileSize: 15, modificationTime: Date(timeIntervalSince1970: 200), inode: 1, isDirectory: false, isSymlink: false),
            FileCatalogRecord(snapshotId: "s2", relativePath: "c.txt", fileSize: 30, modificationTime: Date(timeIntervalSince1970: 200), inode: 3, isDirectory: false, isSymlink: false)
        ]

        let report = SnapshotDiffEngine.computeDiff(baseFiles: snap1Files, targetFiles: snap2Files)
        try assertEqual(report.addedCount, 1)
        try assertEqual(report.modifiedCount, 1)
        try assertEqual(report.deletedCount, 1)
        try assertTrue(report.items.contains { $0.relativePath == "c.txt" && $0.changeType == .added })
        try assertTrue(report.items.contains { $0.relativePath == "a.txt" && $0.changeType == .modified })
        try assertTrue(report.items.contains { $0.relativePath == "b.txt" && $0.changeType == .deleted })
    }

    @Test func test_TimelineQueries() async throws {
        let tempDir = try createTempDirectory(prefix: "Timeline")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("catalog.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)
        defer { Task { await db.close() } }

        try await db.insertSnapshot(SnapshotRecord(id: "s1", timestamp: Date(timeIntervalSince1970: 1000), status: "completed", totalFiles: 1, totalBytes: 10, snapshotPath: "s1"))
        try await db.insertSnapshot(SnapshotRecord(id: "s2", timestamp: Date(timeIntervalSince1970: 2000), status: "completed", totalFiles: 1, totalBytes: 20, snapshotPath: "s2"))

        try await db.insertFileRecordsBatch([
            FileCatalogRecord(snapshotId: "s1", relativePath: "report.pdf", fileSize: 10, modificationTime: Date(timeIntervalSince1970: 1000), inode: 10, checksum: "h1", isDirectory: false, isSymlink: false),
            FileCatalogRecord(snapshotId: "s2", relativePath: "report.pdf", fileSize: 20, modificationTime: Date(timeIntervalSince1970: 2000), inode: 10, checksum: "h2", isDirectory: false, isSymlink: false)
        ])

        let versions = try await db.listVersions(ofRelativePath: "report.pdf")
        try assertEqual(versions.count, 2)
        try assertEqual(versions.first?.file.fileSize, 20, "Timeline should list newest version first")
    }

    @Test func test_GlobalFileSearch() async throws {
        let tempDir = try createTempDirectory(prefix: "Search")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("catalog.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)
        defer { Task { await db.close() } }

        try await db.insertSnapshot(SnapshotRecord(id: "s1", timestamp: Date(), status: "completed", totalFiles: 2, totalBytes: 30, snapshotPath: "s1"))
        try await db.insertFileRecordsBatch([
            FileCatalogRecord(snapshotId: "s1", relativePath: "Documents/financial_q3.xlsx", fileSize: 15, modificationTime: Date(), inode: 1, isDirectory: false, isSymlink: false),
            FileCatalogRecord(snapshotId: "s1", relativePath: "Photos/beach.heic", fileSize: 15, modificationTime: Date(), inode: 2, isDirectory: false, isSymlink: false)
        ])

        let hits = try await db.searchFilesAcrossSnapshots(query: "financial")
        try assertEqual(hits.count, 1)
        try assertEqual(hits.first?.relativePath, "Documents/financial_q3.xlsx")
    }

    @Test func test_DatabaseCloseRelease() async throws {
        let tempDir = try createTempDirectory(prefix: "DBClose")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("catalog.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)
        let open1 = await db.isOpen
        try assertTrue(open1)

        // Close connection and verify release
        await db.close()
        let open2 = await db.isOpen
        try assertFalse(open2)

        // Re-open and verify safe re-initialization
        try await db.open(at: dbPath)
        let open3 = await db.isOpen
        try assertTrue(open3)
        await db.close()
        let open4 = await db.isOpen
        try assertFalse(open4)
    }

    @Test func test_CascadingSnapshotDeletion() async throws {
        let tempDir = try createTempDirectory(prefix: "DBCascade")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("catalog.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)
        defer { Task { await db.close() } }

        try await db.insertSnapshot(SnapshotRecord(id: "s_del", timestamp: Date(), status: "completed", totalFiles: 1, totalBytes: 10, snapshotPath: "s_del"))
        try await db.insertFileRecordsBatch([
            FileCatalogRecord(snapshotId: "s_del", relativePath: "orphaned.txt", fileSize: 10, modificationTime: Date(), inode: 5, isDirectory: false, isSymlink: false)
        ])

        var files = try await db.listFiles(forSnapshotId: "s_del")
        try assertEqual(files.count, 1)

        try await db.deleteSnapshot(id: "s_del")
        files = try await db.listFiles(forSnapshotId: "s_del")
        try assertEqual(files.count, 0, "Deleting snapshot must cascade delete all file catalog entries")
    }

    @Test func test_TextDiffEngineSideBySide() throws {
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

    @Test func test_CentralDatabaseOfflineSnapshotInspection() async throws {
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

        // Clean up cached snapshot from CentralDatabase
        try centralDB.deleteCachedSnapshot(id: "snap-offline-101", forProfileId: profileId.uuidString)
        centralDB.close()
    }
}
