import Foundation
import ServiceManagement
import os

/// Manager controlling the background daemon lifecycle via modern macOS SMAppService and legacy LaunchAgent fallbacks.
public final class DaemonServiceManager: @unchecked Sendable {
    public static let shared = DaemonServiceManager()
    private let logger = Logger(subsystem: "com.otterkeep", category: "DaemonService")

    public static let agentLabel = "com.otterkeep.daemon"
    public static let plistName = "com.otterkeep.daemon.plist"

    private var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(Self.plistName)")
    }

    private init() {}

    /// ServiceManagement SMAppService agent handle for macOS 13.0+ / 15.0+ Sequoia.
    public var appService: SMAppService {
        SMAppService.agent(plistName: Self.plistName)
    }

    /// Status of the background service under SMAppService.
    public var serviceStatus: SMAppService.Status {
        appService.status
    }

    /// Checks whether the background daemon agent is active or enabled.
    public var isDaemonEnabled: Bool {
        let status = appService.status
        if status == .enabled {
            return true
        }
        // Fallback for standalone / CLI usage outside an app bundle
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    /// Registers the background daemon using modern SMAppService with fallback to launchctl.
    public func registerDaemon(cliBinaryPath: String? = nil) throws {
        // Attempt modern SMAppService registration first if running inside an application bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            do {
                try appService.register()
                logger.info("SMAppService successfully registered background daemon: \(Self.plistName)")
                return
            } catch {
                logger.warning("SMAppService registration failed (\(error.localizedDescription)), falling back to LaunchAgent installation")
            }
        }

        // Standalone CLI or non-bundled fallback: install into ~/Library/LaunchAgents/
        let binaryPath = cliBinaryPath ?? resolveDefaultCLIPath()
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.agentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryPath)</string>
                <string>schedule</string>
                <string>check</string>
            </array>
            <key>StartInterval</key>
            <integer>900</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Logs/OtterKeep/daemon.log</string>
            <key>StandardErrorPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Logs/OtterKeep/daemon_err.log</string>
        </dict>
        </plist>
        """

        let parentDir = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/OtterKeep")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        try plistContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
        logger.info("Installed background LaunchAgent plist at: \(self.launchAgentURL.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w", launchAgentURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    /// Unregisters and removes the background daemon.
    public func unregisterDaemon() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            try? appService.unregister()
            logger.info("SMAppService unregistered background daemon.")
        }

        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", "-w", launchAgentURL.path]
            try? process.run()
            process.waitUntilExit()

            try? FileManager.default.removeItem(at: launchAgentURL)
            logger.info("Removed LaunchAgent plist at \(self.launchAgentURL.path)")
        }
    }

    /// Opens System Settings Login Items & Extensions panel when approval is required.
    public func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func resolveDefaultCLIPath() -> String {
        let localBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/otterkeep").path
        if FileManager.default.fileExists(atPath: localBin) { return localBin }

        let usrLocal = "/usr/local/bin/otterkeep"
        if FileManager.default.fileExists(atPath: usrLocal) { return usrLocal }

        let appBundleCLI = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/otterkeep").path
        if FileManager.default.fileExists(atPath: appBundleCLI) { return appBundleCLI }

        return "/usr/local/bin/otterkeep"
    }
}
