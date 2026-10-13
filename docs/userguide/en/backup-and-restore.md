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

## 2. Navigating Snapshot Timelines

Under the **Restore** tab in the main application window:

- **Snapshot Selector**: View a chronological history of backups, with timestamps, total file counts, and logical byte sizes.
- **File Explorer**: Browse directories exactly as they appeared at the moment the snapshot was captured.
- **Global Search**: Type any file name or substring into the search bar to locate all historical versions across every recorded snapshot.
- **Diff View**: Compare any two snapshots side-by-side to see what was added, modified, or removed.

---

## 3. Restoring Files Safely

When restoring files, OtterKeep prioritizes safety above all else:

### Collision Avoidance
If a file with the same name already exists at the restore destination:
- OtterKeep never silently overwrites your existing work.
- It applies a clear, localized version suffix:
  - English: `Report (restored 1).pdf`
  - Hungarian: `Report (visszaállított 1).pdf`

### Restoring In-Place or to Custom Location
- **Restore In-Place**: Reconstructs the file directly to its original historical path.
- **Restore To...**: Select any folder on your Mac (such as your Desktop or a dedicated triage folder) to inspect the recovered file safely.

---

## 4. Pruning and Retention Policies

To ensure your backup drive never fills up unexpectedly, configure automatic retention rules under **Settings**:
- **Keep Hourly Backups**: Retained for the last 24 hours.
- **Keep Daily Backups**: Retained for the last 30 days.
- **Keep Weekly Backups**: Retained for 12 months.
- When an obsolete snapshot is pruned, the SQLite catalog updates automatically and APFS frees data blocks that are no longer referenced by any remaining snapshot.
