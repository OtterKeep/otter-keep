//
//  SystemVersionIntegrityTests.swift
//  OtterKeepIntegrationTests
//
//  System, Version & Subsystem SemVer Integrity Suite
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
struct SystemVersionIntegrityTests {
    @Test func test_CoreEngineMetadata() throws {
        let manifest = try VersionManifest.load()
        try assertEqual(CoreEngine.appName, "OtterKeep")
        try assertEqual(CoreEngine.bundleIdentifier, "com.otterkeep.desktop")
        try assertEqual(CoreEngine.version, manifest.version, "CoreEngine version must match version.json")
        try assertEqual(CoreEngine.buildNumber, manifest.build, "Build number must match version.json")
    }

    @Test func test_SemVerSubsystemMatrix() throws {
        let manifest = try VersionManifest.load()
        try assertEqual(
            CoreEngine.componentVersions,
            manifest.subsystems,
            "The subsystem SemVer matrix must match version.json"
        )

        let summary = CoreEngine.componentVersionsFormatted
        for component in ["OtterKeepStorage", "OtterKeepDatabase", "OtterKeepCore", "OtterKeepUI", "OtterKeepCLI"] {
            let version = try require(manifest.subsystems[component], "version.json must declare \(component)")
            try assertTrue(summary.contains("v\(version)"), "Summary must reflect \(component) v\(version)")
        }
    }

    @Test func test_SemVerComparison() throws {
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("2.3.4", "2.3.4"), .orderedSame)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("2.3.4", "2.3.5"), .orderedAscending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("2.3.5", "2.3.4"), .orderedDescending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("v2.3.4", "2.3.4"), .orderedSame)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("2.10.0", "2.3.4"), .orderedDescending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("2.3.10", "2.3.9"), .orderedDescending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("3.0.0", "2.99.99"), .orderedDescending)
    }

    @Test func test_SparkleAppcast() async throws {
        let manifest = try VersionManifest.load()
        let coordinator = SoftwareUpdateCoordinator()
        try assertEqual(coordinator.currentVersion, manifest.version)
        try assertEqual(coordinator.currentBuild, manifest.build)

        let appcastURL = VersionManifest.repositoryRoot(from: #file)
            .appendingPathComponent("Distribution/appcast.xml")
        let data = try Data(contentsOf: appcastURL)

        let latest = try require(
            await coordinator.parseAppcastXML(data: data),
            "Expected parsed update info in appcast"
        )
        try assertEqual(latest.version, manifest.version, "Newest appcast item must match version.json")
        try assertEqual(latest.buildNumber, manifest.build, "Newest appcast build must match version.json")
        try assertTrue(latest.downloadURL.absoluteString.contains("OtterKeep-\(manifest.version).zip"))
    }
}
