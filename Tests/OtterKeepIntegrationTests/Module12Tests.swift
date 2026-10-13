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
}
