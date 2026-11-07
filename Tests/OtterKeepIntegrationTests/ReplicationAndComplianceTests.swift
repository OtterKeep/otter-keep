//
//  ReplicationAndComplianceTests.swift
//  OtterKeepIntegrationTests
//
//  Replication & 3-2-1 Compliance: 3-2-1 Compliance Rule Evaluation,
//  Offsite Copy Job Verification, and Catch-Up Replication Coordination.
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
struct ReplicationAndComplianceTests {
    @Test func testComplianceEvaluatorScenarios() throws {
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

    @Test func testReplicationCatchUpCoordinator() async throws {
        let tempDir = try createTempDirectory(prefix: "Replication")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)
        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let profileId = UUID()
        let destinationId = UUID()
        let record = PendingReplicationRecord(
            profileId: profileId,
            snapshotId: "2026-10-08_14-00-00",
            destinationId: destinationId,
            destinationType: "b2",
            status: "pending",
            errorMessage: "Host unreachable"
        )

        // Insert and verify listing
        try await db.insertPendingReplication(record)
        let pending = try await db.listPendingReplications(status: "pending", profileId: profileId)
        try assertEqual(pending.count, 1)
        try assertEqual(pending.first?.snapshotId, "2026-10-08_14-00-00")
        try assertEqual(pending.first?.destinationType, "b2")
        try assertEqual(pending.first?.errorMessage, "Host unreachable")

        // Update status to completed
        try await db.updatePendingReplicationStatus(id: record.id, status: "completed")
        let pendingAfter = try await db.listPendingReplications(status: "pending", profileId: profileId)
        try assertEqual(pendingAfter.count, 0)

        let completed = try await db.listPendingReplications(status: "completed", profileId: profileId)
        try assertEqual(completed.count, 1)

        // Delete record
        try await db.deletePendingReplication(id: record.id)
        let remaining = try await db.listPendingReplications(profileId: profileId)
        try assertEqual(remaining.count, 0)
    }
}
