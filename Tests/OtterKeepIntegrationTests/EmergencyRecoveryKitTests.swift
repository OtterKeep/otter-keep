//
//  EmergencyRecoveryKitTests.swift
//  OtterKeepIntegrationTests
//
//  Rigorous testing for Emergency Recovery Kit (PDF metadata, QR code payload,
//  cryptographic fingerprinting, and CLI restore instructions).
//

import Foundation
import Testing
import OtterKeepDomain
import OtterKeepCore

@MainActor
@Suite(.serialized)
struct EmergencyRecoveryKitTests {
    @Test func testEmergencyKitMetadataGeneration() throws {
        let tempSource = URL(fileURLWithPath: "/tmp/otter_source_test")
        let tempDest = URL(fileURLWithPath: "/tmp/otter_dest_test")
        let profile = BackupProfile(
            name: "Sanctuary Vault",
            sourceURL: tempSource,
            destinationURL: tempDest
        )

        let passphrase = "Ollie-Secret-Vault-Password-2026"
        let metadata = EmergencyKitBuilder.buildMetadata(
            for: profile,
            passphrase: passphrase,
            includePassphrase: true
        )

        try assertEqual(metadata.profileName, "Sanctuary Vault")
        try assertEqual(metadata.profileId, profile.id)
        try assertEqual(metadata.sourceDirectory, tempSource.path)
        try assertEqual(metadata.destinationDescription, tempDest.path)
        try assertEqual(metadata.embeddedPassphrase, passphrase)
        try assertTrue(!metadata.saltHex.isEmpty, "Salt hex must not be empty")
        try assertTrue(!metadata.keyFingerprint.isEmpty, "Key fingerprint must not be empty")
        try assertTrue(!metadata.qrPayload.isEmpty, "QR code payload must contain serialized metadata")

        let pngData = EmergencyKitBuilder.generateQRCodePNGData(for: metadata.qrPayload)
        try assertTrue(pngData != nil, "QR code PNG generation must succeed")
        try assertTrue((pngData?.count ?? 0) > 100, "QR PNG data must be a valid image")
    }

    @Test func testEmergencyKitExcludesPassphraseWhenConfigured() throws {
        let profile = BackupProfile(
            name: "Vault Zero",
            sourceURL: URL(fileURLWithPath: "/tmp/source"),
            destinationURL: URL(fileURLWithPath: "/tmp/dest")
        )

        let metadata = EmergencyKitBuilder.buildMetadata(
            for: profile,
            passphrase: "SuperSecretPassword",
            includePassphrase: false
        )

        try assertTrue(metadata.embeddedPassphrase == nil, "Embedded passphrase must be nil when includePassphrase is false")
        try assertTrue(!metadata.keyFingerprint.isEmpty, "Key fingerprint is still present for verification")
    }

    @Test func testEmergencyKitTerminalRestoreCommand() throws {
        let profile = BackupProfile(
            name: "Docs Sanctuary",
            sourceURL: URL(fileURLWithPath: "/Users/test/Documents"),
            destinationURL: URL(fileURLWithPath: "/Volumes/BackupDrive/OtterKeep")
        )

        let metadata = EmergencyKitBuilder.buildMetadata(
            for: profile,
            passphrase: "MyPassphrase",
            includePassphrase: false
        )

        try assertTrue(metadata.cliRestoreCommand.contains("otterkeep restore"), "Must include CLI restore invocation")
        try assertTrue(metadata.cliRestoreCommand.contains(profile.destinationURL.path), "Must point to backup destination")
    }
}
