//
//  UXRegressionTests.swift
//  OtterKeepIntegrationTests
//
//  Regression guards for the UX hardening pass: single-slot modal routing, gauge segment
//  distribution, timeline scrubber index math, non-modal success feedback, locale-aware schedule
//  labels, and the three-part error architecture.
//

import Foundation
import OtterKeepCore
import OtterKeepDomain
import Testing
@testable import OtterKeepUI

@MainActor
@Suite(.serialized)
struct UXRegressionTests {
    // MARK: - Central Modal Route

    @Test func testModalRouteIsExclusiveAndQueuesRequests() throws {
        let appState = AppState()

        try assertNil(appState.activeModal)

        appState.showPreferencesModal = true
        try assertEqual(appState.activeModal, .preferences)

        // A second request must not steal the presentation slot.
        appState.showSystemLogsModal = true
        try assertEqual(appState.activeModal, .preferences)
        try assertEqual(appState.pendingModal, .systemLogs)

        // Dismissing promotes the queued request instead of dropping it.
        appState.showPreferencesModal = false
        try assertNil(appState.activeModal)
        appState.promotePendingModal()
        try assertEqual(appState.activeModal, .systemLogs)
        try assertNil(appState.pendingModal)

        appState.showSystemLogsModal = false
        try assertNil(appState.activeModal)
    }

    @Test func testModalRouteIgnoresDuplicateRequests() throws {
        let appState = AppState()

        appState.showPreferencesModal = true
        appState.showPreferencesModal = true

        try assertEqual(appState.activeModal, .preferences)
        try assertNil(appState.pendingModal)
    }

    @Test func testDismissingQueuedRouteClearsPendingSlot() throws {
        let appState = AppState()

        appState.showPreferencesModal = true
        appState.showSystemLogsModal = true
        try assertEqual(appState.pendingModal, .systemLogs)

        // Cancelling the queued route must not disturb the visible one.
        appState.showSystemLogsModal = false
        try assertEqual(appState.activeModal, .preferences)
        try assertNil(appState.pendingModal)
    }

    @Test func testDestinationEditorStacksOnProfileSettingsInsteadOfQueueing() throws {
        let appState = AppState()

        appState.showProfileSettingsModal = true
        try assertEqual(appState.activeModal, .profileSettings)

        // The editor is a nested sheet inside the settings modal. Requesting it must not be queued
        // behind the settings sheet, otherwise it only appears after that sheet closes.
        appState.openDestinationEditor(destination: nil)
        try assertTrue(appState.showRemoteDestinationEditorSheet)
        try assertEqual(appState.activeModal, .profileSettings)
        try assertNil(appState.pendingModal)

        // Closing the editor leaves the settings sheet untouched.
        appState.showRemoteDestinationEditorSheet = false
        try assertFalse(appState.showRemoteDestinationEditorSheet)
        try assertEqual(appState.activeModal, .profileSettings)
        try assertNil(appState.pendingModal)
    }

    // MARK: - Storage Gauge Segments

    @Test func testGaugeSegmentsNeverOverflowTheTrack() throws {
        let gauge = StorageGaugeBar(
            totalBytes: 1_000,
            backupBytes: 400,
            freeBytes: 500,
            title: "Test"
        )

        for trackWidth in [CGFloat(40), 120, 320, 900] {
            let segments = gauge.segmentWidths(for: trackWidth)
            let totalWidth = segments.reduce(CGFloat.zero) { $0 + $1.width }
            let gaps = CGFloat(max(segments.count - 1, 0)) * 2
            try assertTrue(
                totalWidth + gaps <= trackWidth + 0.5,
                "Segments overflowed a \(trackWidth)pt track: \(totalWidth) + \(gaps) gaps"
            )
        }
    }

    @Test func testGaugeSegmentsDropInvisibleShares() throws {
        // A 0.1% backup share is below the visibility threshold, so only free space is drawn.
        let gauge = StorageGaugeBar(
            totalBytes: 1_000_000,
            backupBytes: 1_000,
            freeBytes: 999_000,
            title: "Test"
        )

        let segments = gauge.segmentWidths(for: 300)
        try assertEqual(segments.count, 1)
    }

    @Test func testGaugeSegmentsAreEmptyForZeroWidth() throws {
        let gauge = StorageGaugeBar(totalBytes: 100, backupBytes: 50, freeBytes: 50, title: "Test")
        try assertTrue(gauge.segmentWidths(for: 0).isEmpty)
    }

    // MARK: - Timeline Scrubber Index Math

    @Test func testScrubberIndexClampsToSnapshotBounds() throws {
        let width: CGFloat = 200

        try assertEqual(VisualTimelineScrubberView.snapshotIndex(forX: -500, trackWidth: width, count: 5), 0)
        try assertEqual(VisualTimelineScrubberView.snapshotIndex(forX: 5_000, trackWidth: width, count: 5), 4)
        try assertEqual(VisualTimelineScrubberView.snapshotIndex(forX: 0, trackWidth: width, count: 1), 0)
        try assertEqual(VisualTimelineScrubberView.snapshotIndex(forX: 100, trackWidth: width, count: 0), 0)
    }

    @Test func testScrubberIndexMapsTrackEndsToFirstAndLastSnapshot() throws {
        let width: CGFloat = 200
        let inset: CGFloat = 8

        try assertEqual(VisualTimelineScrubberView.snapshotIndex(forX: inset, trackWidth: width, count: 4), 0)
        try assertEqual(VisualTimelineScrubberView.snapshotIndex(forX: width - inset, trackWidth: width, count: 4), 3)
    }

    // MARK: - Success Feedback Is Non-Modal

    @Test func testSuccessFeedbackUsesBannerInsteadOfAlert() throws {
        let appState = AppState()

        appState.showSuccess("Profile saved")

        try assertEqual(appState.successBannerMessage, "Profile saved")
        try assertFalse(appState.showAlert)
        try assertNil(appState.activeModal)
    }

    @Test func testErrorFeedbackStillUsesBlockingAlert() throws {
        let appState = AppState()

        appState.showError("Something needs attention")

        try assertTrue(appState.showAlert)
        try assertEqual(appState.alertMessage, "Something needs attention")
        try assertNil(appState.successBannerMessage)
    }

    // MARK: - Locale-Aware Schedule Labels

    @Test func testScheduleHourLabelsCoverEveryHour() throws {
        let labels = ScheduleTimeFormatting.hourLabels

        try assertEqual(labels.count, 24)
        try assertEqual(labels.map(\.hour), Array(0..<24))
        try assertTrue(labels.allSatisfy { !$0.label.isEmpty })
    }

    @Test func testScheduleMinuteLabelsAreNonEmpty() throws {
        try assertEqual(ScheduleTimeFormatting.minuteOptions, [0, 15, 30, 45])
        for minute in ScheduleTimeFormatting.minuteOptions {
            try assertTrue(!ScheduleTimeFormatting.minuteLabel(minute).isEmpty)
        }
    }

    // MARK: - Three-Part Error Architecture

    @Test func testEveryAnalyzedFailureCarriesGuaranteeAndRecovery() throws {
        let cases: [(Error, URL?, URL?)] = [
            (
                NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC), userInfo: [NSLocalizedDescriptionKey: "No space left on device"]),
                URL(fileURLWithPath: "/Volumes/ExternalSSD"),
                URL(fileURLWithPath: "/Users/user/Docs")
            ),
            (
                NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: [NSLocalizedDescriptionKey: "Permission denied"]),
                URL(fileURLWithPath: "/Volumes/ExternalSSD"),
                URL(fileURLWithPath: "/Users/user/Docs")
            ),
            (
                NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected failure"]),
                URL(fileURLWithPath: "/Volumes/ExternalSSD"),
                URL(fileURLWithPath: "/Users/user/Docs")
            ),
        ]

        for (error, destination, source) in cases {
            let analyzed = AppState.analyzeBackupError(error, destinationURL: destination, sourceURL: source)
            try assertTrue(!analyzed.title.isEmpty)
            try assertTrue(!analyzed.message.isEmpty)
            try assertTrue(!analyzed.detailedReason.isEmpty)
            try assertTrue(!analyzed.guaranteeText.isEmpty)
            try assertTrue(!analyzed.recoveryAction.label.isEmpty)
        }
    }

    @Test func testPermissionFailureOffersFullDiskAccessRecovery() throws {
        // Both paths must exist, otherwise the missing-drive branch wins before the permission check.
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        let analyzed = AppState.analyzeBackupError(
            error,
            destinationURL: URL(fileURLWithPath: NSTemporaryDirectory()),
            sourceURL: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        try assertEqual(analyzed.recoveryAction.kind, .openFullDiskAccess)
    }

    // MARK: - Localization Coverage

    @Test func testNewUXKeysAreTranslatedInBothLanguages() throws {
        let keys: [L10n.Key] = [
            .closeButton,
            .clearSearchButton,
            .removeExclusionButton,
            .compareVersionsButton,
            .openInFinderButton,
            .previousSnapshotButton,
            .nextSnapshotButton,
            .refreshLogsButton,
            .stopBackupAccessibility,
            .startBackupAccessibility,
            .modalPayloadUnavailableTitle,
            .modalPayloadUnavailableMessage,
            .supportBundleButton,
            .feedbackGuaranteeTitle,
            .feedbackGuaranteeSnapshotsSafe,
            .feedbackGuaranteeNothingModified,
            .recoveryOpenFullDiskAccess,
            .recoveryViewLogs,
            .ignoreFilesTooltipDesc,
            .driveAutomationTooltipDesc,
            .clientEncryptionTooltipDesc,
            .encryptionPassphraseFieldLabel,
            .encryptionPassphraseFieldPlaceholder,
            .confirmPassphraseFieldLabel,
            .confirmPassphraseFieldPlaceholder,
            .passphraseMismatchError,
            .biometricsActionGatesSection,
            .biometricsSecureEnclaveToggle,
            .encryptionPermanentTag,
            .encryptionKeychainStoredDesc,
            .unencryptedProfileNotice,
            .centralDatabaseTitle,
            .centralDatabaseVacuumButton,
            .unadoptedDriveDiscoveredTitle,
            .unadoptedDriveDiscoveredMessageFormat,
            .unadoptedDriveAdoptAction,
            .unadoptedDriveDismissAction,
        ]

        for key in keys {
            try assertTrue(L10n.hasExplicitTranslation(for: key, in: .english), "Missing EN translation for \(key.rawValue)")
            try assertTrue(L10n.hasExplicitTranslation(for: key, in: .hungarian), "Missing HU translation for \(key.rawValue)")
        }
    }

    // MARK: - Profile Settings Transactional Lifecycle

    @Test func testProfileSettingsCancelRevertsEditsAndSavePersists() throws {
        let appState = AppState()
        let testProfile = BackupProfile(
            id: UUID(),
            name: "Initial Profile Name",
            sourceURL: URL(fileURLWithPath: "/tmp/source"),
            destinationURL: URL(fileURLWithPath: "/tmp/dest")
        )
        appState.profiles = [testProfile]
        appState.selectedProfileId = testProfile.id

        // 1. Open profile settings modal -> baseline is captured
        appState.showProfileSettingsModal = true
        try assertEqual(appState.showProfileSettingsModal, true)
        try assertEqual(appState.profileSettingsBaseline?.name, "Initial Profile Name")

        // 2. Modify profile properties while modal is open
        var edited = testProfile
        edited.name = "Unsaved Draft Name"
        edited.pruningPolicy.isAutoPruningEnabled = true
        appState.selectedProfile = edited

        try assertEqual(appState.selectedProfile?.name, "Unsaved Draft Name")
        try assertEqual(appState.selectedProfile?.pruningPolicy.isAutoPruningEnabled, true)

        // 3. Cancel settings -> must revert to baseline
        appState.cancelProfileSettings()
        try assertEqual(appState.showProfileSettingsModal, false)
        try assertNil(appState.profileSettingsBaseline)
        try assertEqual(appState.selectedProfile?.name, "Initial Profile Name")
        try assertEqual(appState.selectedProfile?.pruningPolicy.isAutoPruningEnabled, false)

        // 4. Open again and test saving
        appState.showProfileSettingsModal = true
        var savedEdit = testProfile
        savedEdit.name = "Persisted Name"
        appState.selectedProfile = savedEdit

        appState.saveProfileSettings()
        try assertEqual(appState.showProfileSettingsModal, false)
        try assertNil(appState.profileSettingsBaseline)
        try assertEqual(appState.selectedProfile?.name, "Persisted Name")
    }
}
