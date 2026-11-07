//
//  DiagnosticsLoggingTests.swift
//  OtterKeepIntegrationTests
//
//  Diagnostics & Observability: Privacy-Preserving Log Scrubbing,
//  Path Masking, Dual-Tier Diagnostics, Apple Standard ~/Library/Logs Directory.
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
struct DiagnosticsLoggingTests {
    @Test func testLogPrivacyScrubbing() throws {
        let rawLog = "Error connecting to S3 with key AKIAIOSFODNN7EXAMPLE and secret https://api.endpoint.com?token=mySecretToken12345678"
        let sanitized = LogPrivacySanitizer.sanitize(rawLog)
        try assertFalse(sanitized.contains("AKIAIOSFODNN7EXAMPLE"), "AWS keys must be scrubbed")
        try assertFalse(sanitized.contains("mySecretToken12345678"), "Token parameters must be scrubbed")
        try assertTrue(sanitized.contains("<AWS_ACCESS_KEY_ID>"))
    }

    @Test func testPathMasking() throws {
        let rawPath = "/Users/john/Documents/Personal/FinancialReport_2026.pdf"
        let sanitized = LogPrivacySanitizer.sanitizeSinglePath(rawPath)
        try assertFalse(sanitized.contains("john"), "Usernames must be scrubbed")
        try assertFalse(sanitized.contains("FinancialReport_2026"), "Personal filenames must be scrubbed")
        try assertTrue(sanitized.hasSuffix(".pdf"), "File extension must be preserved for diagnostic triage")
    }

    @Test func testDualTierDiagnostics() throws {
        let logger = LogManager.shared
        logger.log("Info message test", level: .info, category: "Test")
        logger.log("Warning message test", level: .warning, category: "Test")

        let entries = logger.getEntries()
        try assertTrue(entries.contains(where: { $0.message.contains("Info message test") }))
    }

    @Test func testDebugFileLoggerAppend() throws {
        let fileLogger = DebugFileLogger.shared
        let url = fileLogger.startSession()
        try assertTrue(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        fileLogger.appendLog(sanitizedMessage: "Diagnostic checkpoint", level: "INFO", category: "Test")
        fileLogger.stopSession()

        let content = try String(contentsOf: url, encoding: .utf8)
        try assertTrue(content.contains("Diagnostic checkpoint"))
    }

    @Test func testAppleStandardLogDirectory() throws {
        let logsDir = DebugFileLogger.shared.logsDirectory
        try assertTrue(logsDir.path.contains("Library/Logs/OtterKeep"), "Logs directory must adhere to Apple native ~/Library/Logs/OtterKeep standard")

        let managerLogDir = LogManager.shared.logDirectory
        try assertEqual(managerLogDir.path, logsDir.path, "LogManager logDirectory must match DebugFileLogger logsDirectory")
        try assertTrue(LogManager.shared.logFileURL.path.hasSuffix("Library/Logs/OtterKeep/logs.json"))
    }
}
