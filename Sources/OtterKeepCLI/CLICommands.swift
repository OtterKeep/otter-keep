import Foundation
import Darwin
import ArgumentParser
import OtterKeepDomain
import OtterKeepApplication
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

// MARK: - Root Command

/// Main entrypoint for the OtterKeep command-line interface.
@main
struct OtterKeepCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "otterkeep",
        abstract: "The Serene Guardian for Your macOS Digital Sanctuary",
        version: "OtterKeep v\(CoreEngine.version) (Build \(CoreEngine.buildNumber))",
        subcommands: [
            BackupCommand.self,
            RestoreCommand.self,
            RestoreSnapshotCommand.self,
            ProfileCommand.self,
            ScheduleCommand.self,
            DiagnosticsCommand.self,
            StatusCommand.self,
            ReplicateCommand.self,
            PhotosCommand.self,
            PruneCommand.self,
            DaemonCommand.self,
            DoctorCommand.self,
            SnapshotsCommand.self,
            FileHistoryCommand.self,
            LogsCommand.self,
            ScrubCommand.self,
            DiffCommand.self,
            LockCommand.self,
            UnlockCommand.self
        ]
    )

    @Option(name: .long, help: "Application language: en or hu")
    var lang: String?

    @Flag(name: .long, help: "Enable verbose debug file logging to ~/Library/Logs/OtterKeep/")
    var debug: Bool = false

    mutating func validate() throws {
        if let lang = lang?.lowercased() {
            if lang == "hu" || lang == "magyar" {
                LocalizationManager.shared.currentLanguage = .hungarian
            } else if lang == "en" || lang == "english" {
                LocalizationManager.shared.currentLanguage = .english
            }
        }
        if debug {
            let logURL = LogManager.shared.enableDebugFileLogging(persistSetting: false)
            print(L10n.format(.cliDebugActiveNotice, logURL.path(percentEncoded: false)))
            print()
        }
    }

    /// Terminates the CLI process, flushing and printing debug log notice if debug logging was active.
    static func exitCLI(_ code: Int32) -> Never {
        if let url = LogManager.shared.currentDebugLogFileURL {
            LogManager.shared.flush()
            print("\n" + L10n.format(.cliDebugSavedNotice, url.path(percentEncoded: false)))
        }
        Darwin.exit(code)
    }
}

// MARK: - Backup Command

struct BackupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "Execute a backup session or pre-backup simulation."
    )

    @Argument(help: "Target backup profile name or UUID (optional, defaults to first profile)")
    var profileName: String?

    @Option(name: .long, help: "Target backup profile name or UUID")
    var profile: String?

    @Flag(name: .long, help: "Perform non-destructive dry-run analysis")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Force full baseline backup without CoW cloning")
    var full: Bool = false

    @Flag(name: .long, help: "Run in continuous event-driven mode (FSEvents)")
    var continuous: Bool = false

    func run() async throws {
        var args: [String] = []
        if dryRun { args.append("--dry-run") }
        if full { args.append("--full") }
        if continuous { args.append("--continuous") }
        let target = profile ?? profileName
        if let target = target {
            args.append("--profile")
            args.append(target)
        }
        await OtterKeepCLI.handleBackup(args)
    }
}

// MARK: - Restore Command

struct RestoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Restore individual files or folders from a historical snapshot."
    )

    @Argument(help: "Target backup profile name or UUID (optional)")
    var profileName: String?

    @Option(name: .long, help: "Target backup profile name or UUID")
    var profile: String?

    @Option(name: .long, help: "Snapshot identifier to restore from")
    var snapshot: String

    @Option(name: .long, help: "Relative path of file inside snapshot root")
    var file: String?

    @Option(name: .long, help: "Destination path where item will be restored")
    var target: String

    @Option(name: .long, help: "Collision resolution strategy (keepBoth, overwrite, skip)")
    var collision: String?

    func run() async throws {
        var args: [String] = [
            "--snapshot", snapshot,
            "--target", target
        ]
        let p = profile ?? profileName
        if let p = p {
            args.append(contentsOf: ["--profile", p])
        }
        if let file = file {
            args.append(contentsOf: ["--file", file])
        }
        if let col = collision {
            args.append(contentsOf: ["--collision", col])
        }
        await OtterKeepCLI.handleRestore(args)
    }
}

// MARK: - Restore Snapshot Command

struct RestoreSnapshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore-snapshot",
        abstract: "Restore an entire snapshot hierarchy atomically."
    )

    @Argument(help: "Target backup profile name or UUID (optional)")
    var profileName: String?

    @Option(name: .long, help: "Target backup profile name or UUID")
    var profile: String?

    @Option(name: .long, help: "Snapshot identifier to restore")
    var snapshot: String

    @Option(name: .long, help: "Target destination directory")
    var target: String

    @Option(name: .long, help: "Collision resolution strategy (overwrite, keepBoth, skip)")
    var collision: String?

    func run() async throws {
        var args: [String] = [
            "--snapshot", snapshot,
            "--target", target
        ]
        let p = profile ?? profileName
        if let p = p {
            args.append(contentsOf: ["--profile", p])
        }
        if let col = collision {
            args.append(contentsOf: ["--collision", col])
        }
        await OtterKeepCLI.handleRestoreSnapshot(args)
    }
}

// MARK: - Profile Command

struct ProfileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profile",
        abstract: "Manage backup profiles (list, show, create, delete).",
        subcommands: [
            ListProfiles.self,
            ShowProfile.self,
            CreateProfile.self,
            DeleteProfile.self
        ],
        defaultSubcommand: ListProfiles.self
    )

    struct ListProfiles: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List all configured profiles.")
        func run() async throws {
            await OtterKeepCLI.handleProfile(["list"])
        }
    }

    struct ShowProfile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show detailed profile configuration.")
        @Argument(help: "Profile name or UUID")
        var name: String

        func run() async throws {
            let store = ProfileStore.shared
            guard let p = store.findProfile(namedOrId: name) else {
                print(L10n.format(.cliProfileNotFound, name))
                OtterKeepCLI.exitCLI(1)
            }
            print("📁 Profile: \(p.name) (UUID: \(p.id.uuidString))")
            print("   Source:      \(p.sourceURL.path)")
            print("   Destination: \(p.destinationURL.path)")
            print("   Excludes:    \(p.excludePatterns.joined(separator: ", "))")
            let sched = p.schedule.isEnabled ? "\(p.schedule.frequency.rawValue)" : "Disabled"
            print("   Schedule:    \(sched)")
        }
    }

    struct CreateProfile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new backup profile.",
            aliases: ["add"]
        )

        @Option(name: .long, help: "Profile name")
        var name: String

        @Option(name: .long, help: "Source folder path")
        var source: String

        @Option(name: .long, help: "Destination folder path")
        var destination: String

        func run() async throws {
            let args = ["create", "--name", name, "--source", source, "--destination", destination]
            await OtterKeepCLI.handleProfile(args)
        }
    }

    struct DeleteProfile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete an existing backup profile.",
            aliases: ["remove"]
        )

        @Argument(help: "Profile name or UUID to delete")
        var name: String

        func run() async throws {
            let args = ["delete", "--name", name]
            await OtterKeepCLI.handleProfile(args)
        }
    }
}

// MARK: - Schedule Command

struct ScheduleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Evaluate schedules and trigger due backups.",
        subcommands: [CheckSchedule.self, RunSchedule.self],
        defaultSubcommand: CheckSchedule.self
    )

    struct CheckSchedule: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "check", abstract: "Check for overdue scheduled backups.")
        func run() async throws {
            await OtterKeepCLI.handleSchedule(["check"])
        }
    }

    struct RunSchedule: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "run", abstract: "Run scheduled backup checks immediately.")
        func run() async throws {
            await OtterKeepCLI.handleSchedule(["run"])
        }
    }
}

// MARK: - Diagnostics Command

struct DiagnosticsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnostics",
        abstract: "Generate system diagnostic reports and bundles.",
        subcommands: [BundleDiagnostics.self],
        defaultSubcommand: BundleDiagnostics.self
    )

    struct BundleDiagnostics: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "bundle", abstract: "Export sanitized diagnostic support bundle.")
        @Option(name: .long, help: "Target output path for zip archive")
        var output: String?

        func run() async throws {
            print("📦 Gathering OtterKeep sanctuary diagnostic telemetry...")
            let targetURL = output.map { URL(fileURLWithPath: $0) }
            do {
                let zipURL = try await SanctuarySupportBundleExporter.shared.exportSupportBundle(to: targetURL)
                print("✅ Diagnostic bundle created successfully at:")
                print("   \(zipURL.path(percentEncoded: false))")
            } catch {
                print("❌ Failed to create diagnostic bundle: \(error.localizedDescription)")
                OtterKeepCLI.exitCLI(1)
            }
        }
    }
}

// MARK: - Status Command

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Display status of all backup profiles.")
    func run() async throws {
        await OtterKeepCLI.handleStatus()
    }
}

// MARK: - Replicate Command

struct ReplicateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "replicate",
        abstract: "Trigger 3-2-1 secondary replication (Backup Copy Job).",
        aliases: ["copy-job", "sync"]
    )

    @Option(name: .long, help: "Target profile name or UUID")
    var profile: String?

    @Option(name: .long, help: "Target snapshot ID to replicate (defaults to latest)")
    var snapshot: String?

    func run() async throws {
        var args: [String] = []
        if let p = profile { args.append(contentsOf: ["--profile", p]) }
        if let s = snapshot { args.append(contentsOf: ["--snapshot", s]) }
        await OtterKeepCLI.handleReplicate(args)
    }
}

// MARK: - Photos Command

struct PhotosCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "photos", abstract: "Manage Apple Photos sanctuary backups.")

    @Argument(help: "Action: status, backup, snapshots")
    var action: String = "status"

    func run() async throws {
        await OtterKeepCLI.handlePhotos([action])
    }
}

// MARK: - Prune Command

struct PruneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "prune", abstract: "Prune obsolete historical snapshots.")

    @Option(name: .long, help: "Target profile name or UUID")
    var profile: String?

    @Option(name: .long, help: "Number of newest snapshots to retain")
    var keep: Int?

    func run() async throws {
        var args: [String] = []
        if let p = profile { args.append(contentsOf: ["--profile", p]) }
        if let k = keep { args.append(contentsOf: ["--keep", String(k)]) }
        await OtterKeepCLI.handlePrune(args)
    }
}

// MARK: - Daemon Command

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "daemon", abstract: "Manage headless background daemon.")

    @Argument(help: "Action: install, uninstall, status, check")
    var action: String = "status"

    func run() async throws {
        OtterKeepCLI.handleDaemon([action])
    }
}

// MARK: - Doctor Command

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Run system diagnostics and check permissions.")
    func run() async throws {
        await OtterKeepCLI.handleDoctor()
    }
}

// MARK: - Snapshots Command

struct SnapshotsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshots",
        abstract: "List recorded snapshots in the catalog.",
        aliases: ["snapshot"]
    )

    @Argument(help: "Action (default: list)")
    var action: String = "list"

    @Option(name: .long, help: "Target profile name or UUID")
    var profile: String?

    func run() async throws {
        var args = [action]
        if let p = profile { args.append(contentsOf: ["--profile", p]) }
        await OtterKeepCLI.handleSnapshots(args)
    }
}

// MARK: - File History Command

struct FileHistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-history",
        abstract: "Inspect historical versions of a file across snapshots.",
        aliases: ["history"]
    )

    @Argument(help: "Filesystem path to the file")
    var path: String

    @Flag(name: .long, help: "Open version history in macOS graphical interface")
    var gui: Bool = false

    func run() async throws {
        var args = [path]
        if gui { args.append("--gui") }
        await OtterKeepCLI.handleFileHistory(args)
    }
}

// MARK: - Logs Command

struct LogsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "logs", abstract: "Inspect unified diagnostic logs.", aliases: ["log"])

    @Flag(name: .long, help: "Print active log file path")
    var path: Bool = false

    @Flag(name: .long, help: "List all recorded log files")
    var list: Bool = false

    @Flag(name: .long, help: "Enable debug file logging")
    var enable: Bool = false

    @Flag(name: .long, help: "Disable debug file logging")
    var disable: Bool = false

    @Option(name: .long, help: "Number of log lines to show")
    var limit: Int?

    func run() async throws {
        var args: [String] = []
        if path { args.append("--path") }
        if list { args.append("--list") }
        if enable { args.append("--enable") }
        if disable { args.append("--disable") }
        if let limit = limit { args.append(contentsOf: ["--limit", String(limit)]) }
        OtterKeepCLI.handleLogs(args)
    }
}

// MARK: - Scrub Command

struct ScrubCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "scrub", abstract: "Run cryptographic SHA-256 data scrubbing pass.")

    @Option(name: .long, help: "Target profile name or UUID")
    var profile: String?

    @Option(name: .long, help: "Limit count of recent snapshots to scrub")
    var limit: Int?

    func run() async throws {
        var args: [String] = []
        if let p = profile { args.append(contentsOf: ["--profile", p]) }
        if let l = limit { args.append(contentsOf: ["--limit", String(l)]) }
        await OtterKeepCLI.handleScrub(args)
    }
}

// MARK: - Diff Command

struct DiffCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "diff", abstract: "Compare snapshots or file contents.")

    @Option(name: .long, help: "Target profile name or UUID")
    var profile: String?

    @Option(name: .long, help: "Target snapshot ID (default: latest)")
    var target: String?

    @Option(name: .long, help: "Base snapshot ID (default: previous)")
    var base: String?

    @Option(name: .long, help: "Relative path of file to compare")
    var file: String?

    @Flag(name: .long, help: "Render aligned side-by-side Myers LCS line comparison")
    var sideBySide: Bool = false

    func run() async throws {
        var args: [String] = []
        if let p = profile { args.append(contentsOf: ["--profile", p]) }
        if let t = target { args.append(contentsOf: ["--target", t]) }
        if let b = base { args.append(contentsOf: ["--base", b]) }
        if let f = file { args.append(contentsOf: ["--file", f]) }
        if sideBySide { args.append("--side-by-side") }
        await OtterKeepCLI.handleDiff(args)
    }
}

// MARK: - Lock Command

struct LockCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "lock", abstract: "Apply WORM immutability protection to a snapshot.")

    @Option(name: .long, help: "Snapshot identifier to lock")
    var snapshot: String

    @Option(name: .long, help: "Target profile name or UUID")
    var profile: String?

    @Option(name: .long, help: "Lock retention period in days (default: 30)")
    var days: Int = 30

    func run() async throws {
        var args: [String] = ["--snapshot", snapshot, "--days", String(days)]
        if let p = profile { args.append(contentsOf: ["--profile", p]) }
        await OtterKeepCLI.handleLock(args)
    }
}

// MARK: - Unlock Command

struct UnlockCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unlock", abstract: "Remove user immutable flag from a snapshot.")

    @Option(name: .long, help: "Snapshot identifier to unlock")
    var snapshot: String

    @Option(name: .long, help: "Target profile name or UUID")
    var profile: String?

    func run() async throws {
        var args: [String] = ["--snapshot", snapshot]
        if let p = profile { args.append(contentsOf: ["--profile", p]) }
        await OtterKeepCLI.handleUnlock(args)
    }
}
