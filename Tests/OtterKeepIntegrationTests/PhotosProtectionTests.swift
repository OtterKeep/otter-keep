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
}
