import Foundation
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

/// Command-line interface entry point for OtterKeep.
///
/// Provides headless backup execution, pre-backup dry-run simulation, profile management,
/// snapshot inspection, point-in-time file restoration, and log inspection.
@main
struct OtterKeepCLI {

    /// Terminates the CLI process, flushing and printing the debug log notice if debug logging was active.
    static func exitCLI(_ code: Int32) -> Never {
        if let url = LogManager.shared.currentDebugLogFileURL {
            LogManager.shared.flush()
            print("\n" + L10n.format(.cliDebugSavedNotice, url.path(percentEncoded: false)))
        }
        exit(code)
    }

    /// Main entrypoint parsing arguments and dispatching subcommands.
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())

        // 1. Handle optional --lang flag
        if let langIdx = args.firstIndex(of: "--lang"), langIdx + 1 < args.count {
            let langCode = args[langIdx + 1].lowercased()
            if langCode == "hu" || langCode == "magyar" {
                LocalizationManager.shared.currentLanguage = .hungarian
            } else if langCode == "en" || langCode == "english" {
                LocalizationManager.shared.currentLanguage = .english
            }
            args.removeSubrange(langIdx...langIdx + 1)
        }

        // 2. Handle optional --debug flag
        if let debugIdx = args.firstIndex(of: "--debug") {
            args.remove(at: debugIdx)
            let logURL = LogManager.shared.enableDebugFileLogging(persistSetting: false)
            print(L10n.format(.cliDebugActiveNotice, logURL.path(percentEncoded: false)))
            print()
        }

        // 3. Handle version query
        if args.contains("--version") || args.contains("-v") || args.first == "version" {
            print("🦦 OtterKeep v\(CoreEngine.version) (Build \(CoreEngine.buildNumber))")
            print("   ├── OtterKeepStorage:  v\(CoreEngine.storageVersion)")
            print("   ├── OtterKeepDatabase: v\(CoreEngine.databaseVersion)")
            print("   ├── OtterKeepCore:     v\(CoreEngine.coreVersion)")
            print("   ├── OtterKeepUI:       v\(CoreEngine.uiVersion)")
            print("   └── OtterKeepCLI:      v\(CoreEngine.cliVersion)")
            exitCLI(0)
        }


        // 4. Handle help request
        if args.isEmpty || args.contains("--help") || args.contains("-h") || args.first == "help" {
            printHelp()
            exitCLI(0)
        }

        let command = args[0]
        let subArgs = Array(args.dropFirst())

        switch command {
        case "backup":
            await handleBackup(subArgs)
        case "status":
            await handleStatus()
        case "replicate", "copy-job", "sync":
            await handleReplicate(subArgs)
        case "photos":
            await handlePhotos(subArgs)
        case "prune":
            await handlePrune(subArgs)
        case "daemon":
            handleDaemon(subArgs)
        case "doctor":
            await handleDoctor()
        case "profile", "profiles":
            await handleProfile(subArgs)
        case "snapshots", "snapshot":
            await handleSnapshots(subArgs)
        case "restore":
            await handleRestore(subArgs)
        case "restore-snapshot":
            await handleRestoreSnapshot(subArgs)
        case "file-history", "history":
            await handleFileHistory(subArgs)
        case "logs", "log":
            handleLogs(subArgs)
        case "schedule":
            await handleSchedule(subArgs)
        case "scrub":
            await handleScrub(subArgs)
        case "diff":
            await handleDiff(subArgs)
        case "lock":
            await handleLock(subArgs)
        case "unlock":
            await handleUnlock(subArgs)
        default:
            print(L10n.format(.cliUnknownCommand, command))
            exitCLI(1)
        }
    }

}
