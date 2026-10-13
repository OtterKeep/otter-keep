//
//  PresentationUITests.swift
//  OtterKeepIntegrationTests
//
//  Presentation & UI Design System: Theme Tokens, Three-Part Error Reassurance,
//  Configuration Export/Import Serialization, Multi-Profile Tracking, Version Metadata,
//  Restore Modes and Feedback, and AppState Settings Side-Effects.
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
struct PresentationUITests {
    @Test func testOtterThemeTokens() throws {
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

    @Test func testThreePartErrorArchitecture() throws {
        let dummyError = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC), userInfo: [NSLocalizedDescriptionKey: "No space left on device"])
        let analyzed = AppState.analyzeBackupError(dummyError, destinationURL: URL(fileURLWithPath: "/Volumes/ExternalSSD"), sourceURL: URL(fileURLWithPath: "/Users/user/Docs"))

        // Part 1: What happened (title & message)
        try assertTrue(!analyzed.title.isEmpty)
        try assertTrue(!analyzed.message.isEmpty)

        // Part 2 & 3: Sanctuary reassurance & restorative pathway
        try assertTrue(!analyzed.detailedReason.isEmpty)
    }

    @Test func testConfigurationArchiveSerialization() throws {
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

    @Test func testAppStateMultiProfileTracking() async throws {
        let appState = AppState()
        let p1 = UUID()
        let p2 = UUID()

        try assertFalse(appState.isBackupRunning(for: p1))
        try assertFalse(appState.isBackupRunning(for: p2))
    }

    @Test func testOtterAboutViewMetadata() throws {
        let manifest = try VersionManifest.load()
        try assertEqual(CoreEngine.version, manifest.version)
        try assertEqual(CoreEngine.buildNumber, manifest.build)
    }

    @Test func testRestoreOperationFeedbackAndModes() throws {
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
    @Test func testSettingsStateSideEffectPropagation() throws {
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

    @Test func testProfileHealthStatusEvaluations() throws {
        let appState = AppState()
        let profile = BackupProfile(
            name: "Health Test Profile",
            sourceURL: URL(fileURLWithPath: "/tmp/src"),
            destinationURL: URL(fileURLWithPath: "/tmp/dst")
        )

        // 1. Never backed up
        let neverStatus = appState.profileHealthStatus(for: profile)
        try assertEqual(neverStatus, .neverBackedUp)
        try assertEqual(neverStatus.systemImage, "questionmark.circle.fill")

        // 2. Healthy status
        let now = Date()
        let healthySnap = SnapshotRecord(
            id: "2026-10-13_120000",
            timestamp: now.addingTimeInterval(-3600),
            status: "completed",
            totalFiles: 10,
            totalBytes: 2048,
            snapshotPath: "2026-10-13_120000"
        )
        appState.cacheProfileStatus(profileId: profile.id, latestSnapshot: healthySnap, snapshotCount: 1)
        let healthyStatus = appState.profileHealthStatus(for: profile, now: now)
        try assertEqual(healthyStatus, .healthy)
        try assertEqual(healthyStatus.systemImage, "checkmark.circle.fill")

        // 3. Failed status (last summary has errors)
        let failedSummary = BackupSessionSummary(
            snapshotId: "2026-10-13_120000",
            profileName: profile.name,
            timestamp: now.addingTimeInterval(-7200),
            durationSeconds: 100,
            totalScannedFiles: 10,
            totalScannedBytes: 2048,
            copiedCount: 5,
            copiedBytes: 1024,
            clonedCount: 0,
            clonedBytes: 0,
            skippedCount: 0,
            errorCount: 2,
            skippedItems: [],
            errorItems: [],
            status: "completed_with_errors",
            averageSpeedBytesPerSecond: 1024.0,
            autoPrunedSnapshotsCount: 0
        )
        appState.cacheProfileStatus(profileId: profile.id, latestSnapshot: healthySnap, snapshotCount: 1, lastSummary: failedSummary)
        let failedStatus = appState.profileHealthStatus(for: profile, now: now)
        try assertEqual(failedStatus, .failed(errorCount: 2))
        try assertEqual(failedStatus.systemImage, "exclamationmark.triangle.fill")

        // 4. Stale > 14 days
        let staleDate = now.addingTimeInterval(-15 * 86400)
        let staleSnap = SnapshotRecord(
            id: "2026-09-28_120000",
            timestamp: staleDate,
            status: "completed",
            totalFiles: 10,
            totalBytes: 2048,
            snapshotPath: "2026-09-28_120000"
        )
        appState.cacheProfileStatus(profileId: profile.id, latestSnapshot: staleSnap, snapshotCount: 1, lastSummary: nil)
        let staleStatus = appState.profileHealthStatus(for: profile, now: now)
        try assertEqual(staleStatus, .staleFourteenDays(daysOld: 15))
        try assertEqual(staleStatus.systemImage, "clock.badge.exclamationmark.fill")

        // 5. Schedule overdue (< 14 days, e.g. 2 days ago with daily schedule)
        var scheduledProfile = profile
        scheduledProfile.schedule = BackupSchedule(isEnabled: true, frequency: .daily, hour: 12, minute: 0)
        let twoDaysAgo = now.addingTimeInterval(-2 * 86400)
        let scheduleSnap = SnapshotRecord(
            id: "2026-10-11_120000",
            timestamp: twoDaysAgo,
            status: "completed",
            totalFiles: 10,
            totalBytes: 2048,
            snapshotPath: "2026-10-11_120000"
        )
        appState.cacheProfileStatus(profileId: scheduledProfile.id, latestSnapshot: scheduleSnap, snapshotCount: 1, lastSummary: nil)
        let overdueStatus = appState.profileHealthStatus(for: scheduledProfile, now: now)
        try assertEqual(overdueStatus, .scheduleOverdue)
        try assertEqual(overdueStatus.systemImage, "clock.badge.questionmark.fill")
    }

    @Test func testProfileDeletionConfirmationAndSaveUnification() throws {
        let appState = AppState()
        let p1 = BackupProfile(name: "P1", sourceURL: URL(fileURLWithPath: "/tmp/src1"), destinationURL: URL(fileURLWithPath: "/tmp/dst1"))
        let p2 = BackupProfile(name: "P2", sourceURL: URL(fileURLWithPath: "/tmp/src2"), destinationURL: URL(fileURLWithPath: "/tmp/dst2"))
        appState.profiles = [p1, p2]

        // Test deletion state tracking
        try assertFalse(appState.showDeleteProfileConfirmation)
        try assertNil(appState.profilePendingDeletion)

        appState.profilePendingDeletion = p2
        appState.showDeleteProfileConfirmation = true
        try assertTrue(appState.showDeleteProfileConfirmation)
        try assertEqual(appState.profilePendingDeletion?.id, p2.id)

        // Confirm cancellation clears pending profile
        appState.profilePendingDeletion = nil
        appState.showDeleteProfileConfirmation = false
        try assertFalse(appState.showDeleteProfileConfirmation)
        try assertNil(appState.profilePendingDeletion)

        // Verify unified button translation key exists in Hungarian and English
        try assertEqual(L10n.t(.save, lang: .english), "Save")
        try assertEqual(L10n.t(.save, lang: .hungarian), "Mentés")
    }

    @Test func testOttieMascotImageResolution() throws {
        let warningImg = OtterKeepLogoView.resolveSanctuaryWarningImage()
        try assertNotNil(warningImg)
        let safeImg = OtterKeepLogoView.resolveSanctuarySafeImage()
        try assertNotNil(safeImg)
        let dangerImg = OtterKeepLogoView.resolveSanctuaryDangerImage()
        try assertNotNil(dangerImg)
        let logoImg = OtterKeepLogoView.resolveLogoImage()
        try assertNotNil(logoImg)
        let successImg = OtterKeepLogoView.resolveSuccessImage()
        try assertNotNil(successImg)
        let failureImg = OtterKeepLogoView.resolveFailureImage()
        try assertNotNil(failureImg)
    }
}
