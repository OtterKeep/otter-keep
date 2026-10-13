//
//  VersionManifest.swift
//  OtterKeepIntegrationTests
//
//  Reads the repository's single version source (`version.json`) so tests assert
//  consistency instead of duplicating version literals.
//

import Foundation

struct VersionManifest: Sendable {
    let version: String
    let build: String
    let subsystems: [String: String]

    /// Repository root, discovered by walking up from the test file (or the working directory)
    /// until the directory containing `Package.swift` is found.
    ///
    /// The compiler may hand `#file` to the test target as a path relative to the package root, so
    /// a fixed number of `deletingLastPathComponent()` calls is not reliable.
    static func repositoryRoot(from testFile: String = #file) -> URL {
        let fileManager = FileManager.default
        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let candidates = [
            URL(fileURLWithPath: testFile),
            workingDirectory.appendingPathComponent(testFile),
            workingDirectory,
        ]

        for candidate in candidates {
            var directory = candidate.hasDirectoryPath ? candidate : candidate.deletingLastPathComponent()
            while directory.pathComponents.count > 1 {
                if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                    return directory
                }
                directory.deleteLastPathComponent()
            }
        }

        return workingDirectory
    }

    static func load(from testFile: String = #file) throws -> VersionManifest {
        let root = repositoryRoot(from: testFile)
        let manifestURL = root.appendingPathComponent("version.json")

        guard let data = try? Data(contentsOf: manifestURL) else {
            throw TestFailure(
                message: "version.json could not be read at '\(manifestURL.path(percentEncoded: false))'",
                file: testFile,
                line: #line
            )
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["version"] as? String,
            let build = json["build"] as? String,
            let subsystems = json["subsystems"] as? [String: String]
        else {
            throw TestFailure(message: "version.json is malformed", file: testFile, line: #line)
        }

        return VersionManifest(version: version, build: build, subsystems: subsystems)
    }
}
