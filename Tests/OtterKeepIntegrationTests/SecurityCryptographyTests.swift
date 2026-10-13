//
//  SecurityCryptographyTests.swift
//  OtterKeepIntegrationTests
//
//  Security & Cryptography: Client-Side Envelope Encryption (OKENC2 / DSENC1),
//  Tamper Resistance, Checksum Verification, and Bit-Rot Scrubbing.
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
struct SecurityCryptographyTests {
    @Test func testOKENC2Encryption() throws {
        let plaintext = Data("Cherished OtterKeep Sanctuary Payload 2026".utf8)
        let passphrase = "Ollie-Super-Secret-Sanctuary-Passphrase"

        let encrypted = try ClientSideEncryptor.encrypt(data: plaintext, passphrase: passphrase)
        try assertTrue(encrypted.count > plaintext.count)
        try assertTrue(encrypted.starts(with: ClientSideEncryptor.headerMagicOKENC2))

        let decrypted = try ClientSideEncryptor.decrypt(envelope: encrypted, passphrase: passphrase)
        try assertEqual(decrypted, plaintext, "Decrypted data must match original plaintext")
    }

    @Test func testDSENC1BackwardCompatibility() throws {
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

    @Test func testTamperResistance() throws {
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

    @Test func testHashCalculations() throws {
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

    @Test func testDataScrubberBitRotDetection() async throws {
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
}
