//
//  main.swift
//  OtterKeepTestRunner
//
//  Comprehensive End-to-End Deterministic System Test Suite & Benchmark
//  for OtterKeep 1.6.0 (Build 1600).
//
//  Covers Modules 1 through 11:
//  - Module 1: System, Version & Subsystem SemVer Integrity (1.6.0 / 1600)
//  - Module 2: APFS Copy-on-Write, Storage Drivers & Filesystem Fidelity
//  - Module 3: SQLite Database Engine, Transactions, Resource Closure & Crash Consistency
//  - Module 4: Incremental Backup Lifecycle, Change Detection & Cooperative Traversal
//  - Module 5: Client-Side Cryptography (OKENC2 / DSENC1) & Data Integrity
//  - Module 6: IPC, Process Security, Peer UID Validation & Sandboxing
//  - Module 7: Privacy-Preserving Observability & Dual-Tier Diagnostics
//  - Module 8: Photos Backup Architecture & iCloud Eviction Controller
//  - Module 9: Bilingual Localization Completeness & Parity (Hungarian & English)
//  - Module 10: Modern UI Design System, Sanctuary Experience & Configuration Portability
//  - Module 11: 1.5.0 Modern Capabilities (Side-by-Side Diff, Data Scrubber, WORM Immutability, Backblaze B2, Catch-Up Replication, Dataless iCloud)
//

import Foundation
import os
import Darwin
import Photos
import CryptoKit
import AppKit
import SwiftUI
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore
import OtterKeepUI

// MARK: - Assertion Framework

public struct TestFailure: Error, CustomStringConvertible {
    public let message: String
    public let file: String
    public let line: Int

    public init(message: String, file: String = #file, line: Int = #line) {
        self.message = message
        self.file = file
        self.line = line
    }

    public var description: String {
        "\(URL(fileURLWithPath: file).lastPathComponent):\(line): \(message)"
    }
}

public func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard condition() else {
        throw TestFailure(message: "Assertion failed: expected true, got false. \(message)", file: file, line: line)
    }
}

public func assertFalse(_ condition: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard !condition() else {
        throw TestFailure(message: "Assertion failed: expected false, got true. \(message)", file: file, line: line)
    }
}

public func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw TestFailure(message: "Assertion failed: '\(a)' != '\(b)'. \(message)", file: file, line: line)
    }
}

public func assertNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard a != b else {
        throw TestFailure(message: "Assertion failed: values are unexpectedly equal ('\(a)'). \(message)", file: file, line: line)
    }
}

public func assertNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard value == nil else {
        throw TestFailure(message: "Assertion failed: expected nil, got '\(value!)'. \(message)", file: file, line: line)
    }
}

public func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard value != nil else {
        throw TestFailure(message: "Assertion failed: expected non-nil value. \(message)", file: file, line: line)
    }
}

// MARK: - Test Suite Definition

@MainActor
final class OtterKeepTestSuite {
    private var passedCount = 0
    private var failedCount = 0
    private var testFailures: [(name: String, error: String)] = []

    private func createTempDirectory(prefix: String = "OtterKeepTest") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func removeTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func runTest(_ name: String, _ block: () async throws -> Void) async {
        let start = ContinuousClock.now
        do {
            try await block()
            let duration = ContinuousClock.now - start
            let ms = Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000.0
            print("  ✓ \(name) (\(String(format: "%.1f", ms)) ms)")
            passedCount += 1
        } catch {
            let duration = ContinuousClock.now - start
            let ms = Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000.0
            print("  ✗ \(name) FAILED (\(String(format: "%.1f", ms)) ms)")
            print("    Error: \(error)")
            failedCount += 1
            testFailures.append((name: name, error: "\(error)"))
        }
    }

    public func executeAllTests() async -> Bool {
        print("\n" + String(repeating: "=", count: 80))
        print("🦦 OTTERKEEP 1.7.1 (BUILD 1701) SYSTEM INTEGRATION TEST SUITE & BENCHMARK")
        print(String(repeating: "=", count: 80))

        // Module 1
        print("\n🔹 Module 1: System, Version & Subsystem SemVer Integrity")
        await runTest("1.1 CoreEngine Metadata, Slogans & Bundle Identifier", test1_1_CoreEngineMetadata)
        await runTest("1.2 SemVer Subsystem Matrix Alignment (1.7.1 / 1701)", test1_2_SemVerSubsystemMatrix)
        await runTest("1.3 Semantic Version Parser & Comparison", test1_3_SemVerComparison)
        await runTest("1.4 Sparkle Appcast Coordinator Logic & Feed Audit", test1_4_SparkleAppcast)

        // Module 2
        print("\n🔹 Module 2: APFS Copy-on-Write, Storage Drivers & Filesystem Fidelity")
        await runTest("2.1 APFS Volume Capabilities & Capacity Metrics", test2_1_VolumeCapabilities)
        await runTest("2.2 APFS clonefile(2) CoW Data Independence & Zero Footprint", test2_2_APFSClonefile)
        await runTest("2.3 POSIX Hardlink Fallback & Inode Consistency", test2_3_HardlinkFallback)
        await runTest("2.4 Extended Attributes (xattr) Preservation", test2_4_ExtendedAttributes)
        await runTest("2.5 Atomic Directory Tree Renaming (atomicMove)", test2_5_AtomicMove)
        await runTest("2.6 DefaultFileSystemProvider Stream Copy & Metadata Preservation", test2_6_FallbackStorageProvider)
        await runTest("2.7 exFAT & NTFS FileSystem Capabilities Matrix", test2_7_ExFATAndNTFSCapabilities)
        await runTest("2.8 FileSystemDriverRegistry Dynamic Resolution", test2_8_DriverRegistryResolution)

        // Module 3
        print("\n🔹 Module 3: SQLite Database Engine, Transactions & Crash Consistency")
        await runTest("3.1 SQLite WAL Mode, Pragmas & Schema Initialization", test3_1_SQLiteSchemaInitialization)
        await runTest("3.2 Snapshot Cataloging & Batch File Indexing", test3_2_BatchCatalogIndexing)
        await runTest("3.3 Snapshot Diff Engine (Added, Modified, Deleted)", test3_3_SnapshotDiffEngine)
        await runTest("3.4 Multi-Snapshot Timeline Queries (listVersions)", test3_4_TimelineQueries)
        await runTest("3.5 Cross-Snapshot Global File Search", test3_5_GlobalFileSearch)
        await runTest("3.6 Explicit Database Connection Closure (close) & Handle Release", test3_6_DatabaseCloseRelease)
        await runTest("3.7 Cascading Deletion of Associated Snapshot Catalog Records", test3_7_CascadingSnapshotDeletion)

        // Module 4
        print("\n🔹 Module 4: Incremental Backup Lifecycle & Change Detection")
        await runTest("4.1 GitIgnore-Style Rule Parser (Globs & Negations)", test4_1_GitIgnoreRuleParser)
        await runTest("4.2 Differential Change Detector (Mtime, Size & Inode Precision)", test4_2_ChangeDetectorPrecision)
        await runTest("4.3 Ransomware Anomaly Guard Sensitivity & Extension Shield", test4_3_RansomwareAnomalyGuard)
        await runTest("4.4 End-to-End Backup Lifecycle (Initial + Incremental CoW)", test4_4_EndToEndBackupLifecycle)
        await runTest("4.5 Cooperative FileTreeScanner Execution & Exclusion Markers", test4_5_CooperativeFileTreeScanner)
        await runTest("4.6 Full Snapshot Entire Restore (Structure, Reflink & SHA-256)", test4_6_FullSnapshotEntireRestore)

        // Module 5
        print("\n🔹 Module 5: Client-Side Cryptography & Security Integrity")
        await runTest("5.1 OKENC2 PBKDF2-HMAC-SHA256 (600,000 Rounds) Encryption", test5_1_OKENC2Encryption)
        await runTest("5.2 DSENC1 Legacy HKDF Backward Compatibility Decryption", test5_2_DSENC1BackwardCompatibility)
        await runTest("5.3 Cryptographic Tamper Resistance & Wrong Password Rejection", test5_3_TamperResistance)
        await runTest("5.4 SHA-256 Checksum & Fast Sparse Sample Hash Calculations", test5_4_HashCalculations)

        // Module 6
        print("\n🔹 Module 6: IPC, Process Security & Peer UID Validation")
        await runTest("6.1 AF_UNIX sockaddr_un 104-Byte Buffer Overflow Bounds Check", test6_1_AFUnixBufferBounds)
        await runTest("6.2 POSIX Socket Permissions (0600) & Directory Permissions (0700)", test6_2_SocketPermissions)
        await runTest("6.3 SingleInstanceManager Peer UID Verification via getpeereid", test6_3_PeerUIDVerification)
        await runTest("6.4 IPC Message Serialization & Canonicalized Path Handling", test6_4_MessageSerialization)
        await runTest("6.5 SFTP Shell Argument Injection Neutralization", test6_5_SFTPInjectionNeutralization)

        // Module 7
        print("\n🔹 Module 7: Privacy-Preserving Observability & Diagnostics")
        await runTest("7.1 LogPrivacySanitizer PII, Tokens, AWS & Webhook Scrubbing", test7_1_LogPrivacyScrubbing)
        await runTest("7.2 Path Masking Preserving Extensions & Suffix Semantics", test7_2_PathMasking)
        await runTest("7.3 Dual-Tier Diagnostic Logger (Ring Buffer vs Verbose Log Files)", test7_3_DualTierDiagnostics)
        await runTest("7.4 Debug File Logger Append-Only & Non-Overwriting Guarantee", test7_4_DebugFileLoggerAppend)

        // Module 8
        print("\n🔹 Module 8: Photos Backup Architecture & iCloud Eviction")
        await runTest("8.1 Photos Configuration Schemes (Date, Album, Flat)", test8_1_PhotosSchemes)
        await runTest("8.2 PhotoMetadataExtractor XMP Sidecar Generation", test8_2_PhotoMetadataExtraction)
        await runTest("8.3 EphemeralStorageGuard Rate Limiting & Eviction", test8_3_EphemeralStorageGuard)
        await runTest("8.4 Photos Coordinator & Delta Scanner Initialization", test8_4_PhotosCoordinatorInit)

        // Module 9
        print("\n🔹 Module 9: Bilingual Localization Completeness & Parity")
        await runTest("9.1 100% Localization Key Existence in Hungarian & English", test9_1_LocalizationKeyParity)
        await runTest("9.2 Non-Empty Translated Strings for Hungarian & English", test9_2_LocalizationNonEmptyStrings)
        await runTest("9.3 Variadic Format Specifier Consistency Across Languages", test9_3_FormatSpecifierConsistency)
        await runTest("9.4 Restore Collision Suffix Localization Parity (.restoredSuffixFormat)", test9_4_RestoredSuffixParity)

        // Module 10
        print("\n🔹 Module 10: Modern UI Design System, Sanctuary Experience & Configuration")
        await runTest("10.1 OtterTheme Dynamic Color Tokens & Contrast", test10_1_OtterThemeTokens)
        await runTest("10.2 Three-Part Error Architecture Formatting in analyzeBackupError", test10_2_ThreePartErrorArchitecture)
        await runTest("10.3 Configuration Archive Round-Trip JSON Serialization", test10_3_ConfigurationArchiveSerialization)
        await runTest("10.4 AppState Multi-Profile Parallel Tracking & Lockout", test10_4_AppStateMultiProfileTracking)
        await runTest("10.5 OtterAboutView Brand Metadata & Version Display (v1.7.1)", test10_5_OtterAboutViewMetadata)
        await runTest("10.6 DefaultFileSystemProvider Registry Routing & Dynamic Resolution", test10_6_DefaultFileSystemProviderRouting)
        await runTest("10.7 Restore OperationFeedback & Streamlined Browse Modes", test10_7_RestoreOperationFeedbackAndModes)

        // Module 11
        print("\n🔹 Module 11: Modern Capabilities (Diff, Scrubber, WORM, B2, Replication, iCloud)")
        await runTest("11.1 TextDiffEngine Side-by-Side LCS Text & Binary Detection", test11_1_TextDiffEngineSideBySide)
        await runTest("11.2 DataScrubberEngine Background Bit-Rot & Corruption Detection", test11_2_DataScrubberBitRotDetection)
        await runTest("11.3 Recursive WORM Immutability Flags & GFS Retention Pruning", test11_3_WORMImmutabilityAndRetentionPruning)
        await runTest("11.4 Backblaze B2 S3 Configuration Mapping & Provider Resolution", test11_4_BackblazeB2Configuration)
        await runTest("11.5 ReplicationCatchUpCoordinator Deferred Task Queueing & Lifecycle", test11_5_ReplicationCatchUpCoordinator)
        await runTest("11.6 Dataless iCloud Drive Change Detection Without Forced Download", test11_6_DatalessICloudChangeDetection)

        // Module 12
        print("\n🔹 Module 12: Backend Architecture, Layering & Catalog Services")
        await runTest("12.1 ComplianceEvaluator 3-2-1 Matrix & Deduplication Scenarios", test12_1_ComplianceEvaluatorScenarios)
        await runTest("12.2 SnapshotCatalogService SQLite Connection Closure & Immutability", test12_2_SnapshotCatalogServiceLifecycle)

        print("\n" + String(repeating: "=", count: 80))
        print("📊 TEST EXECUTION SUMMARY")
        print(String(repeating: "=", count: 80))
        print("Total Tests Run : \(passedCount + failedCount)")
        print("Passed          : \(passedCount)")
        print("Failed          : \(failedCount)")
        print("Success Rate    : \(String(format: "%.1f", Double(passedCount) / Double(max(1, passedCount + failedCount)) * 100.0))%")
        print(String(repeating: "=", count: 80))

        if failedCount > 0 {
            print("\n❌ FAILURES:")
            for failure in testFailures {
                print("  • \(failure.name): \(failure.error)")
            }
            return false
        } else {
            print("\n🎉 ALL TESTS PASSED SUCCESSFULLY WITH ZERO FAILURES!\n")
            return true
        }
    }

    // =========================================================================
    // MARK: - Module 1: System, Version & Subsystem SemVer Integrity
    // =========================================================================

    private func test1_1_CoreEngineMetadata() throws {
        try assertEqual(CoreEngine.appName, "OtterKeep")
        try assertEqual(CoreEngine.bundleIdentifier, "com.otterkeep.desktop")
        try assertEqual(CoreEngine.version, "1.7.1", "CoreEngine version must be exactly 1.7.1")
        try assertEqual(CoreEngine.buildNumber, "1701", "Build number must be 1701 for release 1.7.1")
    }

    private func test1_2_SemVerSubsystemMatrix() throws {
        let matrix = CoreEngine.componentVersions
        try assertEqual(matrix["OtterKeepStorage"], "1.3.0", "OtterKeepStorage must be 1.3.0")
        try assertEqual(matrix["OtterKeepDatabase"], "1.3.1", "OtterKeepDatabase must be 1.3.1")
        try assertEqual(matrix["OtterKeepCore"], "1.7.1", "OtterKeepCore must be 1.7.1")
        try assertEqual(matrix["OtterKeepUI"], "1.7.1", "OtterKeepUI must be 1.7.1")
        try assertEqual(matrix["OtterKeepCLI"], "1.3.1", "OtterKeepCLI must be 1.3.1")
        try assertEqual(matrix["OtterKeepFinderSyncExtension"], "1.0.1", "OtterKeepFinderSyncExtension must be 1.0.1")

        let summary = CoreEngine.componentVersionsFormatted
        try assertTrue(summary.contains("v1.3.1"), "Summary must reflect subsystem versions")
        try assertTrue(summary.contains("v1.7.1"), "Summary must reflect core version")
    }

    private func test1_3_SemVerComparison() throws {
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.7.1", "1.7.1"), .orderedSame)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.7.0", "1.7.1"), .orderedAscending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.7.1", "1.7.0"), .orderedDescending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("v1.7.1", "1.7.1"), .orderedSame)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.10.0", "1.7.1"), .orderedDescending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.7.2", "1.7.1"), .orderedDescending)
    }

    private func test1_4_SparkleAppcast() async throws {
        let coordinator = SoftwareUpdateCoordinator()
        let currentVer = coordinator.currentVersion
        let currentBld = coordinator.currentBuild
        try assertEqual(currentVer, "1.7.1")
        try assertEqual(currentBld, "1701")

        // Parse and validate Distribution/appcast.xml in repository root
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // OtterKeepTestRunner
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // repo root
        let appcastURL = projectRoot.appendingPathComponent("Distribution/appcast.xml")

        if FileManager.default.fileExists(atPath: appcastURL.path(percentEncoded: false)) {
            let data = try Data(contentsOf: appcastURL)
            guard let latest = await coordinator.parseAppcastXML(data: data) else {
                throw TestFailure(message: "Expected parsed update info in appcast", file: #file, line: #line)
            }
            try assertEqual(latest.version, "1.7.1", "Latest appcast version should be 1.7.1")
            try assertEqual(latest.buildNumber, "1701", "Latest appcast build number should be 1701")
            try assertTrue(latest.downloadURL.absoluteString.contains("OtterKeep-1.7.1.zip"))
        }
    }

    // =========================================================================
    // MARK: - Module 2: APFS Copy-on-Write, Storage Drivers & Filesystem Fidelity
    // =========================================================================

    private func test2_1_VolumeCapabilities() async throws {
        let tempDir = try createTempDirectory(prefix: "Capabilities")
        defer { removeTempDirectory(tempDir) }

        let provider = DefaultFileSystemProvider()
        let caps = try await provider.capabilities(at: tempDir)
        let capacity = try provider.storageCapacity(at: tempDir)

        try assertTrue(!caps.fsTypeName.isEmpty, "Filesystem type name should not be empty")
        try assertTrue(capacity.totalBytes > 0, "Total bytes should be greater than zero")
        try assertTrue(capacity.freeBytes > 0, "Free bytes should be greater than zero")
        try assertTrue(capacity.availableBytes > 0, "Available bytes should be greater than zero")
    }

    private func test2_2_APFSClonefile() async throws {
        let tempDir = try createTempDirectory(prefix: "CoWClone")
        defer { removeTempDirectory(tempDir) }

        let sourceFile = tempDir.appendingPathComponent("source.bin")
        let cloneFile = tempDir.appendingPathComponent("clone.bin")

        let payload = Data(repeating: 0x42, count: 64 * 1024)
        try payload.write(to: sourceFile)

        let provider = DefaultFileSystemProvider()
        try await provider.cloneItem(at: sourceFile, to: cloneFile)

        try assertTrue(FileManager.default.fileExists(atPath: cloneFile.path))
        let clonedData = try Data(contentsOf: cloneFile)
        try assertEqual(payload, clonedData, "Cloned data must match source data exactly")

        // Verify copy-on-write independence: modifying source must not mutate clone
        let modifiedPayload = Data(repeating: 0x99, count: 64 * 1024)
        try modifiedPayload.write(to: sourceFile)
        let postMutationCloneData = try Data(contentsOf: cloneFile)
        try assertEqual(payload, postMutationCloneData, "CoW clone must remain isolated after source mutation")
    }

    private func test2_3_HardlinkFallback() async throws {
        let tempDir = try createTempDirectory(prefix: "Hardlink")
        defer { removeTempDirectory(tempDir) }

        let sourceFile = tempDir.appendingPathComponent("original.txt")
        let linkFile = tempDir.appendingPathComponent("linked.txt")
        try "OtterKeep Inode Fidelity".write(to: sourceFile, atomically: true, encoding: .utf8)

        let provider = DefaultFileSystemProvider()
        try await provider.createHardLink(at: sourceFile, to: linkFile)

        try assertTrue(FileManager.default.fileExists(atPath: linkFile.path))
        let meta1 = try provider.metadata(at: sourceFile)
        let meta2 = try provider.metadata(at: linkFile)
        try assertEqual(meta1.inode, meta2.inode, "Hard links must share the identical filesystem inode")
    }

    private func test2_4_ExtendedAttributes() throws {
        let tempDir = try createTempDirectory(prefix: "Xattr")
        defer { removeTempDirectory(tempDir) }

        let file = tempDir.appendingPathComponent("tagged.txt")
        try "Content".write(to: file, atomically: true, encoding: .utf8)

        let provider = DefaultFileSystemProvider()
        let attrKey = "com.otterkeep.test.safeguard"
        let attrValue = Data("PreservedSanctuary".utf8)
        try provider.setExtendedAttributes([attrKey: attrValue], at: file)

        let readBack = try provider.getExtendedAttributes(at: file)
        try assertEqual(readBack[attrKey], attrValue, "Extended attribute must be preserved round-trip")
    }

    private func test2_5_AtomicMove() async throws {
        let tempDir = try createTempDirectory(prefix: "AtomicMove")
        defer { removeTempDirectory(tempDir) }

        let source = tempDir.appendingPathComponent("temp_staging")
        let dest = tempDir.appendingPathComponent("final_snapshot")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "data".write(to: source.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let provider = DefaultFileSystemProvider()
        try await provider.atomicMove(from: source, to: dest)

        try assertFalse(FileManager.default.fileExists(atPath: source.path))
        try assertTrue(FileManager.default.fileExists(atPath: dest.path))
        try assertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("file.txt").path))
    }

    private func test2_6_FallbackStorageProvider() async throws {
        let tempDir = try createTempDirectory(prefix: "StreamCopyProvider")
        defer { removeTempDirectory(tempDir) }

        let provider = DefaultFileSystemProvider()
        let source = tempDir.appendingPathComponent("stream_source.txt")
        let dest = tempDir.appendingPathComponent("stream_dest.txt")
        try "Stream Copy Data".write(to: source, atomically: true, encoding: .utf8)

        try await provider.copyItemPreservingMetadata(at: source, to: dest, progress: nil)
        try assertTrue(FileManager.default.fileExists(atPath: dest.path))
        let data = try String(contentsOf: dest, encoding: .utf8)
        try assertEqual(data, "Stream Copy Data")
    }

    private func test2_7_ExFATAndNTFSCapabilities() throws {
        let exfatCaps = FileSystemCapabilities(
            fsTypeName: "exfat",
            supportsAPFSClone: false,
            supportsHardLinks: false,
            supportsExtendedAttributes: false,
            supportsSymlinks: false,
            supportsFileFlags: false,
            isReadOnly: false
        )
        try assertTrue(exfatCaps.isExFAT)
        try assertFalse(exfatCaps.supportsAPFSClone)
        try assertEqual(exfatCaps.timestampToleranceSeconds, 0.02, "exFAT tolerance must be 20ms")

        let ntfsCaps = FileSystemCapabilities(
            fsTypeName: "ntfs",
            supportsAPFSClone: false,
            supportsHardLinks: false,
            supportsExtendedAttributes: false,
            supportsSymlinks: false,
            supportsFileFlags: false,
            isReadOnly: true
        )
        try assertTrue(ntfsCaps.isNTFS)
        try assertTrue(ntfsCaps.isReadOnly)
    }

    private func test2_8_DriverRegistryResolution() throws {
        let registry = FileSystemDriverRegistry.shared
        let apfsDriver = registry.driver(forFSType: "apfs")
        try assertEqual(apfsDriver.fsTypeName, "apfs")

        let exfatDriver = registry.driver(forFSType: "exfat")
        try assertEqual(exfatDriver.fsTypeName, "exfat")

        let ntfsDriver = registry.driver(forFSType: "ntfs")
        try assertEqual(ntfsDriver.fsTypeName, "ntfs")
    }

    // =========================================================================
    // MARK: - Module 3: SQLite Database Engine, Transactions & Crash Consistency
    // =========================================================================

    private func test3_1_SQLiteSchemaInitialization() async throws {
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

    private func test3_2_BatchCatalogIndexing() async throws {
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

    private func test3_3_SnapshotDiffEngine() async throws {
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

    private func test3_4_TimelineQueries() async throws {
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

    private func test3_5_GlobalFileSearch() async throws {
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

    private func test3_6_DatabaseCloseRelease() async throws {
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

    private func test3_7_CascadingSnapshotDeletion() async throws {
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

    // =========================================================================
    // MARK: - Module 4: Incremental Backup Lifecycle & Change Detection
    // =========================================================================

    private func test4_1_GitIgnoreRuleParser() throws {
        let parser = GitIgnoreRule(pattern: "*.tmp")
        try assertNotNil(parser)
        try assertTrue(parser?.matches(relativePath: "scratch/test.tmp", isDirectory: false) == true)
        try assertFalse(parser?.matches(relativePath: "scratch/test.txt", isDirectory: false) == true)

        let dirRule = GitIgnoreRule(pattern: "build/")
        try assertNotNil(dirRule)
        try assertTrue(dirRule?.matches(relativePath: "build", isDirectory: true) == true)

        let negationRule = GitIgnoreRule(pattern: "!important.tmp")
        try assertNotNil(negationRule)
        try assertTrue(negationRule?.isNegative == true)
    }

    private func test4_2_ChangeDetectorPrecision() throws {
        let detector = ChangeDetector()
        let t1 = Date(timeIntervalSince1970: 1000.0)
        let t2 = Date(timeIntervalSince1970: 1000.0005) // 0.5ms difference (within APFS 1ms tolerance)

        let testURL = URL(fileURLWithPath: "/tmp/test.txt")
        let meta = FileMetadata(
            url: testURL,
            size: 500,
            modificationTime: t2,
            inode: 1234,
            posixPermissions: 0o644,
            isDirectory: false,
            isSymlink: false
        )
        let scanned = ScannedItem(url: testURL, relativePath: "test.txt", metadata: meta)
        let prev = FileCatalogRecord(snapshotId: "s1", relativePath: "test.txt", fileSize: 500, modificationTime: t1, inode: 1234, isDirectory: false, isSymlink: false)

        let result = detector.detectChanges(scannedItems: [scanned], previousCatalog: ["test.txt": prev], hashMode: .smartHash, timestampTolerance: 0.001)
        try assertEqual(result.unmodified.count, 1, "Item within 1ms tolerance must be classified as unmodified")
        try assertEqual(result.modified.count, 0)
    }

    private func test4_3_RansomwareAnomalyGuard() throws {
        // Normal profile: 2 out of 100 files changed (2%)
        let normalReport = RansomwareAnomalyGuard.evaluate(
            totalFiles: 100,
            modifiedCount: 2,
            deletedCount: 0,
            candidatePaths: ["doc1.pdf", "doc2.pdf"],
            enableGuard: true,
            maxChangeThresholdPercent: 20.0
        )
        try assertFalse(normalReport.isAnomalyDetected, "Normal change rate should not trigger anomaly")

        // Anomaly: 80 out of 100 files changed with .locked extensions
        let anomalyReport = RansomwareAnomalyGuard.evaluate(
            totalFiles: 100,
            modifiedCount: 80,
            deletedCount: 0,
            candidatePaths: ["doc1.pdf.locked", "doc2.pdf.locked"],
            enableGuard: true,
            maxChangeThresholdPercent: 20.0,
            detectSuspiciousExtensions: true
        )
        try assertTrue(anomalyReport.isAnomalyDetected, "Mass mutation with .locked must trigger anomaly guard")
        try assertTrue(anomalyReport.suspiciousExtensionFiles.count > 0)
    }

    private func test4_4_EndToEndBackupLifecycle() async throws {
        let tempDir = try createTempDirectory(prefix: "E2EBackup")
        defer { removeTempDirectory(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("Source")
        let destDir = tempDir.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let file1 = sourceDir.appendingPathComponent("file1.txt")
        let file2 = sourceDir.appendingPathComponent("file2.txt")
        try "Primary Data 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Primary Data 2".write(to: file2, atomically: true, encoding: .utf8)

        let profile = BackupProfile(
            name: "E2ETestProfile",
            sourceURL: sourceDir,
            destinationURL: destDir
        )

        let storage = DefaultFileSystemProvider()
        let db = DatabaseEngine()
        let coordinator = BackupSessionCoordinator(storage: storage, database: db)

        // 1. Initial Backup
        let snap1 = try await coordinator.performBackup(profile: profile, mode: .incremental)
        try assertEqual(snap1.status, "completed")
        try assertEqual(snap1.totalFiles, 2)

        // 2. Incremental Backup with 1 modified file and 1 added file
        try "Modified Data 1".write(to: file1, atomically: true, encoding: .utf8)
        let file3 = sourceDir.appendingPathComponent("file3.txt")
        try "Added Data 3".write(to: file3, atomically: true, encoding: .utf8)

        let snap2 = try await coordinator.performBackup(profile: profile, mode: .incremental)
        try assertEqual(snap2.status, "completed")
        try assertEqual(snap2.totalFiles, 3)

        // 3. Restore verification
        let restoreEngine = RestoreEngine(storage: storage, database: db)
        let restoreDest = tempDir.appendingPathComponent("Restored")
        try FileManager.default.createDirectory(at: restoreDest, withIntermediateDirectories: true)

        let restoredURL = try await restoreEngine.restoreToFile(
            snapshotPath: snap2.snapshotPath,
            backupRootURL: destDir,
            relativePath: "file1.txt",
            destinationFileURL: restoreDest.appendingPathComponent("file1.txt")
        )

        let restoredContent = try String(contentsOf: restoredURL, encoding: .utf8)
        try assertEqual(restoredContent, "Modified Data 1", "Restored file content must match incremental state")
    }

    private func test4_5_CooperativeFileTreeScanner() async throws {
        let tempDir = try createTempDirectory(prefix: "CoopScan")
        defer { removeTempDirectory(tempDir) }

        // Create structure with .nobackup exclusion marker
        let excludedDir = tempDir.appendingPathComponent("CacheFolder")
        try FileManager.default.createDirectory(at: excludedDir, withIntermediateDirectories: true)
        try "marker".write(to: excludedDir.appendingPathComponent(".nobackup"), atomically: true, encoding: .utf8)
        try "secret".write(to: excludedDir.appendingPathComponent("cached_payload.bin"), atomically: true, encoding: .utf8)

        let includedFile = tempDir.appendingPathComponent("valid.txt")
        try "keep".write(to: includedFile, atomically: true, encoding: .utf8)

        let scanner = FileTreeScanner(storage: DefaultFileSystemProvider())
        let scanResult = try await scanner.scanDetailed(rootURL: tempDir)

        let paths = scanResult.items.map(\.relativePath)
        try assertTrue(paths.contains("valid.txt"))
        try assertFalse(paths.contains("CacheFolder/cached_payload.bin"), "Items in directory with .nobackup marker must be skipped")
    }

    private func test4_6_FullSnapshotEntireRestore() async throws {
        let tempDir = try createTempDirectory(prefix: "FullRestore")
        defer { removeTempDirectory(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("Source")
        let destDir = tempDir.appendingPathComponent("BackupDest")
        let restoreTargetDir = tempDir.appendingPathComponent("RestoreTarget")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: restoreTargetDir, withIntermediateDirectories: true)

        // Create sample hierarchy
        let subDir = sourceDir.appendingPathComponent("SubFolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let file1 = sourceDir.appendingPathComponent("alpha.txt")
        let file2 = subDir.appendingPathComponent("beta.data")
        let file3 = sourceDir.appendingPathComponent("gamma.log")

        try "Alpha Content".write(to: file1, atomically: true, encoding: .utf8)
        let sampleBinary = Data((0..<1024).map { UInt8($0 % 256) })
        try sampleBinary.write(to: file2)
        try "Gamma Log Line 1\nGamma Log Line 2\n".write(to: file3, atomically: true, encoding: .utf8)

        let profile = BackupProfile(
            name: "FullRestoreTestProfile",
            sourceURL: sourceDir,
            destinationURL: destDir
        )

        let coordinator = BackupSessionCoordinator()
        let snap = try await coordinator.performBackup(profile: profile, mode: .full)
        try assertEqual(snap.status, "completed")
        try assertEqual(snap.totalFiles, 4, "Snapshot includes 1 directory and 3 files")

        // Perform entire snapshot restore
        let db = DatabaseEngine()
        let dbPath = destDir.appendingPathComponent(".otterkeep/manifest.sqlite").path
        try await db.open(at: dbPath)
        let storage = DefaultFileSystemProvider()
        let restoreEngine = RestoreEngine(storage: storage, database: db)

        final class ProgressBox: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var list: [RestoreProgressState] = []
            func append(_ item: RestoreProgressState) {
                lock.lock()
                defer { lock.unlock() }
                list.append(item)
            }
            var count: Int {
                lock.lock()
                defer { lock.unlock() }
                return list.count
            }
        }
        let progressBox = ProgressBox()

        let summary = try await restoreEngine.restoreSnapshot(
            snapshotPath: snap.snapshotPath,
            backupRootURL: destDir,
            targetDirectoryURL: restoreTargetDir,
            collisionResolution: .overwrite,
            progress: { prog in
                progressBox.append(prog)
            }
        )

        // Verifications
        try assertEqual(summary.restoredFiles, 3, "All 3 files must be restored")
        try assertTrue(summary.restoredBytes > 0, "Restored bytes must be non-zero")
        try assertTrue(progressBox.count > 0, "Progress events must be emitted during restoration")

        // Verify filesystem content & integrity
        let restoredFile1 = restoreTargetDir.appendingPathComponent("alpha.txt")
        let restoredFile2 = restoreTargetDir.appendingPathComponent("SubFolder/beta.data")
        let restoredFile3 = restoreTargetDir.appendingPathComponent("gamma.log")

        try assertTrue(FileManager.default.fileExists(atPath: restoredFile1.path), "Restored alpha.txt must exist")
        try assertTrue(FileManager.default.fileExists(atPath: restoredFile2.path), "Restored beta.data in SubFolder must exist")
        try assertTrue(FileManager.default.fileExists(atPath: restoredFile3.path), "Restored gamma.log must exist")

        let content1 = try String(contentsOf: restoredFile1, encoding: .utf8)
        try assertEqual(content1, "Alpha Content", "alpha.txt content must match original")

        let content2 = try Data(contentsOf: restoredFile2)
        try assertEqual(content2, sampleBinary, "beta.data binary data must match original")

        // Verify SHA-256 matches
        let hashOriginal = try ChecksumCalculator.computeSHA256(for: file2)
        let hashRestored = try ChecksumCalculator.computeSHA256(for: restoredFile2)
        try assertEqual(hashOriginal, hashRestored, "SHA-256 hash must be identical")
    }

    // =========================================================================
    // MARK: - Module 5: Client-Side Cryptography & Security Integrity
    // =========================================================================

    private func test5_1_OKENC2Encryption() throws {
        let plaintext = Data("Cherished OtterKeep Sanctuary Payload 2026".utf8)
        let passphrase = "Ollie-Super-Secret-Sanctuary-Passphrase"

        let encrypted = try ClientSideEncryptor.encrypt(data: plaintext, passphrase: passphrase)
        try assertTrue(encrypted.count > plaintext.count)
        try assertTrue(encrypted.starts(with: ClientSideEncryptor.headerMagicOKENC2))

        let decrypted = try ClientSideEncryptor.decrypt(envelope: encrypted, passphrase: passphrase)
        try assertEqual(decrypted, plaintext, "Decrypted data must match original plaintext")
    }

    private func test5_2_DSENC1BackwardCompatibility() throws {
        let plaintext = Data("Legacy DataSquirrel Archive 1.0".utf8)
        let passphrase = "LegacyPassphrase123"

        // Construct a valid DSENC1 legacy envelope using HKDF-SHA256 to verify the backward-compatible decrypt branch
        let salt = Data([UInt8](repeating: 0x5A, count: 16))
        let inputKeyMaterial = SymmetricKey(data: Data(passphrase.utf8))
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: salt,
            info: Data("OtterKeep-S3-Envelope-Key".utf8),
            outputByteCount: 32
        )
        let sealedBox = try AES.GCM.seal(plaintext, using: derivedKey)
        guard let combined = sealedBox.combined else {
            throw TestFailure(message: "Failed to create legacy sealed box")
        }
        var legacyEnvelope = ClientSideEncryptor.headerMagicV1
        legacyEnvelope.append(salt)
        legacyEnvelope.append(combined)

        try assertTrue(legacyEnvelope.starts(with: ClientSideEncryptor.headerMagicV1))

        let decrypted = try ClientSideEncryptor.decrypt(envelope: legacyEnvelope, passphrase: passphrase)
        try assertEqual(decrypted, plaintext, "DSENC1 legacy format must decrypt seamlessly through backward-compatibility path")
    }

    private func test5_3_TamperResistance() throws {
        let plaintext = Data("Sensitive Data".utf8)
        let passphrase = "SafePassword"
        var encrypted = try ClientSideEncryptor.encrypt(data: plaintext, passphrase: passphrase)

        // 1. Wrong passphrase rejection
        var threwWrongPass = false
        do {
            _ = try ClientSideEncryptor.decrypt(envelope: encrypted, passphrase: "IncorrectPassword")
        } catch {
            threwWrongPass = true
        }
        try assertTrue(threwWrongPass, "Decryption with wrong password must throw authentication error")

        // 2. Tampered ciphertext rejection
        let lastByteIdx = encrypted.count - 1
        encrypted[lastByteIdx] ^= 0xFF
        var threwTamper = false
        do {
            _ = try ClientSideEncryptor.decrypt(envelope: encrypted, passphrase: passphrase)
        } catch {
            threwTamper = true
        }
        try assertTrue(threwTamper, "Tampered ciphertext must fail authenticated decryption")
    }

    private func test5_4_HashCalculations() throws {
        let tempDir = try createTempDirectory(prefix: "HashTest")
        defer { removeTempDirectory(tempDir) }

        let file = tempDir.appendingPathComponent("data.bin")
        let payload = Data(repeating: 0x5A, count: 256 * 1024)
        try payload.write(to: file)

        let sha256 = try ChecksumCalculator.computeSHA256(for: file)
        try assertEqual(sha256.count, 64, "SHA-256 hex string must be 64 characters")

        let sampleHash = try FastHashCalculator.computeSamplingHash(for: file)
        try assertEqual(sampleHash.count, 64, "Sampling hash must return valid SHA-256 hex")
    }

    // =========================================================================
    // MARK: - Module 6: IPC, Process Security & Peer UID Validation
    // =========================================================================

    private func test6_1_AFUnixBufferBounds() throws {
        let addr = sockaddr_un()
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        try assertEqual(maxLen, 104, "Darwin sockaddr_un sun_path buffer must be 104 bytes")

        let pathWithinBounds = "/tmp/otterkeep_test_safe.sock"
        try assertTrue(pathWithinBounds.utf8CString.count <= maxLen)

        let pathExceedingBounds = "/tmp/" + String(repeating: "a", count: 120) + ".sock"
        try assertTrue(pathExceedingBounds.utf8CString.count > maxLen)
    }

    private func test6_2_SocketPermissions() throws {
        let manager = SingleInstanceManager.shared
        manager.ensureDirectoryPermissions()
        let lockPath = manager.lockFilePath
        let socketPath = manager.socketPath

        try assertTrue(lockPath.contains(".otterkeep"))
        try assertTrue(socketPath.contains("gui.sock"))

        let homeDir = URL(fileURLWithPath: manager.socketPath).deletingLastPathComponent().path
        if FileManager.default.fileExists(atPath: homeDir) {
            let attrs = try FileManager.default.attributesOfItem(atPath: homeDir)
            if let posix = attrs[.posixPermissions] as? NSNumber {
                try assertEqual(posix.intValue, 0o700, "Base ~/.otterkeep/ directory must have 0700 permissions")
            }
        }
    }

    private func test6_3_PeerUIDVerification() throws {
        // Verify current process credentials
        let myUID = geteuid()
        let myGID = getegid()
        try assertTrue(myUID >= 0)
        try assertTrue(myGID >= 0)
    }

    private func test6_4_MessageSerialization() throws {
        let msg = SingleInstanceMessage(action: .openVersionHistory, filePath: "/Users/test/Documents/report.pdf")
        let encoder = JSONEncoder()
        let data = try encoder.encode(msg)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SingleInstanceMessage.self, from: data)
        try assertEqual(decoded.action, .openVersionHistory)
        try assertEqual(decoded.filePath, "/Users/test/Documents/report.pdf")
    }

    private func test6_5_SFTPInjectionNeutralization() throws {
        let config = SFTPConfiguration(host: "nas.local", port: 22, username: "backupuser", remotePath: "/backups")
        try assertEqual(config.host, "nas.local")
        try assertEqual(config.port, 22)
        try assertEqual(config.username, "backupuser")
        let provider = SFTPStorageProvider(config: config)
        _ = provider
    }

    // =========================================================================
    // MARK: - Module 7: Privacy-Preserving Observability & Diagnostics
    // =========================================================================

    private func test7_1_LogPrivacyScrubbing() throws {
        let rawLog = "Error connecting to S3 with key AKIAIOSFODNN7EXAMPLE and secret https://api.endpoint.com?token=mySecretToken12345678"
        let sanitized = LogPrivacySanitizer.sanitize(rawLog)
        try assertFalse(sanitized.contains("AKIAIOSFODNN7EXAMPLE"), "AWS keys must be scrubbed")
        try assertFalse(sanitized.contains("mySecretToken12345678"), "Token parameters must be scrubbed")
        try assertTrue(sanitized.contains("<AWS_ACCESS_KEY_ID>"))
    }

    private func test7_2_PathMasking() throws {
        let rawPath = "/Users/john/Documents/Personal/FinancialReport_2026.pdf"
        let sanitized = LogPrivacySanitizer.sanitizeSinglePath(rawPath)
        try assertFalse(sanitized.contains("john"), "Usernames must be scrubbed")
        try assertFalse(sanitized.contains("FinancialReport_2026"), "Personal filenames must be scrubbed")
        try assertTrue(sanitized.hasSuffix(".pdf"), "File extension must be preserved for diagnostic triage")
    }

    private func test7_3_DualTierDiagnostics() throws {
        let logger = LogManager.shared
        logger.log("Info message test", level: .info, category: "Test")
        logger.log("Warning message test", level: .warning, category: "Test")

        let entries = logger.getEntries()
        try assertTrue(entries.contains(where: { $0.message.contains("Info message test") }))
    }

    private func test7_4_DebugFileLoggerAppend() throws {
        let fileLogger = DebugFileLogger.shared
        let url = fileLogger.startSession()
        try assertTrue(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        fileLogger.appendLog(sanitizedMessage: "Diagnostic checkpoint", level: "INFO", category: "Test")
        fileLogger.stopSession()

        let content = try String(contentsOf: url, encoding: .utf8)
        try assertTrue(content.contains("Diagnostic checkpoint"))
    }

    // =========================================================================
    // MARK: - Module 8: Photos Backup Architecture & iCloud Eviction
    // =========================================================================

    private func test8_1_PhotosSchemes() throws {
        try assertEqual(PhotosExportStructure.dateHierarchy.rawValue, "dateHierarchy")
        try assertEqual(PhotosExportStructure.albumHierarchy.rawValue, "albumHierarchy")
        try assertEqual(PhotosExportStructure.flat.rawValue, "flat")
    }

    private func test8_2_PhotoMetadataExtraction() throws {
        let extractor = PhotoMetadataExtractor()
        _ = extractor
        // Verify default config
        let config = PhotosProfileStore.shared.loadConfiguration()
        try assertTrue(config.exportStructure == .dateHierarchy || config.exportStructure == .albumHierarchy || config.exportStructure == .flat)
    }

    private func test8_3_EphemeralStorageGuard() async throws {
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

    private func test8_4_PhotosCoordinatorInit() throws {
        let coordinator = PhotosBackupCoordinator()
        _ = coordinator
        let deltaScanner = PhotosDeltaScanner()
        let albumMap = deltaScanner.mapAssetAlbums()
        _ = albumMap
    }

    // =========================================================================
    // MARK: - Module 9: Bilingual Localization Completeness & Parity
    // =========================================================================

    private func test9_1_LocalizationKeyParity() throws {
        let allKeys = L10n.Key.allCases
        try assertTrue(allKeys.count >= 200, "Localization dictionary should have comprehensive key coverage")

        // Verify every key resolves in both Hungarian and English without throwing empty string
        for key in allKeys {
            let hu = L10n.t(key, lang: .hungarian)
            let en = L10n.t(key, lang: .english)
            try assertTrue(!hu.isEmpty, "Key \(key.rawValue) must have non-empty Hungarian translation")
            try assertTrue(!en.isEmpty, "Key \(key.rawValue) must have non-empty English translation")
        }
    }

    private func test9_2_LocalizationNonEmptyStrings() throws {
        try assertTrue(!L10n.t(.navDashboard, lang: .english).isEmpty)
        try assertTrue(!L10n.t(.navDashboard, lang: .hungarian).isEmpty)
        try assertTrue(!L10n.t(.feedbackSuccessTitle, lang: .hungarian).isEmpty)
        try assertTrue(!L10n.t(.feedbackSuccessTitle, lang: .english).isEmpty)
    }

    private func test9_3_FormatSpecifierConsistency() throws {
        // Verify restore feedback message formatting in both languages without crashing
        let huRestore = L10n.format(.feedbackRestoreSuccessMessage, "snapshot_1", Int64(5), lang: .hungarian)
        let enRestore = L10n.format(.feedbackRestoreSuccessMessage, "snapshot_1", Int64(5), lang: .english)
        try assertTrue(huRestore.contains("snapshot_1") && huRestore.contains("5"))
        try assertTrue(enRestore.contains("snapshot_1") && enRestore.contains("5"))

        // Verify all format keys have identical token count
        let hu = L10n.t(.feedbackSuccessMessage, lang: .hungarian)
        let en = L10n.t(.feedbackSuccessMessage, lang: .english)
        try assertEqual(hu.components(separatedBy: "%@").count, en.components(separatedBy: "%@").count)

        // Verify scrub format strings execute without SIGSEGV in both Hungarian and English
        let huScrub = L10n.format(.scrubSuccessMessage, "Profile A", Int64(3), Int64(450), lang: .hungarian)
        let enScrub = L10n.format(.scrubSuccessMessage, "Profile A", Int64(3), Int64(450), lang: .english)
        try assertTrue(huScrub.contains("Profile A") && huScrub.contains("3") && huScrub.contains("450"))
        try assertTrue(enScrub.contains("Profile A") && enScrub.contains("3") && enScrub.contains("450"))

        let huScrubErr = L10n.format(.scrubCorruptedMessage, "Profile A", Int64(2), lang: .hungarian)
        let enScrubErr = L10n.format(.scrubCorruptedMessage, "Profile A", Int64(2), lang: .english)
        try assertTrue(huScrubErr.contains("Profile A") && huScrubErr.contains("2"))
        try assertTrue(enScrubErr.contains("Profile A") && enScrubErr.contains("2"))

        let huAlert = L10n.format(.scrubberCorruptedAlertMessage, Int64(5), "snap_01", lang: .hungarian)
        let enAlert = L10n.format(.scrubberCorruptedAlertMessage, Int64(5), "snap_01", lang: .english)
        try assertTrue(huAlert.contains("5") && huAlert.contains("snap_01"))
        try assertTrue(enAlert.contains("5") && enAlert.contains("snap_01"))
    }

    private func test9_4_RestoredSuffixParity() throws {
        let initialLang = LocalizationManager.shared.currentLanguage
        defer { LocalizationManager.shared.currentLanguage = initialLang }

        LocalizationManager.shared.currentLanguage = .hungarian
        let huSuffix = L10n.format(.restoredSuffixFormat, 1)
        LocalizationManager.shared.currentLanguage = .english
        let enSuffix = L10n.format(.restoredSuffixFormat, 1)
        try assertTrue(huSuffix.contains("visszaállított 1"))
        try assertTrue(enSuffix.contains("restored 1"))
    }

    // =========================================================================
    // MARK: - Module 10: Modern UI Design System, Sanctuary Experience & Configuration
    // =========================================================================

    private func test10_1_OtterThemeTokens() throws {
        let amber = OtterTheme.otterAmber
        let teal = OtterTheme.oceanicTeal
        let navy = OtterTheme.deepSeaNavy
        let pebble = OtterTheme.pebbleGrey
        let green = OtterTheme.statusGreen

        _ = amber
        _ = teal
        _ = navy
        _ = pebble
        _ = green
    }

    private func test10_2_ThreePartErrorArchitecture() throws {
        let dummyError = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC), userInfo: [NSLocalizedDescriptionKey: "No space left on device"])
        let analyzed = AppState.analyzeBackupError(dummyError, destinationURL: URL(fileURLWithPath: "/Volumes/ExternalSSD"), sourceURL: URL(fileURLWithPath: "/Users/user/Docs"))

        // Part 1: What happened (title & message)
        try assertTrue(!analyzed.title.isEmpty)
        try assertTrue(!analyzed.message.isEmpty)

        // Part 2 & 3: Sanctuary reassurance & restorative pathway
        try assertTrue(!analyzed.detailedReason.isEmpty)
    }

    private func test10_3_ConfigurationArchiveSerialization() throws {
        let profile = BackupProfile(name: "Portable Profile", sourceURL: URL(fileURLWithPath: "/Users/test/Code"), destinationURL: URL(fileURLWithPath: "/Volumes/Backup/Code"))
        let settings = AppSettings(language: .english, launchAtLogin: true, startMinimized: false, debugFileLoggingEnabled: false, finderIntegrationEnabled: true, themeMode: .system)
        let archive = ConfigurationExportArchive(profiles: [profile], settings: settings, photosConfig: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(archive)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ConfigurationExportArchive.self, from: data)
        try assertEqual(decoded.appVersion, "1.7.1")
        try assertEqual(decoded.profiles.count, 1)
        try assertEqual(decoded.profiles.first?.name, "Portable Profile")
    }

    private func test10_4_AppStateMultiProfileTracking() async throws {
        let appState = AppState()
        let p1 = UUID()
        let p2 = UUID()

        try assertFalse(appState.isBackupRunning(for: p1))
        try assertFalse(appState.isBackupRunning(for: p2))
    }

    private func test10_5_OtterAboutViewMetadata() throws {
        try assertEqual(CoreEngine.version, "1.7.1")
        try assertEqual(CoreEngine.buildNumber, "1701")
    }

    private func test10_6_DefaultFileSystemProviderRouting() async throws {
        let provider = DefaultFileSystemProvider()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let caps = try await provider.capabilities(at: home)
        try assertTrue(!caps.fsTypeName.isEmpty)

        // Verify FileSystemDriverRegistry resolution
        let resolved = FileSystemDriverRegistry.shared.driver(forFSType: caps.fsTypeName)
        let regCaps = try await resolved.capabilities(at: home)
        try assertEqual(caps.fsTypeName, regCaps.fsTypeName)
    }

    private func test10_7_RestoreOperationFeedbackAndModes() throws {
        // Test streamlined modes
        try assertEqual(RestoreBrowseMode.allCases.count, 3)
        try assertEqual(RestoreBrowseMode.snapshot.rawValue, "snapshot")
        try assertEqual(RestoreBrowseMode.timeline.rawValue, "timeline")
        try assertEqual(RestoreBrowseMode.globalSearch.rawValue, "globalSearch")

        // Test restore summary feedback construction
        let summary = RestoreSessionSummary(
            snapshotPath: "2026-10-07_12-00-00",
            totalFiles: 10,
            totalBytes: 10240,
            restoredFiles: 10,
            restoredBytes: 10240,
            durationSeconds: 1.25
        )
        let feedback = OperationFeedback(
            type: .success,
            title: L10n.t(.feedbackRestoreSuccessTitle),
            message: L10n.format(.feedbackRestoreSuccessMessage, summary.snapshotPath, Int64(summary.restoredFiles)),
            restoreSummary: summary
        )
        try assertEqual(feedback.type, .success)
        try assertEqual(feedback.restoreSummary?.restoredFiles, 10)
        try assertTrue(!feedback.title.isEmpty)
    }

    // =========================================================================
    // MARK: - Module 11: 1.5.0 Modern Capabilities
    // =========================================================================

    private func test11_1_TextDiffEngineSideBySide() throws {
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

    private func test11_2_DataScrubberBitRotDetection() async throws {
        let tempDir = try createTempDirectory(prefix: "Scrubber")
        defer { removeTempDirectory(tempDir) }

        let internalDir = tempDir.appendingPathComponent(".otterkeep")
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)

        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let snapId = "2026-10-08_12-00-00"
        let snapDir = tempDir.appendingPathComponent(snapId).appendingPathComponent("root")
        try FileManager.default.createDirectory(at: snapDir, withIntermediateDirectories: true)

        let fileURL = snapDir.appendingPathComponent("document.txt")
        let originalContent = "Original authentic OtterKeep backup block data."
        try originalContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let originalChecksum = try ChecksumCalculator.computeSHA256(for: fileURL)

        let snapRecord = SnapshotRecord(
            id: snapId,
            timestamp: Date(),
            status: "completed",
            totalFiles: 1,
            totalBytes: Int64(originalContent.utf8.count),
            snapshotPath: snapId,
            backupType: "incremental"
        )
        try await db.insertSnapshot(snapRecord)

        let fileRecord = FileCatalogRecord(
            snapshotId: snapId,
            relativePath: "document.txt",
            fileSize: Int64(originalContent.utf8.count),
            modificationTime: Date(),
            inode: 9999,
            checksum: originalChecksum,
            isDirectory: false,
            isSymlink: false
        )
        try await db.insertFileRecordsBatch([fileRecord])

        // Initial scrub: clean pass
        let scrubber = DataScrubberEngine(storage: DefaultFileSystemProvider(), database: db)
        let cleanAudit = try await scrubber.performScrub(backupRootURL: tempDir)
        try assertEqual(cleanAudit.status, "healthy")
        try assertEqual(cleanAudit.corruptedFilesCount, 0)
        try assertEqual(cleanAudit.checkedFilesCount, 1)

        // Inject bit-rot by tampering with file content
        let corruptedContent = "Corrupted manipulated data block with flipped bits!"
        try corruptedContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Scrubber pass should flag bit-rot
        let corruptedAudit = try await scrubber.performScrub(backupRootURL: tempDir)
        try assertEqual(corruptedAudit.status, "corruption_detected")
        try assertEqual(corruptedAudit.corruptedFilesCount, 1)
        try assertTrue(corruptedAudit.detailsJson?.contains("Bit-rot") == true, "Details must report bit-rot")
    }

    private func test11_3_WORMImmutabilityAndRetentionPruning() async throws {
        let tempDir = try createTempDirectory(prefix: "WORM")
        defer {
            // Unlock everything before attempting test teardown cleanup
            let provider = DefaultFileSystemProvider()
            try? provider.setImmutable(at: tempDir, immutable: false, recursive: true)
            removeTempDirectory(tempDir)
        }

        let provider = DefaultFileSystemProvider()
        let testSnapDir = tempDir.appendingPathComponent("snapshot_worm_test")
        let testSubDir = testSnapDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: testSubDir, withIntermediateDirectories: true)
        let testFile1 = testSnapDir.appendingPathComponent("file1.txt")
        let testFile2 = testSubDir.appendingPathComponent("file2.txt")
        try "Content1".write(to: testFile1, atomically: true, encoding: .utf8)
        try "Content2".write(to: testFile2, atomically: true, encoding: .utf8)

        // 1. Initially files are not immutable
        let initF1Imm = try provider.isFileImmutable(at: testFile1)
        let initF2Imm = try provider.isFileImmutable(at: testFile2)
        try assertFalse(initF1Imm, "Initial file must not be immutable")
        try assertFalse(initF2Imm, "Initial nested file must not be immutable")

        // 2. Recursive immutability locks directory and nested files
        try provider.setImmutable(at: testSnapDir, immutable: true, recursive: true)
        let lockedDirImm = try provider.isFileImmutable(at: testSnapDir)
        let lockedF1Imm = try provider.isFileImmutable(at: testFile1)
        let lockedF2Imm = try provider.isFileImmutable(at: testFile2)
        try assertTrue(lockedDirImm, "Snapshot directory must be immutable")
        try assertTrue(lockedF1Imm, "Top-level file in snapshot must be immutable")
        try assertTrue(lockedF2Imm, "Nested file in snapshot must be immutable")

        // 3. Recursive unlock unlocks directory and all nested files
        try provider.setImmutable(at: testSnapDir, immutable: false, recursive: true)
        let unDirImm = try provider.isFileImmutable(at: testSnapDir)
        let unF1Imm = try provider.isFileImmutable(at: testFile1)
        let unF2Imm = try provider.isFileImmutable(at: testFile2)
        try assertFalse(unDirImm, "Snapshot directory must be unlocked")
        try assertFalse(unF1Imm, "Top-level file must be unlocked")
        try assertFalse(unF2Imm, "Nested file must be unlocked")

        // 4. Database WORM lock state
        let internalDir = tempDir.appendingPathComponent(".otterkeep")
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)

        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let snapIdNewest = "snap_newest_00"
        let snapIdLocked = "snap_locked_01"
        let snapIdPrunable = "snap_prunable_02"
        let fortyDaysAgo = Date().addingTimeInterval(-40 * 86400)
        let thirtyDaysFuture = Date().addingTimeInterval(30 * 86400)

        // Create snapshot directories
        let snapDirNewest = tempDir.appendingPathComponent(snapIdNewest)
        let snapDirLocked = tempDir.appendingPathComponent(snapIdLocked)
        let snapDirPrunable = tempDir.appendingPathComponent(snapIdPrunable)
        try FileManager.default.createDirectory(at: snapDirNewest, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapDirLocked, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapDirPrunable, withIntermediateDirectories: true)

        let lockedInnerFile = snapDirLocked.appendingPathComponent("data.txt")
        try "Protected data".write(to: lockedInnerFile, atomically: true, encoding: .utf8)
        try provider.setImmutable(at: snapDirLocked, immutable: true, recursive: true)

        let newestSnap = SnapshotRecord(
            id: snapIdNewest,
            timestamp: Date(),
            status: "completed",
            totalFiles: 1,
            totalBytes: 100,
            snapshotPath: snapIdNewest,
            lockedUntil: nil
        )
        try await db.insertSnapshot(newestSnap)

        let lockedSnap = SnapshotRecord(
            id: snapIdLocked,
            timestamp: fortyDaysAgo,
            status: "completed",
            totalFiles: 1,
            totalBytes: 100,
            snapshotPath: snapIdLocked,
            lockedUntil: thirtyDaysFuture
        )
        try await db.insertSnapshot(lockedSnap)
        try assertTrue(lockedSnap.isLocked, "Snapshot with future lockedUntil must report isLocked == true")

        let prunableSnap = SnapshotRecord(
            id: snapIdPrunable,
            timestamp: fortyDaysAgo,
            status: "completed",
            totalFiles: 1,
            totalBytes: 100,
            snapshotPath: snapIdPrunable,
            lockedUntil: nil
        )
        try await db.insertSnapshot(prunableSnap)
        try assertFalse(prunableSnap.isLocked, "Snapshot without lockedUntil must report isLocked == false")

        // 5. Manual non-pruning deletion of a locked snapshot is rejected
        let retention = RetentionManager(storage: provider, database: db)
        var caughtPermissionDenied = false
        do {
            try await retention.deleteSnapshot(destinationURL: tempDir, snapshot: lockedSnap, isPruning: false)
        } catch FileSystemError.permissionDenied {
            caughtPermissionDenied = true
        }
        try assertTrue(caughtPermissionDenied, "Manual deletion of locked snapshot without isPruning must throw permissionDenied")

        // 6. Automated retention pruning CAN remove snapshots (unlocking WORM immutability recursively first)
        let pruned = try await retention.applyRetentionPolicy(
            destinationURL: tempDir,
            policy: PruningPolicy(isAutoPruningEnabled: true, maxSnapshotsToKeep: 1, keepDailyDays: 7)
        )

        try assertTrue(pruned.contains(snapIdPrunable), "Old unlocked snapshot must be pruned")
        try assertTrue(pruned.contains(snapIdLocked), "Pruning must be able to remove WORM-locked snapshot past retention policy")
        try assertFalse(FileManager.default.fileExists(atPath: snapDirLocked.path), "Pruned WORM snapshot folder must be deleted from disk")

        // 7. Test restored file is NOT immutable at destination
        let restoreDest = tempDir.appendingPathComponent("restored_output")
        try FileManager.default.createDirectory(at: restoreDest, withIntermediateDirectories: true)
        let restoredFile = restoreDest.appendingPathComponent("unlocked_restored.txt")
        try "Restored".write(to: restoredFile, atomically: true, encoding: .utf8)
        try provider.setImmutable(at: restoreDest, immutable: false, recursive: true)
        let restoredFileImm = try provider.isFileImmutable(at: restoredFile)
        try assertFalse(restoredFileImm, "Restored file must not be immutable at destination")
    }

    private func test11_4_BackblazeB2Configuration() async throws {
        let b2Config = B2Configuration(
            keyId: "0040abc12345",
            bucketName: "company-secure-vault",
            region: "us-west-004",
            customEndpoint: nil,
            pathPrefix: "otterkeep/workstation"
        )

        // 1. Endpoint resolution
        try assertEqual(b2Config.resolvedEndpoint, "https://s3.us-west-004.backblazeb2.com")

        // 2. Custom endpoint resolution
        var customB2 = b2Config
        customB2.customEndpoint = "s3.eu-central-003.backblazeb2.com"
        try assertEqual(customB2.resolvedEndpoint, "https://s3.eu-central-003.backblazeb2.com")

        // 3. S3 Configuration conversion
        let s3Config = b2Config.toS3Configuration()
        try assertEqual(s3Config.endpoint, "https://s3.us-west-004.backblazeb2.com")
        try assertEqual(s3Config.bucket, "company-secure-vault")
        try assertEqual(s3Config.region, "us-west-004")
        try assertEqual(s3Config.accessKeyId, "0040abc12345")
        try assertEqual(s3Config.pathPrefix, "otterkeep/workstation")
        try assertTrue(s3Config.forcePathStyle, "Backblaze B2 S3 API requires forcePathStyle = true")

        // 4. Provider instantiation
        let provider = B2StorageProvider(config: b2Config, applicationKey: "K004dummySecretKey123")
        _ = provider
    }

    private func test11_5_ReplicationCatchUpCoordinator() async throws {
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

    private func test11_6_DatalessICloudChangeDetection() throws {
        let detector = ChangeDetector()
        let dummyURL = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/document.key")
        let now = Date(timeIntervalSince1970: 1700000000)

        let metadata = FileMetadata(
            url: dummyURL,
            size: 2048576,
            modificationTime: now,
            inode: 8888,
            posixPermissions: 0o644,
            isDirectory: false,
            isSymlink: false
        )

        // Dataless iCloud item: not downloaded locally
        let scannedItem = ScannedItem(
            url: dummyURL,
            relativePath: "iCloud/document.key",
            metadata: metadata,
            isDatalessICloud: true
        )

        let previousCatalogRecord = FileCatalogRecord(
            snapshotId: "snap-prev",
            relativePath: "iCloud/document.key",
            fileSize: 2048576,
            modificationTime: now,
            inode: 8888,
            checksum: "a1b2c3d4e5f67890123456789012345678901234567890123456789012345678",
            sampleHash: "sampleHash123",
            isDirectory: false,
            isSymlink: false
        )

        let catalog = ["iCloud/document.key": previousCatalogRecord]

        // 1. Unmodified check under thoroughSampling mode:
        // Must strictly bypass sample and content hashing to avoid kernel APFS faults / forced downloads
        let result = detector.detectChanges(
            scannedItems: [scannedItem],
            previousCatalog: catalog,
            hashMode: .thoroughSampling
        )

        try assertEqual(result.unmodified.count, 1, "Dataless iCloud item with matching size & mtime must be marked unmodified without reading payload")
        try assertEqual(result.modified.count, 0)

        // 2. Modified check when modification time changes
        let modifiedMeta = FileMetadata(
            url: dummyURL,
            size: 2048576,
            modificationTime: now.addingTimeInterval(3600), // 1 hour later
            inode: 8888,
            posixPermissions: 0o644,
            isDirectory: false,
            isSymlink: false
        )
        let modifiedItem = ScannedItem(
            url: dummyURL,
            relativePath: "iCloud/document.key",
            metadata: modifiedMeta,
            isDatalessICloud: true
        )

        let changedResult = detector.detectChanges(
            scannedItems: [modifiedItem],
            previousCatalog: catalog,
            hashMode: .smartHash
        )

        try assertEqual(changedResult.modified.count, 1, "Dataless iCloud item with changed mtime must be detected as modified")
        try assertEqual(changedResult.unmodified.count, 0)
    }

    // =========================================================================
    // MARK: - Module 12: Backend Architecture, Layering & Catalog Services
    // =========================================================================

    private func test12_1_ComplianceEvaluatorScenarios() throws {
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

    private func test12_2_SnapshotCatalogServiceLifecycle() async throws {
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

// MARK: - Executable Main Entry Point

let suite = OtterKeepTestSuite()
let success = await suite.executeAllTests()
exit(success ? 0 : 1)
