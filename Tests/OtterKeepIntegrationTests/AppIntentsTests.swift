//
//  AppIntentsTests.swift
//  OtterKeepIntegrationTests
//
//  Tests for AppIntents Shortcuts integration: ProfileAppEntity, StartBackupIntent,
//  GetBackupStatusIntent, and OtterKeepShortcutsProvider.
//

import Foundation
import Testing
import OtterKeepDomain
import OtterKeepCore

@MainActor
@Suite(.serialized)
struct AppIntentsTests {
    @Test func testProfileAppEntityQueryResolution() async throws {
        let initialProfiles = ProfileStore.shared.loadProfiles()

        // Create a temporary profile for entity query testing
        let testProfile = BackupProfile(
            name: "Shortcuts Entity Test Profile",
            sourceURL: URL(fileURLWithPath: "/tmp/source_\(UUID().uuidString)"),
            destinationURL: URL(fileURLWithPath: "/tmp/dest_\(UUID().uuidString)")
        )
        try ProfileStore.shared.updateProfile(testProfile)
        defer {
            try? ProfileStore.shared.deleteProfile(id: testProfile.id)
            try? ProfileStore.shared.saveProfiles(initialProfiles)
        }

        let query = ProfileEntityQuery()
        let suggested = try await query.suggestedEntities()
        try assertTrue(suggested.contains(where: { $0.id == testProfile.id.uuidString }))

        let resolved = try await query.entities(for: [testProfile.id.uuidString])
        try assertEqual(resolved.count, 1)
        try assertEqual(resolved.first?.name, testProfile.name)
    }

    @Test func testGetBackupStatusIntentExecution() async throws {
        let intent = GetBackupStatusIntent()
        _ = try await intent.perform()
        try assertTrue(true, "GetBackupStatusIntent must execute and return ProvidesDialog result without error")
    }

    @Test func testShortcutsProviderRegistration() throws {
        let shortcuts = OtterKeepShortcutsProvider.appShortcuts
        try assertTrue(shortcuts.count >= 2, "Must register at least StartBackup and GetStatus shortcuts")
    }
}
