import Foundation
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension OtterKeepCLI {
    static func handleLogs(_ args: [String]) {
        if args.contains("--enable") {
            let url = LogManager.shared.enableDebugFileLogging(persistSetting: true)
            print(L10n.t(.cliDebugLoggingEnabled))
            print(L10n.format(.cliLogsPathLabel, url.path(percentEncoded: false)))
            exitCLI(0)
        }

        if args.contains("--disable") {
            LogManager.shared.disableDebugFileLogging(persistSetting: true)
            print(L10n.t(.cliDebugLoggingDisabled))
            exitCLI(0)
        }

        if args.contains("--path") || args.contains("--file") {
            if let activeURL = LogManager.shared.currentDebugLogFileURL {
                print(L10n.format(.cliLogsPathLabel, activeURL.path(percentEncoded: false)))
            } else if let latestURL = LogManager.shared.listDebugLogFiles().first {
                print(L10n.format(.cliLogsPathLabel, latestURL.path(percentEncoded: false)))
            } else {
                print(L10n.t(.cliNoLogsFound))
            }
            exitCLI(0)
        }

        if args.contains("--list") {
            let files = LogManager.shared.listDebugLogFiles()
            if files.isEmpty {
                print(L10n.t(.cliNoLogsFound))
            } else {
                print("\(L10n.t(.logsTitle)) (\(files.count)):")
                let df = ISO8601DateFormatter()
                for (idx, f) in files.enumerated() {
                    let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    let isCurrent = (f == LogManager.shared.currentDebugLogFileURL) ? " [ACTIVE]" : ""
                    print("  [\(idx + 1)] \(f.lastPathComponent)\(isCurrent)  (\(formatBytes(Int64(size))))  \(df.string(from: date))")
                }
            }
            exitCLI(0)
        }

        let limitStr = getOption("--limit", from: args) ?? getOption("--tail", from: args) ?? "25"
        let limit = Int(limitStr) ?? 25

        let entries = LogManager.shared.getEntries()
        let toShow = entries.suffix(limit)

        print("\(L10n.t(.logsTitle)) (\(toShow.count)):")
        let df = ISO8601DateFormatter()
        for e in toShow {
            print("[\(df.string(from: e.timestamp))] [\(e.level.rawValue)] [\(e.category)]: \(e.message)")
        }
        exitCLI(0)
    }

    // MARK: - Schedule Check

    /// Evaluates scheduled backup profiles and triggers missed or due catch-up backups.
    /// - Parameter args: Command-line arguments passed to the schedule subcommand.

    static func handleDaemon(_ args: [String]) {
        let sub = args.first ?? "status"
        let manager = DaemonServiceManager.shared

        switch sub {
        case "status":
            print("⚙️ OtterKeep LaunchAgent Status\n")
            print("   • Installed:  \(manager.isDaemonEnabled)")
            print("   • Label:      \(DaemonServiceManager.agentLabel)")
            print("   • Interval:   900 seconds (15 minutes)")
            print("   • Schedule:   Periodic Catch-Up & Auto-Backup")
            let plistPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(DaemonServiceManager.agentLabel).plist").path
            print("   • Plist Path: \(plistPath)")
            exitCLI(0)

        case "install", "enable":
            do {
                try manager.registerDaemon()
                print("✅ Successfully installed and activated OtterKeep background LaunchAgent.")
                print("   The agent will run 'otterkeep schedule check' periodically every 15 minutes.")
                exitCLI(0)
            } catch {
                print("❌ Failed to install LaunchAgent: \(error.localizedDescription)")
                exitCLI(1)
            }

        case "uninstall", "disable":
            manager.unregisterDaemon()
            print("✅ Successfully unloaded and removed OtterKeep background LaunchAgent.")
            exitCLI(0)

        case "check":
            Task {
                await handleSchedule(["check"])
            }

        default:
            print(L10n.format(.cliUnknownSubcommand, sub))
            exitCLI(1)
        }
    }

    // MARK: - Doctor / Diagnostic Audit

    /// Performs a comprehensive system diagnostic audit checking permissions, disk space, and capabilities.

}
