import Foundation
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

extension OtterKeepCLI {
    static func printHelp() {
        print("""
        \(L10n.t(.cliDescription))
        \(L10n.t(.cliUsage))

        \(L10n.t(.cliCommandsHeader))
          backup                    \(L10n.t(.cliCmdBackup))
            --profile <name|uuid>   \(L10n.t(.cliCmdBackupProfile))
            --dry-run               \(L10n.t(.cliCmdBackupDryRun))
            --full                  \(L10n.t(.cliCmdBackupFull))

          replicate                 Trigger 3-2-1 secondary replication (Backup Copy Job)
            --profile <name|uuid>   Specify profile to replicate
            --snapshot <id>         Specify snapshot ID (defaults to latest)

          photos                    \(L10n.t(.cliCmdPhotos))
            status                  View configuration and library status
            backup                  Trigger Photos backup
            snapshots               List completed Photos snapshots

          prune                     \(L10n.t(.cliCmdPrune))
            --profile <name|uuid>   Specify profile to prune
            --keep <number>         Keep count of latest snapshots (default: profile policy)

          daemon                    \(L10n.t(.cliCmdDaemon))
            install                 Install & enable 15-minute background LaunchAgent
            uninstall               Disable & remove background LaunchAgent
            status                  Check background LaunchAgent registration
            check                   Run single evaluation check

          doctor                    \(L10n.t(.cliCmdDoctor))

          status                    \(L10n.t(.cliCmdStatus))

          profile list              \(L10n.t(.cliCmdProfileList))
          profile create            \(L10n.t(.cliCmdProfileCreate))
            --name <name>           \(L10n.t(.cliCmdProfileName))
            --source <path>         \(L10n.t(.cliCmdProfileSource))
            --destination <path>    \(L10n.t(.cliCmdProfileDest))

          snapshots list            \(L10n.t(.cliCmdSnapshotsList))
            --profile <name|uuid>   \(L10n.t(.cliCmdBackupProfile))

          restore                   \(L10n.t(.cliCmdRestore))
            --profile <name|uuid>   \(L10n.t(.cliCmdRestoreProfile))
            --snapshot <id>         \(L10n.t(.cliCmdRestoreSnapshot))
            --file <rel_path>       \(L10n.t(.cliCmdRestoreFile))
            --target <path>         \(L10n.t(.cliCmdRestoreTarget))

          restore-snapshot          \(L10n.t(.cliCmdRestoreEntireSnapshot))
            --profile <name|uuid>   \(L10n.t(.cliCmdRestoreProfile))
            --snapshot <id>         \(L10n.t(.cliCmdRestoreSnapshot))
            --target <path>         \(L10n.t(.cliCmdRestoreTarget))
            --collision <mode>      \(L10n.t(.cliOptionCollision))

          file-history <path>       \(L10n.t(.cliCmdFileHistory))
            --gui                   \(L10n.t(.cliCmdFileHistoryGui))

          logs                      \(L10n.t(.cliCmdLogs))
            --path                  \(L10n.t(.cliCmdLogsPath))
            --list                  \(L10n.t(.cliCmdLogsList))
            --enable                \(L10n.t(.cliCmdLogsEnable))
            --disable               \(L10n.t(.cliCmdLogsDisable))
            --limit <number>        \(L10n.t(.cliCmdLogsLimit))

          schedule check            \(L10n.t(.cliCmdScheduleCheck))

          scrub                     \(L10n.t(.cliCmdScrubDesc))
            --profile <name|uuid>   Specify profile to scrub
            --limit <number>        Limit count of recent snapshots to inspect

          diff                      Compare two snapshots or side-by-side file contents
            --profile <name|uuid>   Specify profile
            --target <id>           Target snapshot ID (default: latest)
            --base <id>             Base snapshot ID (default: previous)
            --file <rel_path>       Specific file to compare
            --side-by-side          Render aligned side-by-side line comparison

          lock                      Apply WORM immutability protection to a snapshot
            --profile <name|uuid>   Specify profile
            --snapshot <id>         Specify snapshot ID
            --days <count>          Lock duration in days (default: 30)

          unlock                    Remove user immutable flag from a snapshot
            --profile <name|uuid>   Specify profile
            --snapshot <id>         Specify snapshot ID

        Options:
          --debug                   \(L10n.t(.cliOptDebug))
          --version, -v             \(L10n.t(.cliOptVersion))
          --lang <en|hu>            \(L10n.t(.cliOptLang))
          --help, -h                \(L10n.t(.cliOptHelp))

        \(L10n.t(.cliExamplesHeader))
          otterkeep backup --dry-run --debug
          otterkeep backup --profile "Default profile"
          otterkeep replicate --profile "Default profile"
          otterkeep photos backup
          otterkeep prune --keep 5
          otterkeep doctor
          otterkeep daemon status
          otterkeep snapshots list
          otterkeep logs --path
          otterkeep logs --list
          otterkeep logs --limit 10
        """)
    }

    // MARK: - Backup

    /// Handles backup operations including pre-backup dry-run simulations.
    /// - Parameter args: Command-line arguments passed to the backup subcommand.

    static func getOption(_ option: String, from args: [String]) -> String? {
        guard let idx = args.firstIndex(of: option), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    /// Formats a byte count into a human-readable file size string (e.g., "1.2 MB").
    /// - Parameter bytes: The raw byte count.
    /// - Returns: Localized and formatted byte count string.
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Resolves a backup profile specified by name or UUID, defaulting to the first profile if unspecified.
    /// Terminates the process if no profiles exist or if the specified profile is not found.
    /// - Parameter target: Optional profile name or UUID string.
    /// - Returns: The resolved `BackupProfile`.
    static func resolveProfile(target: String?) -> BackupProfile {
        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }
        guard let target else {
            return profiles[0]
        }
        guard let matched = store.findProfile(namedOrId: target) else {
            print(L10n.format(.cliProfileNotFound, target))
            exitCLI(1)
        }
        return matched
    }

}
