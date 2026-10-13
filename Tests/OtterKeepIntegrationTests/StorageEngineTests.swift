//
//  StorageEngineTests.swift
//  OtterKeepIntegrationTests
//
//  Storage Engine, APFS Copy-on-Write, Drivers & Filesystem Fidelity Suite
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
struct StorageEngineTests {
    @Test func test_VolumeCapabilities() async throws {
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

    @Test func test_APFSClonefile() async throws {
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

    @Test func test_HardlinkFallback() async throws {
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

    @Test func test_ExtendedAttributes() throws {
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

    @Test func test_AtomicMove() async throws {
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

    @Test func test_FallbackStorageProvider() async throws {
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

    @Test func test_ExFATAndNTFSCapabilities() throws {
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

    @Test func test_DriverRegistryResolution() throws {
        let registry = FileSystemDriverRegistry.shared
        let apfsDriver = registry.driver(forFSType: "apfs")
        try assertEqual(apfsDriver.fsTypeName, "apfs")

        let exfatDriver = registry.driver(forFSType: "exfat")
        try assertEqual(exfatDriver.fsTypeName, "exfat")

        let ntfsDriver = registry.driver(forFSType: "ntfs")
        try assertEqual(ntfsDriver.fsTypeName, "ntfs")
    }

    @Test func test_DefaultFileSystemProviderRouting() async throws {
        let provider = DefaultFileSystemProvider()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let caps = try await provider.capabilities(at: home)
        try assertTrue(!caps.fsTypeName.isEmpty)

        // Verify FileSystemDriverRegistry resolution
        let resolved = FileSystemDriverRegistry.shared.driver(forFSType: caps.fsTypeName)
        let regCaps = try await resolved.capabilities(at: home)
        try assertEqual(caps.fsTypeName, regCaps.fsTypeName)
    }

    @Test func test_BackblazeB2Configuration() async throws {
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
}
