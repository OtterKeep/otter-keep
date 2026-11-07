# CLI Reference Manual (v2.0.0)

`otterkeep` provides full headless and scripted control over OtterKeep backup profiles, snapshot catalogs, restore workflows, daemon services, and diagnostics. Powered by `apple/swift-argument-parser` under strict Swift 6 concurrency.

---

## 1. Global Usage & Flags

```bash
otterkeep [--lang <lang>] [--debug] [--version] [-h, --help] <subcommand>
```

### Global Flags
- `--lang <lang>`: Application language override (`en` or `hu`).
- `--debug`: Enable verbose diagnostic file logging to `~/Library/Logs/OtterKeep/debug.log`.
- `--version`: Display OtterKeep semantic version (2.0.0) and build number (2000).
- `-h, --help`: Display contextual help and available subcommands.

### Shell Completions
Generate native auto-completion scripts for your preferred shell:
```bash
otterkeep --generate-completion-script zsh > ~/.zfunc/_otterkeep
otterkeep --generate-completion-script bash > /usr/local/etc/bash_completion.d/otterkeep
otterkeep --generate-completion-script fish > ~/.config/fish/completions/otterkeep.fish
```

---

## 2. Core Subcommands

### `backup`
Executes an immediate backup session or dry-run simulation.
```bash
# Standard incremental backup for the active profile
otterkeep backup

# Target a specific profile with simulation (dry-run)
otterkeep backup --profile Work --dry-run

# Run full backup without APFS clonefile link reuse
otterkeep backup --profile Personal --mode full
```

### `restore`
Restores individual files or directory trees from a historical snapshot.
```bash
# In-place restore of a single document
otterkeep restore --snapshot 2026-10-14T100000Z --file Documents/report.pdf

# Alternate location restore of an entire folder tree
otterkeep restore --snapshot 2026-10-14T100000Z --file Projects/Code --destination /tmp/RestoredCode --mode alternate
```

### `restore-snapshot`
Restores an entire snapshot hierarchy atomically with staging protection.
```bash
otterkeep restore-snapshot --snapshot 2026-10-14T100000Z --destination /Volumes/RestoredDrive
```

### `profile`
Inspects and manages backup profiles.
```bash
otterkeep profile list
otterkeep profile show --name Work
otterkeep profile create --name "Creative" --source /Users/name/Studio --destination /Volumes/BackupDisk
otterkeep profile delete --name "Temp" --force
```

### `status`
Displays real-time status of all configured backup profiles, last snapshot timestamps, and destination health.
```bash
otterkeep status
```

### `schedule`
Evaluates configured cron-like schedules and triggers overdue backup profiles.
```bash
otterkeep schedule
```

### `snapshots` / `snapshot`
Lists recorded snapshots in the catalog for the active or specified profile.
```bash
otterkeep snapshots --profile Work
```

### `file-history` / `history`
Inspects historical versions of a file across snapshots.
```bash
otterkeep file-history --file Documents/budget.xlsx
```

### `diff`
Compares file modifications between snapshots or against the live filesystem.
```bash
otterkeep diff --snapshot-a 2026-10-14T090000Z --snapshot-b 2026-10-14T100000Z
```

---

## 3. Security, Storage & Maintenance

### `scrub`
Executes a cryptographic SHA-256 data scrubbing pass over stored snapshots to verify storage integrity and detect bit-rot.
```bash
otterkeep scrub --profile Work
```

### `lock` / `unlock`
Manages snapshot immutability flags (WORM protection via `uchg`).
```bash
otterkeep lock --snapshot 2026-10-14T100000Z
otterkeep unlock --snapshot 2026-10-14T100000Z
```

### `photos`
Manages incremental Apple Photos library backup and export.
```bash
otterkeep photos status
otterkeep photos sync
```

### `replicate` / `copy-job` / `sync`
Executes 3-2-1 secondary replication to remote offsite targets (SFTP, WebDAV, Cloud).
```bash
otterkeep replicate --profile Work
```

### `prune`
Prunes obsolete historical snapshots based on retention policies.
```bash
otterkeep prune --dry-run
otterkeep prune --keep-daily 7 --keep-weekly 4
```

### `daemon`
Controls the headless background service via Apple's modern `SMAppService.agent`.
```bash
otterkeep daemon status
otterkeep daemon install
otterkeep daemon start
otterkeep daemon stop
otterkeep daemon uninstall
```

### `doctor`
Runs comprehensive system diagnostics, verifying Full Disk Access (FDA), volume capabilities, APFS clonefile support, and database health.
```bash
otterkeep doctor
```

### `diagnostics`
Inspects system telemetry or packages a sanitised, anonymised `.tar.gz` diagnostic bundle for developer support.
```bash
otterkeep diagnostics --export-bundle --output ~/Desktop/OtterKeep-Support-Bundle.tar.gz
```
