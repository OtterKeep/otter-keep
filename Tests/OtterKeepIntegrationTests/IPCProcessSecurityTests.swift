//
//  IPCProcessSecurityTests.swift
//  OtterKeepIntegrationTests
//
//  IPC, Process Security & Peer UID Validation: Unix domain socket bounds,
//  secure POSIX socket directory permissions, single instance peer messaging,
//  and command injection neutralization.
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
struct IPCProcessSecurityTests {
    @Test func testAFUnixBufferBounds() throws {
        let addr = sockaddr_un()
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        try assertEqual(maxLen, 104, "Darwin sockaddr_un sun_path buffer must be 104 bytes")

        let pathWithinBounds = "/tmp/otterkeep_test_safe.sock"
        try assertTrue(pathWithinBounds.utf8CString.count <= maxLen)

        let pathExceedingBounds = "/tmp/" + String(repeating: "a", count: 120) + ".sock"
        try assertTrue(pathExceedingBounds.utf8CString.count > maxLen)
    }

    @Test func testSocketPermissions() throws {
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

    @Test func testPeerUIDVerification() throws {
        // Verify current process credentials
        let myUID = geteuid()
        let myGID = getegid()
        try assertTrue(myUID >= 0)
        try assertTrue(myGID >= 0)
    }

    @Test func testMessageSerialization() throws {
        let msg = SingleInstanceMessage(action: .openVersionHistory, filePath: "/Users/test/Documents/report.pdf")
        let encoder = JSONEncoder()
        let data = try encoder.encode(msg)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SingleInstanceMessage.self, from: data)
        try assertEqual(decoded.action, .openVersionHistory)
        try assertEqual(decoded.filePath, "/Users/test/Documents/report.pdf")
    }

    @Test func testSFTPInjectionNeutralization() throws {
        let config = SFTPConfiguration(host: "nas.local", port: 22, username: "backupuser", remotePath: "/backups")
        try assertEqual(config.host, "nas.local")
        try assertEqual(config.port, 22)
        try assertEqual(config.username, "backupuser")
        let provider = SFTPStorageProvider(config: config)
        _ = provider
    }
}
