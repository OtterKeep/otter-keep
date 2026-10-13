//
//  TemporaryDirectoryFixtures.swift
//  OtterKeepIntegrationTests
//
//  Deterministic temporary-directory fixtures shared by every integration module.
//

import Foundation

func createTempDirectory(prefix: String = "OtterKeepTest") throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir
}

func removeTempDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
