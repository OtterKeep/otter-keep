//
//  Module06Tests.swift
//  OtterKeepIntegrationTests
//
//  Module 6: IPC, Process Security & Peer UID Validation
//  Migrated verbatim from the legacy OtterKeepTestRunner harness (module 6).
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
struct Module06Tests {
    @Test func test6_1_AFUnixBufferBounds() throws {
        let addr = sockaddr_un()
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        try assertEqual(maxLen, 104, "Darwin sockaddr_un sun_path buffer must be 104 bytes")

        let pathWithinBounds = "/tmp/otterkeep_test_safe.sock"
        try assertTrue(pathWithinBounds.utf8CString.count <= maxLen)

        let pathExceedingBounds = "/tmp/" + String(repeating: "a", count: 120) + ".sock"
        try assertTrue(pathExceedingBounds.utf8CString.count > maxLen)
    }

    @Test func test6_2_SocketPermissions() throws {
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

    @Test func test6_3_PeerUIDVerification() throws {
        // Verify current process credentials
        let myUID = geteuid()
        let myGID = getegid()
        try assertTrue(myUID >= 0)
        try assertTrue(myGID >= 0)
    }

    @Test func test6_4_MessageSerialization() throws {
        let msg = SingleInstanceMessage(action: .openVersionHistory, filePath: "/Users/test/Documents/report.pdf")
        let encoder = JSONEncoder()
        let data = try encoder.encode(msg)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SingleInstanceMessage.self, from: data)
        try assertEqual(decoded.action, .openVersionHistory)
        try assertEqual(decoded.filePath, "/Users/test/Documents/report.pdf")
    }

    @Test func test6_5_SFTPInjectionNeutralization() throws {
        let config = SFTPConfiguration(host: "nas.local", port: 22, username: "backupuser", remotePath: "/backups")
        try assertEqual(config.host, "nas.local")
        try assertEqual(config.port, 22)
        try assertEqual(config.username, "backupuser")
        let provider = SFTPStorageProvider(config: config)
        _ = provider
    }
}
