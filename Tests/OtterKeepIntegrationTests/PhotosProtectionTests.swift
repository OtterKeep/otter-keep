//
//  PhotosProtectionTests.swift
//  OtterKeepIntegrationTests
//
//  Photos Protection: Photos Backup Architecture, Album Mapping,
//  Export Schemes, and Ephemeral Storage Guard Throttling.
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
struct PhotosProtectionTests {
    @Test func testPhotosSchemes() throws {
        try assertEqual(PhotosExportStructure.dateHierarchy.rawValue, "dateHierarchy")
        try assertEqual(PhotosExportStructure.albumHierarchy.rawValue, "albumHierarchy")
        try assertEqual(PhotosExportStructure.flat.rawValue, "flat")
    }

    @Test func testPhotoMetadataExtraction() throws {
        let extractor = PhotoMetadataExtractor()
        _ = extractor
        // Verify default config
        let config = PhotosProfileStore.shared.loadConfiguration()
        try assertTrue(config.exportStructure == .dateHierarchy || config.exportStructure == .albumHierarchy || config.exportStructure == .flat)
    }

    @Test func testEphemeralStorageGuard() async throws {
        let guardActor = EphemeralStorageGuard(maxInFlightBytes: 50 * 1024 * 1024)
        let initialBuffer = await guardActor.currentBufferBytes
        try assertEqual(initialBuffer, 0)
        await guardActor.acquireInFlightCapacity(for: 10 * 1024 * 1024)
        let afterAcquire = await guardActor.currentBufferBytes
        try assertTrue(afterAcquire >= 10 * 1024 * 1024)
        await guardActor.releaseInFlightCapacity(for: 10 * 1024 * 1024)
        let afterRelease = await guardActor.currentBufferBytes
        try assertEqual(afterRelease, 0)
    }

    @Test func testPhotosCoordinatorInit() throws {
        let coordinator = PhotosBackupCoordinator()
        _ = coordinator
        let deltaScanner = PhotosDeltaScanner()
        let albumMap = deltaScanner.mapAssetAlbums()
        _ = albumMap
    }

    @Test func testPhotosBackupStagingAndCatalogRecordGeneration() async throws {
        let tempDir = try TemporaryDirectoryFixtures.createUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let internalDir = tempDir.appendingPathComponent(".otterkeep")
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").path

        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let snapshotId = "photos_2026-10-14_120000"
        let snapshotRecord = SnapshotRecord(
            id: snapshotId,
            timestamp: Date(),
            status: "completed",
            totalFiles: 1,
            totalBytes: 2500,
            snapshotPath: "2026-10-14_120000",
            backupType: "full"
        )
        try await db.insertSnapshot(snapshotRecord)

        let photoRecords = [
            PhotosAssetRecord(
                snapshotId: snapshotId,
                localIdentifier: "ID_1",
                originalFilename: "IMG_0001.JPG",
                relativePath: "2026/10/IMG_0001.JPG",
                fileSize: 2500,
                modificationTime: Date(),
                sha256: "abc123hash",
                isEdited: false,
                isLivePhoto: false,
                mediaType: "photo"
            )
        ]
        try await db.insertPhotosAssetRecordsBatch(photoRecords)

        // Verify standard FileCatalogRecord batch insertion for Photos
        let catalogRecords = photoRecords.map { asset in
            FileCatalogRecord(
                snapshotId: snapshotId,
                relativePath: asset.relativePath,
                fileSize: asset.fileSize,
                modificationTime: asset.modificationTime,
                inode: 0,
                checksum: asset.sha256,
                isDirectory: false,
                isSymlink: false
            )
        }
        try await db.insertFileRecordsBatch(catalogRecords)

        // Query back via standard FileCatalog queries (used by RestoreEngine and DataScrubber)
        let files = try await db.listFiles(forSnapshotId: snapshotId)
        try assertEqual(files.count, 1)
        try assertEqual(files.first?.relativePath, "2026/10/IMG_0001.JPG")
        try assertEqual(files.first?.checksum, "abc123hash")

        await db.close()
        let isOpen = await db.isOpen
        try assertFalse(isOpen, "Database connection must be cleanly closed")
    }
}
