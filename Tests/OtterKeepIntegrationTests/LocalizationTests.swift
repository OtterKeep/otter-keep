//
//  LocalizationTests.swift
//  OtterKeepIntegrationTests
//
//  Localization & Bilingual Parity: Complete key parity between English and
//  Hungarian, format specifier safety, and localized suffix formatting.
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
struct LocalizationTests {
    @Test func testLocalizationKeyParity() throws {
        let allKeys = L10n.Key.allCases
        try assertTrue(allKeys.count >= 200, "Localization dictionary should have comprehensive key coverage")

        // Verify every key resolves in both Hungarian and English without throwing empty string
        for key in allKeys {
            try assertTrue(
                L10n.hasExplicitTranslation(for: key, in: .english),
                "Key \(key.rawValue) must be registered in the unified string table"
            )
            try assertTrue(
                L10n.hasExplicitTranslation(for: key, in: .hungarian),
                "Key \(key.rawValue) must be registered in the unified string table"
            )
            let hu = L10n.t(key, lang: .hungarian)
            let en = L10n.t(key, lang: .english)
            try assertTrue(!hu.isEmpty, "Key \(key.rawValue) must have non-empty Hungarian translation")
            try assertTrue(!en.isEmpty, "Key \(key.rawValue) must have non-empty English translation")
        }
    }

    @Test func testLocalizationNonEmptyStrings() throws {
        try assertTrue(!L10n.t(.navDashboard, lang: .english).isEmpty)
        try assertTrue(!L10n.t(.navDashboard, lang: .hungarian).isEmpty)
        try assertTrue(!L10n.t(.feedbackSuccessTitle, lang: .hungarian).isEmpty)
        try assertTrue(!L10n.t(.feedbackSuccessTitle, lang: .english).isEmpty)
    }

    @Test func testFormatSpecifierConsistency() throws {
        // Verify restore feedback message formatting in both languages without crashing
        let huRestore = L10n.format(.feedbackRestoreSuccessMessage, "snapshot_1", Int64(5), lang: .hungarian)
        let enRestore = L10n.format(.feedbackRestoreSuccessMessage, "snapshot_1", Int64(5), lang: .english)
        try assertTrue(huRestore.contains("snapshot_1") && huRestore.contains("5"))
        try assertTrue(enRestore.contains("snapshot_1") && enRestore.contains("5"))

        // Verify all format keys have identical token count
        let hu = L10n.t(.feedbackSuccessMessage, lang: .hungarian)
        let en = L10n.t(.feedbackSuccessMessage, lang: .english)
        try assertEqual(hu.components(separatedBy: "%@").count, en.components(separatedBy: "%@").count)

        // Verify scrub format strings execute without SIGSEGV in both Hungarian and English
        let huScrub = L10n.format(.scrubSuccessMessage, "Profile A", Int64(3), Int64(450), lang: .hungarian)
        let enScrub = L10n.format(.scrubSuccessMessage, "Profile A", Int64(3), Int64(450), lang: .english)
        try assertTrue(huScrub.contains("Profile A") && huScrub.contains("3") && huScrub.contains("450"))
        try assertTrue(enScrub.contains("Profile A") && enScrub.contains("3") && enScrub.contains("450"))

        let huScrubErr = L10n.format(.scrubCorruptedMessage, "Profile A", Int64(2), lang: .hungarian)
        let enScrubErr = L10n.format(.scrubCorruptedMessage, "Profile A", Int64(2), lang: .english)
        try assertTrue(huScrubErr.contains("Profile A") && huScrubErr.contains("2"))
        try assertTrue(enScrubErr.contains("Profile A") && enScrubErr.contains("2"))

        let huAlert = L10n.format(.scrubberCorruptedAlertMessage, Int64(5), "snap_01", lang: .hungarian)
        let enAlert = L10n.format(.scrubberCorruptedAlertMessage, Int64(5), "snap_01", lang: .english)
        try assertTrue(huAlert.contains("5") && huAlert.contains("snap_01"))
        try assertTrue(enAlert.contains("5") && enAlert.contains("snap_01"))
    }

    @Test func testRestoredSuffixParity() throws {
        let initialLang = LocalizationManager.shared.currentLanguage
        defer { LocalizationManager.shared.currentLanguage = initialLang }

        LocalizationManager.shared.currentLanguage = .hungarian
        let huSuffix = L10n.format(.restoredSuffixFormat, 1)
        LocalizationManager.shared.currentLanguage = .english
        let enSuffix = L10n.format(.restoredSuffixFormat, 1)
        try assertTrue(huSuffix.contains("visszaállított 1"))
        try assertTrue(enSuffix.contains("restored 1"))
    }
}
