//
//  Module03Tests.swift
//  OtterKeepIntegrationTests
//
//  Module 3: SQLite Database Engine, Transactions & Crash Consistency
//  Migrated verbatim from the legacy OtterKeepTestRunner harness (module 3).
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
struct Module03Tests {
    @Test func test3_1_SQLiteSchemaInitialization() async throws {
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

    @Test func test3_2_BatchCatalogIndexing() async throws {
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

    @Test func test3_3_SnapshotDiffEngine() async throws {
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

    @Test func test3_4_TimelineQueries() async throws {
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

    @Test func test3_5_GlobalFileSearch() async throws {
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

    @Test func test3_6_DatabaseCloseRelease() async throws {
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

    @Test func test3_7_CascadingSnapshotDeletion() async throws {
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
}
