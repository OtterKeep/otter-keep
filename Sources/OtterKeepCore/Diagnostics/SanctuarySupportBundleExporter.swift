import Foundation
import os
import OtterKeepStorage
import OtterKeepDatabase

/// Exports a self-contained, privacy-sanitized diagnostic support bundle for troubleshooting and bug reporting.
public final class SanctuarySupportBundleExporter: Sendable {
    public static let shared = SanctuarySupportBundleExporter()
    private let logger = Logger(subsystem: "com.otterkeep", category: "SupportBundle")

    private init() {}

    /// Exports the support bundle to the specified URL or defaults to `~/Desktop/OtterKeep-Diagnostics-<timestamp>.zip`.
    /// - Parameter targetZipURL: Optional custom zip output path.
    /// - Returns: URL of the created zip archive.
    public func exportSupportBundle(to targetZipURL: URL? = nil) async throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let outputZipURL: URL
        if let targetZipURL = targetZipURL {
            outputZipURL = targetZipURL
        } else {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            outputZipURL = desktop.appendingPathComponent("OtterKeep-Diagnostics-\(timestamp).zip")
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("otterkeep_bundle_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 1. Gather System Information
        let sysInfo = await buildSystemInformation()
        let sysInfoData = try JSONSerialization.data(withJSONObject: sysInfo, options: [.prettyPrinted, .sortedKeys])
        try sysInfoData.write(to: tempDir.appendingPathComponent("system_info.json"))

        // 2. Gather Storage & Volumes Information
        let storageInfo = await buildStorageInformation()
        let storageData = try JSONSerialization.data(withJSONObject: storageInfo, options: [.prettyPrinted, .sortedKeys])
        try storageData.write(to: tempDir.appendingPathComponent("storage_info.json"))

        // 3. Copy & Sanitize Recent Logs (last 5 days)
        let logsDir = tempDir.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let logFiles = LogManager.shared.listDebugLogFiles()
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 86400)

        for fileURL in logFiles {
            let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            if modDate >= fiveDaysAgo {
                if let rawText = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let sanitized = LogPrivacySanitizer.sanitize(rawText)
                    let destURL = logsDir.appendingPathComponent(fileURL.lastPathComponent)
                    try? sanitized.write(to: destURL, atomically: true, encoding: .utf8)
                }
            }
        }

        // Also copy sanitized logs.json if present
        let logsJsonURL = LogManager.shared.logFileURL
        if FileManager.default.fileExists(atPath: logsJsonURL.path),
           let rawJson = try? String(contentsOf: logsJsonURL, encoding: .utf8) {
            let sanitized = LogPrivacySanitizer.sanitize(rawJson)
            try? sanitized.write(to: logsDir.appendingPathComponent("logs.json"), atomically: true, encoding: .utf8)
        }

        // 4. Create ZIP archive
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.currentDirectoryURL = tempDir
        zipProcess.arguments = ["-q", "-r", outputZipURL.path(percentEncoded: false), "."]

        try zipProcess.run()
        zipProcess.waitUntilExit()

        guard zipProcess.terminationStatus == 0 else {
            throw NSError(domain: "SanctuarySupportBundleExporter", code: Int(zipProcess.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Failed to compress support bundle archive (exit code \(zipProcess.terminationStatus))"
            ])
        }

        logger.info("Successfully exported sanctuary support bundle to: \(outputZipURL.path(percentEncoded: false))")
        return outputZipURL
    }

    private func buildSystemInformation() async -> [String: Any] {
        var info: [String: Any] = [:]
        let processInfo = ProcessInfo.processInfo

        info["os_version"] = processInfo.operatingSystemVersionString
        info["processor_count"] = processInfo.activeProcessorCount
        info["physical_memory_bytes"] = processInfo.physicalMemory
        info["thermal_state"] = String(describing: processInfo.thermalState)
        info["is_low_power_mode"] = processInfo.isLowPowerModeEnabled
        info["app_version"] = CoreEngine.version
        info["build_number"] = CoreEngine.buildNumber

        var unameInfo = utsname()
        if uname(&unameInfo) == 0 {
            let machine = withUnsafePointer(to: &unameInfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
            }
            info["architecture"] = machine
        }

        return info
    }

    private func buildStorageInformation() async -> [String: Any] {
        var info: [String: Any] = [:]
        let profiles = ProfileStore.shared.loadProfiles()
        var profilesSummary: [[String: Any]] = []

        let storage = DefaultFileSystemProvider()

        for p in profiles {
            var pInfo: [String: Any] = [:]
            pInfo["id"] = p.id.uuidString
            pInfo["name"] = p.name
            pInfo["source_path"] = LogPrivacySanitizer.sanitize(p.sourceURL.path(percentEncoded: false))
            pInfo["destination_path"] = LogPrivacySanitizer.sanitize(p.destinationURL.path(percentEncoded: false))
            pInfo["is_auto_prune_enabled"] = p.pruningPolicy.isAutoPruningEnabled
            pInfo["is_schedule_enabled"] = p.schedule.isEnabled

            if let cap = try? await storage.capabilities(at: p.destinationURL) {
                pInfo["destination_supports_cow"] = cap.supportsAPFSClone
                pInfo["destination_fs_type"] = cap.fsTypeName
            }
            if let volCap = try? storage.storageCapacity(at: p.destinationURL) {
                pInfo["destination_total_bytes"] = volCap.totalBytes
                pInfo["destination_available_bytes"] = volCap.availableBytes
            }
            profilesSummary.append(pInfo)
        }

        info["profiles_count"] = profiles.count
        info["profiles"] = profilesSummary
        return info
    }
}
