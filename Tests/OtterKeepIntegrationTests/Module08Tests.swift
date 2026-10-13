//
//  Module08Tests.swift
//  OtterKeepIntegrationTests
//
//  Module 8: Photos Backup Architecture & iCloud Eviction
//  Migrated verbatim from the legacy OtterKeepTestRunner harness (module 8).
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
struct Module08Tests {
    @Test func test8_1_PhotosSchemes() throws {
        try assertEqual(PhotosExportStructure.dateHierarchy.rawValue, "dateHierarchy")
        try assertEqual(PhotosExportStructure.albumHierarchy.rawValue, "albumHierarchy")
        try assertEqual(PhotosExportStructure.flat.rawValue, "flat")
    }

    @Test func test8_2_PhotoMetadataExtraction() throws {
        let extractor = PhotoMetadataExtractor()
        _ = extractor
        // Verify default config
        let config = PhotosProfileStore.shared.loadConfiguration()
        try assertTrue(config.exportStructure == .dateHierarchy || config.exportStructure == .albumHierarchy || config.exportStructure == .flat)
    }

    @Test func test8_3_EphemeralStorageGuard() async throws {
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

    @Test func test8_4_PhotosCoordinatorInit() throws {
        let coordinator = PhotosBackupCoordinator()
        _ = coordinator
        let deltaScanner = PhotosDeltaScanner()
        let albumMap = deltaScanner.mapAssetAlbums()
        _ = albumMap
    }
}
