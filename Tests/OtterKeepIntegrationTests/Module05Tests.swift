//
//  Module05Tests.swift
//  OtterKeepIntegrationTests
//
//  Module 5: Client-Side Cryptography & Security Integrity
//  Migrated verbatim from the legacy OtterKeepTestRunner harness (module 5).
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
struct Module05Tests {
    @Test func test5_1_OKENC2Encryption() throws {
        let plaintext = Data("Cherished OtterKeep Sanctuary Payload 2026".utf8)
        let passphrase = "Ollie-Super-Secret-Sanctuary-Passphrase"

        let encrypted = try ClientSideEncryptor.encrypt(data: plaintext, passphrase: passphrase)
        try assertTrue(encrypted.count > plaintext.count)
        try assertTrue(encrypted.starts(with: ClientSideEncryptor.headerMagicOKENC2))

        let decrypted = try ClientSideEncryptor.decrypt(envelope: encrypted, passphrase: passphrase)
        try assertEqual(decrypted, plaintext, "Decrypted data must match original plaintext")
    }

    @Test func test5_2_DSENC1BackwardCompatibility() throws {
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

    @Test func test5_3_TamperResistance() throws {
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

    @Test func test5_4_HashCalculations() throws {
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
}
