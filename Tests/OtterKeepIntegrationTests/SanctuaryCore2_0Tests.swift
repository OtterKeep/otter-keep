//
//  SanctuaryCore2_0Tests.swift
//  OtterKeepIntegrationTests
//
//  OtterKeep 2.0.0 Architecture Suite: FastCDC, Canary Traps, Power Governor,
//  Multi-Drive Zero-Config, Database Self-Healing, and Sparsebundle Storage.
//

import Foundation
import CryptoKit
import Testing
import OtterKeepDomain
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

final class TestSafeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { self._value = value }
    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
    func modify(_ block: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        block(&_value)
    }
}

@MainActor
@Suite(.serialized)
struct SanctuaryCore2_0Tests {

    // MARK: - 1. Content-Defined Chunking (FastCDC)

    @Test func test_FastCDCChunkingAndCASReconstruction() throws {
        let tempDir = try createTempDirectory(prefix: "FastCDCTest")
        defer { removeTempDirectory(tempDir) }

        let engine = FastCDCEngine(configuration: .standard)

        // Generate 300 KB test payload with recurring patterns
        var testData = Data()
        for i in 0..<300 {
            let chunkPattern = "OtterKeep Chunk Segment \(i % 10): The Serene Guardian for Your macOS Digital Sanctuary.\n"
            if let patternData = chunkPattern.data(using: .utf8) {
                testData.append(patternData)
            }
        }
        let originalSHA256 = SHA256.hash(data: testData).compactMap { String(format: "%02x", $0) }.joined()

        let chunks = engine.chunk(data: testData)
        try assertTrue(!chunks.isEmpty)

        // Verify total byte count of all chunks equals original data count
        let totalChunkBytes = chunks.reduce(0) { $0 + $1.length }
        try assertEqual(totalChunkBytes, testData.count)

        // Store into CAS repository
        let casRoot = tempDir.appendingPathComponent("cas_repo", isDirectory: true)
        try engine.store(chunks: chunks, in: casRoot)

        // Reconstruct file from hashes
        let chunkHashes = chunks.map { $0.sha256 }
        let restoredFile = tempDir.appendingPathComponent("restored_output.dat")
        try engine.reconstruct(chunkHashes: chunkHashes, from: casRoot, to: restoredFile)

        let restoredData = try Data(contentsOf: restoredFile)
        let restoredSHA256 = SHA256.hash(data: restoredData).compactMap { String(format: "%02x", $0) }.joined()

        try assertEqual(restoredData.count, testData.count)
        try assertEqual(restoredSHA256, originalSHA256)
    }

    // MARK: - 2. Anti-Ransomware Canary Trap Monitor

    @Test func test_CanaryTrapMonitorPlantAndTamperDetection() throws {
        let tempDir = try createTempDirectory(prefix: "CanaryTest")
        defer { removeTempDirectory(tempDir) }

        let tripwireFired = TestSafeBox(false)
        let monitor = CanaryTrapMonitor { _ in
            tripwireFired.set(true)
        }

        // 1. Plant canary
        let canaryURL = try monitor.plantCanary(in: tempDir)
        try assertTrue(FileManager.default.fileExists(atPath: canaryURL.path(percentEncoded: false)))

        // 2. Arm and verify
        monitor.arm(in: tempDir)
        try monitor.verifyAll() // Passes initially

        // 3. Tamper with canary content
        try "ENCRYPTED_RANSOMWARE_PAYLOAD".data(using: .utf8)?.write(to: canaryURL)

        // 4. Verify tampering is caught
        var caughtTamper = false
        do {
            try monitor.verifyAll()
        } catch is CanaryTrapMonitor.CanaryTrapTriggeredError {
            caughtTamper = true
        }
        try assertTrue(caughtTamper)

        // 5. Delete canary and verify deletion detection
        try FileManager.default.removeItem(at: canaryURL)
        var caughtDeletion = false
        do {
            try monitor.verifyAll()
        } catch is CanaryTrapMonitor.CanaryTrapTriggeredError {
            caughtDeletion = true
        }
        try assertTrue(caughtDeletion)

        monitor.disarm()
    }

    // MARK: - 3. Power and Thermal Governor

    @Test func test_PowerAndThermalGovernorAssessment() {
        let governor = PowerAndThermalGovernor.shared
        let status = governor.currentStatus()

        // Nominal concurrency should match or be at least 1
        let concurrency = governor.recommendedConcurrency(baseConcurrency: 4, throttleOnThermal: true)
        try! assertTrue(concurrency >= 1)

        let delay = governor.throttleDelayNanoseconds(throttleOnThermal: false)
        try! assertEqual(Int(delay), 0)

        // Battery pause test logic
        let (shouldPause, _) = governor.shouldPauseBackup(pauseOnBattery: false)
        // If not critical thermal, should not pause when pauseOnBattery is false
        if status.thermalState != .critical {
            try! assertFalse(shouldPause)
        }
    }

    // MARK: - 4. Multi-Drive Rotation & Zero-Config Adoption

    @Test func test_DriveProfileMetadataAndZeroConfigAdoption() throws {
        let tempDir = try createTempDirectory(prefix: "DriveMetadataTest")
        defer { removeTempDirectory(tempDir) }

        let profile = BackupProfile(
            name: "Sanctuary Vault",
            sourceURL: tempDir.appendingPathComponent("Source"),
            destinationURL: tempDir.appendingPathComponent("BackupTarget"),
            destinationVolumeUUIDs: ["VOL-UUID-1234", "VOL-UUID-5678"]
        )

        let targetDir = profile.destinationURL
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Write zero-config adoption tag
        DriveProfileMetadata.write(for: profile, to: targetDir)

        // Read metadata tag
        let meta = DriveProfileMetadata.read(from: targetDir)
        try assertTrue(meta != nil)
        try assertEqual(meta?.profileId, profile.id)
        try assertEqual(meta?.profileName, "Sanctuary Vault")

        // VolumeMonitor evaluation check
        let monitor = VolumeMonitor.shared
        let matched = monitor.evaluateMountForAutoBackup(mountedURL: targetDir, profiles: [profile])
        // backupOnVolumeMount is false by default so matched is empty
        try assertEqual(matched.count, 0)

        // Enable backupOnVolumeMount
        var activeMountProfile = profile
        activeMountProfile.backupOnVolumeMount = true

        let matchedActive = monitor.evaluateMountForAutoBackup(
            mountedURL: targetDir,
            profiles: [activeMountProfile],
            cooldownSeconds: 0
        )
        try assertEqual(matchedActive.count, 1)
        try assertEqual(matchedActive.first?.id, profile.id)
    }

    // MARK: - 5. Database Self-Healing & Optimization

    @Test func test_DatabaseSelfHealingAndIntegrity() async throws {
        let tempDir = try createTempDirectory(prefix: "DBSelfHealingTest")
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("sanctuary_healing.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)
        defer { Task { await db.close() } }

        // Integrity check on freshly created DB
        let isHealthy = try await db.performIntegrityCheck()
        try assertTrue(isHealthy)

        // Perform self-healing and vacuum maintenance
        try await db.performSelfHealingMaintenance()

        // CentralDatabase self-healing
        let centralPath = tempDir.appendingPathComponent("central_healing.sqlite").path
        let central = CentralDatabase(databasePath: centralPath)
        let centralHealthy = try central.performIntegrityCheck()
        try assertTrue(centralHealthy)

        try central.performSelfHealingMaintenance()
    }

    // MARK: - 6. FSEventWatcher Lifecycle

    @Test func test_FSEventWatcherLifecycle() throws {
        let tempDir = try createTempDirectory(prefix: "FSEventTest")
        defer { removeTempDirectory(tempDir) }

        let changeCount = TestSafeBox(0)
        let watcher = FSEventWatcher(
            watchedPath: tempDir.path(percentEncoded: false),
            excludePatterns: ["*.ignore"],
            debouncingSeconds: 1
        ) { _ in
            changeCount.modify { $0 += 1 }
        }

        watcher.start()
        watcher.stop()
        try assertEqual(changeCount.value, 0)
    }

    // MARK: - 7. Sparsebundle Container Query

    @Test func test_SparsebundleContainerState() {
        let container = SparsebundleContainer()
        let nonExistent = URL(fileURLWithPath: "/tmp/non_existent_vault_\(UUID().uuidString).sparsebundle")
        let (attached, mountPoint) = container.isAttached(at: nonExistent)
        try! assertFalse(attached)
        try! assertTrue(mountPoint == nil)
    }
}
