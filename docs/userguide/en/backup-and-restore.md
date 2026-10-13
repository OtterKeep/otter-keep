# Backup and Restore Guide

This guide details how OtterKeep manages incremental snapshot timelines, detects changes, and securely restores individual files or complete directory hierarchies.

---

## 1. How Incremental Snapshots Work

Every backup session executed by OtterKeep produces an immutable **Snapshot**:

1. **Scan Phase**: The engine traverses configured source paths. Unmodified files are identified by comparing file sizes, nanosecond-precision modification timestamps, and APFS inodes.
2. **CoW Cloning**: For unchanged files existing on the target volume, OtterKeep uses `clonefile(2)` to create pointers to existing data blocks. This operation finishes in milliseconds and consumes zero additional disk space.
3. **Data Transfer**: Only newly created or modified files are copied to the destination.
4. **Catalog Indexing**: A detailed file manifest is recorded into an embedded SQLite database operating in Write-Ahead Logging (WAL) mode.

---

## 2. Navigating Snapshot Timelines & Offline Browsing

Under the **Restore** tab in the main application window:

- **Offline Metadata Access**: Thanks to OtterKeep's persistent Central Database (`~/.otterkeep/central.sqlite`), you can freely inspect historical snapshots, search directories, and analyze changes even when your external backup drive is disconnected.
- **Snapshot Selector**: View a chronological history of backups, with timestamps, total file counts, logical byte sizes, and seal status.
- **File Explorer**: Browse directories exactly as they appeared at the moment the snapshot was captured.
- **Global Search**: Type any file name or substring into the search bar to locate all historical versions across every recorded snapshot.
- **Diff View**: Compare any two snapshots side-by-side to see what was added, modified, or removed.

---

## 3. Restoring Files & Folders Safely

When restoring data, OtterKeep enforces rigorous crash consistency and safety invariants:

### File Collision Avoidance
If an individual file with the same name already exists at the restore destination:
- OtterKeep never silently overwrites your existing work.
- It applies a clear, localized version suffix:
  - English: `Report (restored 1).pdf`
  - Hungarian: `Report (visszaállított 1).pdf`

### 3-Phase Atomic Folder Restore with `.old` Safety Hold
When restoring entire directory trees or performing in-place full folder recovery:
1. **Staging to Temporary Folder**: Files are fully materialized in an isolated temporary staging directory (`.staging_<uuid>`).
2. **Safe Displacement to `.old`**: The existing target directory is renamed to `.old_<timestamp>` rather than deleted.
3. **Atomic Swap & Final Cleanup**: The verified staging directory is swapped into the final target location. Only after the swap successfully completes is the `.old` backup directory permanently removed. If any error, volume disconnection, or cancellation occurs before this final step, the `.old` directory is immediately restored to its original place with zero data loss.

### Restoring In-Place or to Custom Location
- **Restore In-Place**: Reconstructs files and directories directly to their original historical path.
- **Restore To...**: Select any folder on your Mac (such as your Desktop or a triage folder) to inspect recovered data safely.

---

## 4. 100% Certainty Catalog Reconciliation

If you connect a backup drive that contains completed snapshots created on another system or before a catalog sync:
- OtterKeep's **Catalog Reconciler** automatically inspects snapshot directories on the drive.
- It performs strict completeness checks: verifying directory structure, file non-emptiness, and valid seal state.
- Only verified, 100% complete snapshots are reconciled into your local database, ensuring unindexed historical backups are immediately browsable without duplicates or corrupted entries.

---

## 5. Pruning and Retention Policies

To ensure your backup drive never fills up unexpectedly, configure automatic retention rules under **Profile Settings**:
- **Keep Hourly Backups**: Retained for the last 24 hours.
- **Keep Daily Backups**: Retained for the last 30 days.
- **Keep Weekly Backups**: Retained for 12 months.
- When an obsolete snapshot is pruned, the SQLite catalog updates automatically and APFS frees data blocks that are no longer referenced by any remaining snapshot. Snapshots with active WORM locks are strictly protected and exempted from pruning until their lock expires.
