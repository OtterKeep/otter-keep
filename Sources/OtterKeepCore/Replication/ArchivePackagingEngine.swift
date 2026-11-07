import Foundation
import os

/// Supported compression container formats for remote snapshot packaging.
public enum ArchivePackagingFormat: String, Sendable, Codable, CaseIterable {
    /// High-performance Facebook Zstandard compression (.tar.zst).
    case tarZst = "tar.zst"
    /// Universal standard Gzip compression (.tar.gz).
    case tarGz = "tar.gz"

    public var fileExtension: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .tarZst: return "Tar.Zstandard (.tar.zst)"
        case .tarGz: return "Tar.Gzip (.tar.gz)"
        }
    }
}

/// Errors occurring during archive packaging or extraction.
public enum ArchivePackagingError: Error, Sendable, LocalizedError, Equatable {
    case sourceDirectoryNotFound(String)
    case commandFailed(exitCode: Int32, message: String)
    case extractionFailed(String)
    case invalidArchive(String)

    public var errorDescription: String? {
        switch self {
        case .sourceDirectoryNotFound(let path):
            return "Archive source directory does not exist: \(path)"
        case .commandFailed(let exitCode, let message):
            return "Archive creation command exited with code \(exitCode): \(message)"
        case .extractionFailed(let message):
            return "Archive extraction failed: \(message)"
        case .invalidArchive(let path):
            return "Archive file is corrupt or invalid: \(path)"
        }
    }
}

/// Engine managing atomic tar archiving with Zstandard (.tar.zst) and Gzip (.tar.gz) compression for S3 replication.
public struct ArchivePackagingEngine: Sendable {
    public static let shared = ArchivePackagingEngine()
    private let logger = Logger(subsystem: "com.otterkeep", category: "ArchivePackaging")

    public init() {}

    /// Checks if Zstandard (`--zstd`) compression is supported by the system's bsdtar or zstd utility.
    public var isZstdSupported: Bool {
        // Check if /opt/homebrew/bin/zstd or /usr/local/bin/zstd or /usr/bin/zstd exists
        let fm = FileManager.default
        if fm.fileExists(atPath: "/opt/homebrew/bin/zstd") ||
           fm.fileExists(atPath: "/usr/local/bin/zstd") ||
           fm.fileExists(atPath: "/usr/bin/zstd") {
            return true
        }

        // Test running tar with --zstd --version or dry-run
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["--help"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.contains("zstd")
    }

    /// Determines the best available archive packaging format.
    public var defaultFormat: ArchivePackagingFormat {
        isZstdSupported ? .tarZst : .tarGz
    }

    /// Packages the contents of `sourceDirectory` into a compressed archive.
    /// - Parameters:
    ///   - sourceDirectory: The folder whose contents are archived.
    ///   - destinationArchiveURL: Target output file URL.
    ///   - compressionLevel: Desired compression level (1 = fastest, 3 = balanced, 9 = ultra).
    ///   - format: Optional preferred packaging format.
    /// - Returns: URL of the generated archive.
    @discardableResult
    public func createArchive(
        sourceDirectory: URL,
        destinationArchiveURL: URL,
        compressionLevel: Int = 3,
        format: ArchivePackagingFormat? = nil
    ) async throws -> URL {
        let srcPath = sourceDirectory.standardizedFileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: srcPath) else {
            throw ArchivePackagingError.sourceDirectoryNotFound(srcPath)
        }

        let parentDir = destinationArchiveURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let selectedFormat = format ?? (destinationArchiveURL.path.hasSuffix(".zst") ? .tarZst : (destinationArchiveURL.path.hasSuffix(".gz") ? .tarGz : defaultFormat))
        let destPath = destinationArchiveURL.standardizedFileURL.path(percentEncoded: false)

        try? FileManager.default.removeItem(atPath: destPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")

        var arguments: [String] = []
        if selectedFormat == .tarZst {
            arguments = ["--zstd", "-cf", destPath, "-C", srcPath, "."]
        } else {
            arguments = ["-czf", destPath, "-C", srcPath, "."]
        }
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                // If --zstd failed, attempt fallback to gzip
                if selectedFormat == .tarZst {
                    logger.warning("tar --zstd failed with code \(process.terminationStatus). Falling back to gzip (.tar.gz)...")
                    let fallbackURL = destinationArchiveURL.pathExtension == "zst"
                        ? destinationArchiveURL.deletingPathExtension().appendingPathExtension("gz")
                        : destinationArchiveURL
                    let fallbackPath = fallbackURL.standardizedFileURL.path(percentEncoded: false)
                    try? FileManager.default.removeItem(atPath: fallbackPath)

                    let fallbackProcess = Process()
                    fallbackProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    fallbackProcess.arguments = ["-czf", fallbackPath, "-C", srcPath, "."]
                    let fallbackPipe = Pipe()
                    fallbackProcess.standardError = fallbackPipe
                    try fallbackProcess.run()
                    fallbackProcess.waitUntilExit()
                    if fallbackProcess.terminationStatus == 0 {
                        if fallbackURL != destinationArchiveURL {
                            try? FileManager.default.removeItem(at: destinationArchiveURL)
                        }
                        return fallbackURL
                    }
                }

                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errString = String(data: errData, encoding: .utf8) ?? ""
                throw ArchivePackagingError.commandFailed(exitCode: process.terminationStatus, message: errString)
            }
        } catch let err as ArchivePackagingError {
            throw err
        } catch {
            throw ArchivePackagingError.commandFailed(exitCode: -1, message: error.localizedDescription)
        }

        return destinationArchiveURL
    }

    /// Extracts an archive file into the specified destination folder.
    public func extractArchive(
        archiveURL: URL,
        destinationDirectory: URL
    ) async throws {
        let archivePath = archiveURL.standardizedFileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: archivePath) else {
            throw ArchivePackagingError.invalidArchive("Archive file does not exist at: \(archivePath)")
        }

        let destPath = destinationDirectory.standardizedFileURL.path(percentEncoded: false)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archivePath, "-C", destPath]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errString = String(data: errData, encoding: .utf8) ?? ""
                throw ArchivePackagingError.extractionFailed(errString)
            }
        } catch let err as ArchivePackagingError {
            throw err
        } catch {
            throw ArchivePackagingError.extractionFailed(error.localizedDescription)
        }
    }

    /// Verifies the archive integrity by inspecting its table of contents (`tar -tf`).
    public func testArchive(archiveURL: URL) async throws -> Bool {
        let archivePath = archiveURL.standardizedFileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: archivePath) else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tf", archivePath]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
