# Database Design & Cataloging

This document outlines the SQLite database architecture within `OtterKeepDatabase`, covering relational schema design, WAL mode configuration, batch indexing performance, and timeline search queries.

---

## 1. Database Configuration & Pragmas

OtterKeep maintains a dedicated SQLite database (`catalog.sqlite`) at the root of every backup destination. On connection open, the engine executes high-performance pragmas:

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
PRAGMA temp_store = MEMORY;
```

### Clean Closure Protocol
When closing the database:
```sql
PRAGMA wal_checkpoint(TRUNCATE);
```
Following the checkpoint, `sqlite3_close_v2(db)` is called. This flushes all shared-memory segments (`-shm`) and WAL journals (`-wal`), releasing open file descriptors and eliminating external drive ejection locks.

---

## 2. Schema Architecture

```
┌──────────────────────────────────────┐
│              snapshots               │
├──────────────────────────────────────┤
│ id: TEXT PRIMARY KEY                 │
│ timestamp: REAL                      │
│ status: TEXT                         │
│ total_files: INTEGER                 │
│ total_bytes: INTEGER                 │
│ snapshot_path: TEXT                  │
│ backup_type: TEXT                    │
└──────────────────┬───────────────────┘
                   │ 1:N CASCADE
                   ▼
┌──────────────────────────────────────┐
│             file_records             │
├──────────────────────────────────────┤
│ id: INTEGER PRIMARY KEY AUTOINCREMENT│
│ snapshot_id: TEXT REFERENCES snapshot│
│ relative_path: TEXT                  │
│ file_size: INTEGER                   │
│ mtime: REAL                          │
│ inode: INTEGER                       │
│ checksum: TEXT                       │
│ sample_hash: TEXT                    │
│ is_directory: INTEGER                │
│ is_symlink: INTEGER                  │
└──────────────────────────────────────┘
```

---

## 3. Performance Indexes

To support rapid timeline exploration and cross-snapshot searching:
- `idx_file_records_snap`: `(snapshot_id)`
- `idx_file_records_path`: `(relative_path)`
- `idx_file_records_snap_path`: `(snapshot_id, relative_path)`
- `idx_snapshots_timestamp`: `(timestamp DESC)`

---

## 4. Batch Catalog Indexing

Rather than executing individual `INSERT` operations per file, `DatabaseEngine` uses bulk transactions:
- Files are buffered into batches of 1,000 items.
- Prepared statement handles are reused across iterations.
- Batch operations reduce SQLite transaction overhead from seconds to single-digit milliseconds.

---

## 5. Central Database Architecture (`~/.otterkeep/central.sqlite`)

Introduced in v2.0.0, the **Central Database** provides a persistent local repository inside the user's home directory (`~/.otterkeep/central.sqlite`). This decouples local profile configurations and historical browsing from the physical availability of destination backup drives.

### Directory & File Security
- Directory `~/.otterkeep/` permissions: `0700` (`rwx------`).
- Database file permissions: `0600` (`rw-------`).
- Pragmas: `WAL` journal mode, `synchronous = NORMAL`, `foreign_keys = ON`, `busy_timeout = 10000`.

### Relational Schema

```
┌──────────────────────────────────────┐
│               profiles               │
├──────────────────────────────────────┤
│ id: TEXT PRIMARY KEY                 │
│ name: TEXT NOT NULL                  │
│ json_data: TEXT NOT NULL             │
│ created_at: REAL NOT NULL            │
│ updated_at: REAL NOT NULL            │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│           cached_snapshots           │
├──────────────────────────────────────┤
│ id: TEXT NOT NULL                    │
│ profile_id: TEXT NOT NULL            │
│ timestamp: REAL NOT NULL             │
│ status: TEXT NOT NULL                │
│ total_files: INTEGER NOT NULL        │
│ total_bytes: INTEGER NOT NULL        │
│ snapshot_path: TEXT NOT NULL         │
│ backup_type: TEXT NOT NULL           │
│ locked_until: REAL                   │
│ PRIMARY KEY (profile_id, id)         │
└──────────────────┬───────────────────┘
                   │ 1:N
                   ▼
┌──────────────────────────────────────┐
│         cached_file_records          │
├──────────────────────────────────────┤
│ id: INTEGER PRIMARY KEY AUTOINCREMENT│
│ profile_id: TEXT NOT NULL            │
│ snapshot_id: TEXT NOT NULL           │
│ relative_path: TEXT NOT NULL         │
│ file_size: INTEGER NOT NULL          │
│ mtime: REAL NOT NULL                 │
│ inode: INTEGER NOT NULL              │
│ checksum: TEXT                       │
│ is_directory: INTEGER NOT NULL       │
│ is_symlink: INTEGER NOT NULL         │
│ sample_hash: TEXT                    │
└──────────────────────────────────────┘
```

### Performance Indexes
- `idx_profiles_updated`: `(updated_at DESC)`
- `idx_cached_snaps_prof`: `(profile_id, timestamp DESC)`
- `idx_cached_files_prof_snap`: `(profile_id, snapshot_id)`
- `idx_cached_files_prof_path`: `(profile_id, relative_path)`

### Synchronization & Offline Invariant
- **Post-Backup Mirroring**: Upon successful completion of a backup session, `CentralDatabase.shared.cacheSnapshots()` mirrors the target volume's snapshot metadata and file manifest into the central database.
- **Offline Browsing**: When an external drive is detached, UI stores query `CentralDatabase` directly. Users can review snapshots, search file manifests, and inspect diffs without mounting the destination media.
- **Profile Persistence**: Profiles are stored centrally in the `profiles` table as validated JSON payloads, eliminating dependency on loose plist files while retaining full JSON import/export capability.
