//
//  Module10Tests.swift
//  OtterKeepIntegrationTests
//
//  Module 10: Modern UI Design System, Sanctuary Experience & Configuration
//  Migrated verbatim from the legacy OtterKeepTestRunner harness (module 10).
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
struct Module10Tests {
    @Test func test10_1_OtterThemeTokens() throws {
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

    @Test func test10_2_ThreePartErrorArchitecture() throws {
        let dummyError = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC), userInfo: [NSLocalizedDescriptionKey: "No space left on device"])
        let analyzed = AppState.analyzeBackupError(dummyError, destinationURL: URL(fileURLWithPath: "/Volumes/ExternalSSD"), sourceURL: URL(fileURLWithPath: "/Users/user/Docs"))

        // Part 1: What happened (title & message)
        try assertTrue(!analyzed.title.isEmpty)
        try assertTrue(!analyzed.message.isEmpty)

        // Part 2 & 3: Sanctuary reassurance & restorative pathway
        try assertTrue(!analyzed.detailedReason.isEmpty)
    }

    @Test func test10_3_ConfigurationArchiveSerialization() throws {
        let profile = BackupProfile(name: "Portable Profile", sourceURL: URL(fileURLWithPath: "/Users/test/Code"), destinationURL: URL(fileURLWithPath: "/Volumes/Backup/Code"))
        let settings = AppSettings(language: .english, launchAtLogin: true, startMinimized: false, debugFileLoggingEnabled: false, finderIntegrationEnabled: true, themeMode: .system)
        let archive = ConfigurationExportArchive(profiles: [profile], settings: settings, photosConfig: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(archive)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ConfigurationExportArchive.self, from: data)
        try assertEqual(decoded.appVersion, CoreEngine.version)
        try assertEqual(decoded.profiles.count, 1)
        try assertEqual(decoded.profiles.first?.name, "Portable Profile")
    }

    @Test func test10_4_AppStateMultiProfileTracking() async throws {
        let appState = AppState()
        let p1 = UUID()
        let p2 = UUID()

        try assertFalse(appState.isBackupRunning(for: p1))
        try assertFalse(appState.isBackupRunning(for: p2))
    }

    @Test func test10_5_OtterAboutViewMetadata() throws {
        let manifest = try VersionManifest.load()
        try assertEqual(CoreEngine.version, manifest.version)
        try assertEqual(CoreEngine.buildNumber, manifest.build)
    }

    @Test func test10_6_DefaultFileSystemProviderRouting() async throws {
        let provider = DefaultFileSystemProvider()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let caps = try await provider.capabilities(at: home)
        try assertTrue(!caps.fsTypeName.isEmpty)

        // Verify FileSystemDriverRegistry resolution
        let resolved = FileSystemDriverRegistry.shared.driver(forFSType: caps.fsTypeName)
        let regCaps = try await resolved.capabilities(at: home)
        try assertEqual(caps.fsTypeName, regCaps.fsTypeName)
    }

    @Test func test10_7_RestoreOperationFeedbackAndModes() throws {
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

    /// Guards the `AppState` feature-store split: writing a settings property must still drive the
    /// subsystems that the pre-split `didSet` observers updated (theme/language propagation, debug
    /// logging session, Finder integration toggle).
    @Test func test10_8_SettingsStateSideEffectPropagation() throws {
        let appState = AppState()
        let originalLanguage = LocalizationManager.shared.currentLanguage
        let originalTheme = LocalizationManager.shared.currentTheme
        let originalFinderEnabled = FinderIntegrationStore.shared.isEnabled
        let originalDebugLogging = appState.isDebugFileLoggingEnabled
        let originalProfiles = appState.profiles
        defer {
            appState.profiles = originalProfiles
            appState.currentLanguage = originalLanguage
            appState.currentTheme = originalTheme
            appState.isFinderIntegrationEnabled = originalFinderEnabled
            appState.isDebugFileLoggingEnabled = originalDebugLogging
        }

        // The language observer also renames the default profile on disk, so the profile list is
        // temporarily emptied to keep the real `~/.otterkeep/profiles.json` untouched.
        appState.profiles = []
        let newLanguage: AppLanguage = originalLanguage == .hungarian ? .english : .hungarian
        appState.currentLanguage = newLanguage
        try assertEqual(appState.currentLanguage, newLanguage)
        try assertEqual(
            LocalizationManager.shared.currentLanguage,
            newLanguage,
            "Changing the language must reach LocalizationManager"
        )
        appState.profiles = originalProfiles

        let newTheme: AppThemeMode = originalTheme == .dark ? .light : .dark
        appState.currentTheme = newTheme
        try assertEqual(appState.currentTheme, newTheme)
        try assertEqual(
            LocalizationManager.shared.currentTheme,
            newTheme,
            "Changing the theme must reach LocalizationManager"
        )

        appState.isFinderIntegrationEnabled = !originalFinderEnabled
        try assertEqual(
            FinderIntegrationStore.shared.isEnabled,
            appState.isFinderIntegrationEnabled,
            "Toggling Finder integration must reach FinderIntegrationStore"
        )

        appState.isDebugFileLoggingEnabled = true
        try assertNotNil(
            appState.currentDebugLogFileURL,
            "Enabling debug logging must expose the active debug log file"
        )
        appState.isDebugFileLoggingEnabled = false
        try assertNil(
            appState.currentDebugLogFileURL,
            "Disabling debug logging must clear the active debug log file"
        )
    }
}
