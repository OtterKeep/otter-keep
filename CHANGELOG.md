# Changelog

All notable changes to OtterKeep are documented in this file in accordance with [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [2.0.0] - 2026-10-14 (Build 2000)

### 🌟 Release Summary
Version **2.0.0** is a monumental milestone release for OtterKeep, delivering a full transition to Clean Architecture (Hexagonal / Ports & Adapters), a centralized database with offline historical inspection, Apple-standard unified logging, deep data resilience and crash-consistency hardening, near-continuous event-driven backups, anti-ransomware canary traps, Content-Defined Chunking (FastCDC), hardware power and thermal governance, and a refined, human-centric native macOS sanctuary user interface.

- **🏛️ Clean Architecture (Hexagonal / Ports & Adapters) Transition**:
  - **Pure Domain Layer (`OtterKeepDomain`)**: Independent enterprise business models (`SnapshotRecord`, `FileCatalogRecord`, `PendingReplicationRecord`, `PhotosAssetRecord`), GFS retention policies, and domain invariants with zero external dependencies.
  - **Application Layer (`OtterKeepApplication`)**: Abstract repository and storage ports (`SnapshotRepositoryProtocol`, `FileCatalogRepositoryProtocol`, `FileSystemPort`, `PlatformPorts`), DTO data transfer boundaries (`ProfileDTO`, `SnapshotDTO`, `RetentionDTO`), and high-level use case workflows (`SnapshotCatalogUseCases`, `RetentionUseCases`).
  - **Dependency Inversion**: Filesystem storage adapters (`OtterKeepStorage`) and the database engine (`OtterKeepDatabase`) implement application ports as clean infrastructure adapters.

- **🗄️ Central Database & Offline Historical Inspection**:
  - Centralized SQLite database in the user's application directory (`~/.otterkeep/central.sqlite`) storing backup profile configurations (`profiles`) alongside historical snapshots and cached file metadata (`cached_snapshots`, `cached_file_records`).
  - **Offline Browsing**: Backup histories, snapshot statistics, and file timelines remain immediately browsable and searchable in the GUI even when external backup drives are disconnected.
  - **Dual Format Preservation**: JSON export and import for profiles is preserved alongside SQLite storage for complete portability.

- **🪵 Apple-Standard Unified Logging & Telemetry**:
  - Structured Apple Unified Logging (`os_log`) organized by subsystem categories (`Backup`, `Restore`, `Storage`, `Security`, `Database`, `Hook`), with automatic privacy scrubbing (`LogPrivacySanitizer`).
  - Dedicated Apple-standard diagnostic log destination: `~/Library/Logs/OtterKeep/otterkeep.log`.
  - One-click anonymized diagnostic bundle export (`SanctuarySupportBundleExporter`) via GUI and CLI (`otterkeep diagnostics --export-bundle`).

- **🛡️ Data Resilience & Fault-Tolerance Hardening**:
  - **Volume Circuit Breaker**: Immediate cancellation (`group.cancelAll()`) and structured abort upon unexpected drive disconnection (`EIO`, `ENODEV`, `EROFS`, `ENOENT`) or fatal write errors, avoiding CPU spinning or log flooding.
  - **`ENOSPC` Fast-Fail**: Immediate session abort and cleanup of temporary `.in-progress_` staging directories when destination disk capacity is exhausted.
  - **100% Certainty Catalog Reconciliation**: Discovered on-disk snapshots are validated and reconciled into the local SQLite catalog through strict completeness checks (committed `.snapshot_info.json`, matching profile name, valid `root/` tree), preventing partial or corrupted directories from appearing in the catalog.
  - **3-Phase Atomic Directory Restore & `.old` Safety Net**: Full directory restores unpack into a `.staging_<uuid>` directory, atomically rename existing destinations to `<target>.old_<timestamp>`, move staging to destination, and prune the `.old` copy only after verification (with automatic rollback on failure).
  - **SQLite WAL Mode & Busy Timeout**: Enforced Write-Ahead Logging and 10-second busy timeout for smooth, lock-free concurrent operation.
  - **Self-Healing SQLite Maintenance**: Automatic structural integrity checks (`PRAGMA quick_check;`), query planner optimization (`PRAGMA optimize;`), compaction (`VACUUM;`), and corrupted index repair (`REINDEX;`).

- **⚡ Core Engine & Security Upgrades**:
  - **Near-Continuous Backup Engine (`FSEventWatcher`)**: Darwin `FSEventStreamCreate` monitor streams filesystem events in real time, automatically debouncing bursts of activity and respecting exclusion rules.
  - **Power & Thermal Governor (`PowerAndThermalGovernor`)**: Monitors battery status, low power mode, and macOS thermal pressure (`ProcessInfo.thermalState`), automatically pacing or pausing background I/O to maintain cool, quiet operation.
  - **Anti-Ransomware Canary Traps (`CanaryTrapMonitor`)**: Plants hidden tripwire files (`.otterkeep_canary_*.dat`) with known SHA-256 signatures, monitors real-time access via `DispatchSourceFileSystemObject`, enforces `uchg` immutability, and aborts backups if tampering is detected.
  - **Content-Defined Chunking (`FastCDCEngine`)**: Gear rolling hash chunking with normalized masks targeting 64 KB average chunks for large changing files, backed by content-addressed storage (`chunks/xx/yy/<sha256>.chunk`) and bit-for-bit file reconstruction.
  - **Sparsebundle Encrypted Containers (`SparsebundleContainer`)**: Encapsulates backups inside encrypted, auto-expanding APFS disk images via `hdiutil`.
  - **Multi-Drive Rotation & Zero-Config Adoption**: Profiles support drive rotation across multiple volume UUIDs (`destinationVolumeUUIDs`) and automatically recognize backup history on new systems via `.otterkeep_profile_meta.json`.

- **🎨 Sanctuary UX & Modernized Interface**:
  - **Sanctuary Onboarding Wizard**: Native 4-step wizard guiding new users through profile setup, destination selection, and Full Disk Access permissions.
  - **Visual Timeline Scrubber**: Interactive spatial slider with step buttons in the Restore Explorer for navigating historical snapshots.
  - **Consolidated Action Cluster**: Unified action buttons on the status card (Dry-Run Analysis + Back Up Now / Stop Backup).
  - **Tabbed Modal Panels**: Preferences, Profile Settings, and System Logs converted into clean, globally accessible modal dialogs.
  - **Status-Driven Sidebar Icons**: Dynamic icons representing profile health (green checkmark, red error triangle, clock for >14 days old, or schedule question mark).
  - **Friendly Ottie Deletion Modal**: Warm, reassuring deletion confirmation dialog featuring Ottie the mascot with a questioning badge.
  - **Technology Stack Exclusion Presets**: One-click exclusion buttons for Node.js (`node_modules`), Xcode (`.build`, `DerivedData`), Python (`__pycache__`, `.venv`), and media cache folders.
  - **Unified Labels & Localization**: Standardized button labels and 100% bilingual string parity across Hungarian and English.

- **CLI Architecture & Packaging**:
  - Fully migrated CLI to `apple/swift-argument-parser` with auto-generated shell completions for `zsh`, `bash`, and `fish`.
  - Modernized background daemon management to Apple's macOS 13+ `SMAppService.agent` API.
  - Integrated official Sparkle 2.10 framework into the application bundle with cryptographically signed EdDSA/Ed25519 appcasts.
  - Updated repository and distribution URLs to `https://github.com/OtterKeep/otter-keep` and Homebrew tap to `OtterKeep/otterkeep`.

- **Subsystem SemVer Alignment**:
  - `OtterKeepStorage`: `2.0.0`
  - `OtterKeepDatabase`: `2.0.0`
  - `OtterKeepCore`: `2.0.0`
  - `OtterKeepUI`: `2.0.0`
  - `OtterKeepCLI`: `2.0.0`
  - `OtterKeepFinderSyncExtension`: `2.0.0`

---

## [1.7.1] - 2026-10-13 (Build 1701)

### 🌟 Release Summary
Version **1.7.1** is a comprehensive architectural modularization, subsystem decomposition, and verification hardening release for OtterKeep. Monolithic files exceeding 800–3,200 lines across all core subsystems have been decoupled into focused, single-responsibility components and domain stores under strict Swift 6 concurrency, with zero regression in functionality or performance:

- **🏛️ Platform Boundaries & Headless Hardening**:
  - Enforced strict layering in background processes: the backup core (`OtterKeepCore/Pipeline`) is completely free of direct AppKit and `NSWorkspace` dependencies.
  - Volume management and unmounting operate through the shared `VolumeEjecting` protocol (`OtterKeepCore/System/VolumeEjecting.swift`), with AppKit-based implementations (`SystemVolumeEjector`) injected in an isolated manner.
  - System monitoring, notification handling, and Finder preferences are wrapped in clean protocol abstractions (`VolumeObserving`, `NotificationPresenting`, `FinderSettingsOpening`), with platform adapters (`SystemVolumeObserver`, `SystemNotificationPresenter`, `SystemFinderSettingsOpener`) shielded behind `#if canImport(AppKit)` guards, guaranteeing Darwin headless CLI and daemon support.

- **🌐 Single Source of Truth Localization**:
  - Merged separate `L10n+English.swift` and `L10n+Hungarian.swift` dictionaries into the unified `L10n+Strings.swift` table, defining English and Hungarian translations (`Translation`) side-by-side for each key, eliminating missing translations and runtime fallback errors.
  - Hardened `hasExplicitTranslation(for:in:)` verification: resolves system language (`.system`) to the active locale and verifies non-empty text content.

- **🔄 Unified 3-2-1 Replication Pipeline**:
  - Eliminated 850+ lines of redundant state management and loop logic across WebDAV, SFTP, S3, and local/SMB replication.
  - Remote storage adapters implement the shared `ReplicationSink` protocol, while transactional snapshot records, file tracking (`recordReplicationFile`), progress emission, and error handling are centralized in `executeReplicationPipeline`.

- **🖥️ UI & State Modularization**:
  - Reduced the monolithic `AppState.swift` (over 3,000 lines) to 456 lines, distributing state across 5 dedicated `@Observable` stores: `RestoreTimelineStore`, `PhotosStore`, `ReplicationDestinationStore`, `MaintenanceSettingsStore`, and `BackupRuntimeStore`.
  - Decomposed oversized views into focused card and section extensions:
    - `RemoteDestinationEditorModalView.swift` (975 → 194 lines)
    - `MenuBarContentView.swift` (753 → 54 lines)
    - `SettingsView.swift` (752 → 169 lines)
    - `PhotosBackupView.swift` (550 → 46 lines)
    - `RestoreExplorerView.swift` (1,266 → 205 lines)
    - `ProfileRulesView.swift` (1,067 → 102 lines)

- **🗄️ Database & CLI Decoupling**:
  - Decomposed `DatabaseEngine.swift` (1,592 lines) into focused modules: `DatabaseRecords.swift`, `DatabaseEngine+Snapshots.swift`, `DatabaseEngine+FileCatalog.swift`, `DatabaseEngine+Replication.swift`, and `DatabaseEngine+ScrubbingAndPhotos.swift`.
  - Structured `OtterKeepCLI/main.swift` (1,323 lines) into functional command groups: `BackupCommands.swift`, `ProfileCommands.swift`, `MaintenanceCommands.swift`, `ReplicationAndPhotosCommands.swift`, `SystemCommands.swift`, and `CLIHelpers.swift`.

- **🧪 Official Swift-Testing Integration Suite**:
  - Replaced the custom 1,748-line test runner (`OtterKeepTestRunner`) with an official `swift-testing` target (`Tests/OtterKeepIntegrationTests`, 12 modules, 62 tests).
  - Tests run directly via `swift test` and Xcode with native `--filter` support.
  - Updated `scripts/test.sh` to handle Command Line Tools `TestingMacros` compiler plugins smoothly.

- **📌 Single Version Manifest**:
  - Introduced `version.json` and `scripts/sync_version.sh` to derive `CoreEngine` constants, `package_app.sh` defaults, and Sparkle `appcast.xml` metadata from a single source, eliminating version drift.

- **Subsystem SemVer Alignment**:
  - `OtterKeepStorage`: `1.3.0`
  - `OtterKeepDatabase`: `1.3.1` (Patch refactor)
  - `OtterKeepCore`: `1.7.1` (Patch refactor)
  - `OtterKeepUI`: `1.7.1` (Patch refactor)
  - `OtterKeepCLI`: `1.3.1` (Patch refactor)
  - `OtterKeepFinderSyncExtension`: `1.0.1`

---

## [1.7.0] - 2026-10-09 (Build 1700)

### 🌟 Release Summary
Version **1.7.0** is a major backend maintenance, architectural stability, and security hardening release for OtterKeep:
- **Clean Architectural Layering**: Enforced strict boundary separation across subsystems: `Storage` (`OtterKeepStorage`) → `Database` (`OtterKeepDatabase`) → `Core Engine` (`OtterKeepCore`) → `Presentation & Tools` (`OtterKeepUI`, `OtterKeepCLI`).
- **Centralized Snapshot Catalog Service (`SnapshotCatalogService`)**: Encapsulated all SQLite manifest operations, snapshot timeline queries, version diffing, and WORM immutability locking behind a robust service with transactional database lifecycles (`withDatabase`), guaranteeing WAL checkpointing and immediate connection release on all paths.
- **Unified 3-2-1 Compliance Evaluator (`ComplianceEvaluator`)**: Consolidated duplicate compliance calculation logic from UI and CLI into a single authoritative core evaluator in `OtterKeepCore`, ensuring consistent, localized reporting across terminal and graphical interfaces.
- **Security & Data Hardening**:
  - Enforced strict `0600` POSIX file permissions on SQLite database catalogs via `chmod` immediately upon creation and opening.
  - Subprocess environment isolation: Hardened `SFTPStorageProvider` subprocess execution for `/usr/bin/scp` and `/usr/bin/ssh` to prevent credential and variable leakage from the parent process environment.
  - Cryptographic pruning: Removed legacy `encryptLegacyV1` generation from `ClientSideEncryptor`, while retaining a safe, documented, backward-compatible `decrypt` fallback for pre-existing `DSENC1` archives.
- **Compatibility Shim & Dead Code Pruning**:
  - Removed deprecated `FallbackFileSystemProvider` and `APFSFileSystemProvider` shims in `OtterKeepStorage`, fully consolidating filesystem dispatch into `DefaultFileSystemProvider` and `FileSystemDriverRegistry`.
  - Pruned legacy rebranding leftovers (`SquirrelTheme`, squirrel card styling modifiers) in `OtterKeepUI`.
  - Pruned obsolete navigation enum cases in `AppState` and aligned navigation routing in `MainWindowView`.
  - Removed obsolete `OtterKeepEngine` typealias in `CoreEngine.swift`.
- **macOS GUI UX & Folder Restore**:
  - Enabled recursive directory tree selection and one-click folder restore in `RestoreExplorerView`.
  - Replaced alarmist `ABORT` badge with warm amber `Auto-Pause` badge in `ProfileRulesView`.
  - Standardized diff modal footer to native "Close" with Escape shortcut.
  - Added path hover tooltips and bordered button styling in `BackupPipelineView`.
  - Corrected documentation and release URLs to `OtterKeep/otter-keep`.
- **macOS MenuBar Extra Overhaul**:
  - Pixel-perfect mascot template icon maintaining exact 18x18pt dimensions without width jitter.
  - Linear live progress bar with speed (`⚡ MB/s`), completion percentage, processed item counter, and remaining time.
  - Uncapped profile management with smooth scrolling and rich context menu (Incremental, Full, Dry-Run, Time Machine, Finder).
  - Removable destination volume detection and native safe ejection (`unmountAndEjectDevice`).
  - 1-click Time Machine shortcut in header and software update check action in footer.
- **Homebrew Release Automation**:
  - Aligned release workflow to record and verify ZIP archive SHA-256 checksums (`zip_sha256`) for Homebrew tap distribution.
- **Bilingual Localization & Telemetry Polish**: Standardized Apple Unified Logging subsystem identifiers to `com.otterkeep` and localized 3-2-1 rule breakdown formatting in Hungarian and English.

---

## [1.6.0] - 2026-10-08 (Build 1600)

### 🌟 Release Summary
Version **1.6.0** delivers a comprehensive UX, human interface, and architectural polish across the entire OtterKeep GUI, adhering to native macOS Human Interface Guidelines (HIG) and the brand's Sanctuary Principle:
- **Profile-Aware Last Backup Status**: Switching between backup profiles immediately reflects that profile's last backup outcome, relative timestamp, and snapshot count across the sidebar, header bar, and dashboard hero card.
- **Dynamic 3D Pixar Ottie Mascot in Overview**: Replaced the static logo in the Sanctuary Hero card with 3 expressive, transparent-background mascot illustrations reflecting system and storage health:
  - **Safe**: Ottie is proud and joyful, holding a sparkling crystal.
  - **Warning**: Ottie is gently attentive, inspecting a glowing river pebble with care (no alarmist stress).
  - **Danger / Action Needed**: Ottie is empathetic and determined, clutching the protected stone securely to reassure the user that their data is safe.
- **Integrated Storage Forecasting in Sanctuary Hero Card**: Elevated the card height and integrated live storage depletion telemetry (daily growth rate, days remaining, health badges, quota warnings) directly beside Ottie, eliminating the standalone forecast box.
- **Direct Pipeline Folder Management**: Moved "Change folder" and "Reveal in Finder" actions directly inside the Source and Destination nodes of the visual `BackupPipelineView`, removing the redundant cards from the bottom of the Overview dashboard.
- **3-Tab Segmented Rules & Maintenance Workspace**: Reorganized the previously overwhelming 12-card configuration view into three focused sub-tabs:
  1. *Rules & Exclusions*: Directory headers, exclusions with quick presets & gitignore, iCloud strategy, metered Wi-Fi protection, and ransomware guard.
  2. *Automation & Schedule*: Backup triggers, external drive auto-backup on mount, 3-2-1 offsite replication, and outbound webhooks (Slack/Discord/Pushover).
  3. *Maintenance & Storage*: Unified snapshot retention policy (synchronizing auto-pruning and maximum snapshots), WORM immutability & manual data scrubber, catalog disaster recovery, and technical metadata.
- **Time Machine Timeline Mode Reactivation**: Reactivated the vertical snapshot timeline view (`RestoreBrowseMode.timeline`) alongside Snapshot Browser and Global Search, with file difference comparison and QuickLook preview (`Space`).
- **macOS Native Keyboard Shortcuts**: Fast navigation with `⌘1` (Overview), `⌘2` (Time Machine), `⌘3` (Rules & Maintenance), `⌘B` (Backup Now), `⌘D` (Dry-Run), and `⌘.` (Stop).
- **System Notification on Software Updates**: When an update is detected (automatically or manually), OtterKeep chimes a friendly macOS system banner via `UNUserNotificationCenter` with sound and version details.
- **Design Token Clean-up & Localization**: Consolidated color tokens to signature `otterAmber` and `oceanicTeal`, and fully localized system status subtitles, units, and menu bar descriptions in English and Hungarian.

---

### 🎨 Sanctuary Experience & Mascot Art
- Added 3 transparent 3D Pixar-styled PNG assets: `OttieSanctuarySafe.png`, `OttieSanctuaryWarning.png`, `OttieSanctuaryDanger.png`.
- Introduced `SanctuaryMascotMood` (`.safe`, `.warning`, `.danger`) and `OttieSanctuaryMascotView` in `OtterKeepUI`.
- Mascot state dynamically evaluates backup error counts, snapshot presence, single-point-of-failure volume configurations, and storage depletion velocity.

### 🛠️ Workspace Architecture & Maintenance Harmonization
- Replaced the linear 12-block scroll with `ProfileMaintenanceSubTab` segmented navigation (`appState.activeMaintenanceSubTab`).
- Eliminated duplicate snapshot retention steppers, consolidating `appState.maxSnapshotsToKeep` and `profile.pruningPolicy.maxSnapshotsToKeep` into a single unified control with live prune confirmation.
- Integrated pipeline diagram actions with macOS `NSWorkspace.shared.activateFileViewerSelecting` and directory selection panels.

### 🔔 System Telemetry & Notifications
- Software update checks trigger system notification chimes with sound (`.default`) and interactive app launch handler upon discovery.

### 🎨 Human Interface & Sanctuary UX
- **Sidebar Profile Status Indicators**: Each profile row in the sidebar list displays a dynamic status dot and localized status line (e.g. *"Last backup: 5 minutes ago"*, snapshot count, or live phase).
- **Workspace Header Status Badge**: The header bar displays the selected profile's last backup state directly adjacent to its APFS Copy-on-Write badge.
- **Cross-Profile Isolation**: Resolved summary leaks between profiles by implementing per-profile snapshot caching and status resolution (`lastStatusInfo(for:)`).
- **QuickLook (`Space`) Integration**: File rows in the restore explorer timeline support native macOS QuickLook file previews.

### ⌨️ Native macOS Keyboard Shortcuts
- `⌘1`: Overview workspace tab
- `⌘2`: Time Machine restore explorer tab
- `⌘3`: Rules & Maintenance tab
- `⌘B`: Start backup now
- `⌘D`: Quick dry-run analysis
- `⌘.`: Cancel active backup

### 🌐 Bilingual Parity & String Localization
- Replaced hardcoded replication strings in `MenuBarContentView` with localized tokens (`.menuBarReplicationRunning`, `.menuBarMoreProfilesFormat`).
- Localized Full Disk Access and Finder Extension card status descriptions in `SettingsView`.
- Replaced raw unit strings with `.unitCountFormat` and `.daysCountUnitFormat`.

---

## [1.5.0] - 2026-10-08 (Build 1500)

### 🌟 Release Summary
Version **1.5.0** introduces major modern data protection, verification, and comparison capabilities to OtterKeep:
- **Side-by-side file content diffing** between snapshots (Myers LCS algorithm for text, binary metadata comparison).
- **Silent background data scrubber** running with Darwin `.background` I/O QoS to detect bit-rot and silent corruption with native notifications.
- **WORM (Write Once, Read Many) immutability locking** with BSD `uchg` flags protecting snapshots from accidental deletion, ransomware, or premature pruning for configurable retention periods (default: 30 days).
- **Backblaze B2 Cloud Storage API support** as a native remote secondary backup target via S3-compatible endpoints.
- **Intelligent parallel multi-destination backup** allowing simultaneous CoW local and remote transfers with decoupled fault tolerance and background catch-up replication upon reconnection.
- **Dataless iCloud file change detection** eliminating unwanted cloud download triggers by strictly evaluating metadata.
- **Enhanced dual-tier logging** offering clear user-facing operational summaries alongside forensic verbose diagnostics.

---

### 🔍 Side-by-Side File Content Comparison
- **Myers LCS Alignment**: Implemented `TextDiffEngine` computing line-by-line differences with side-by-side row alignment, additions/deletions counts, and modification markers.
- **Binary Signature Inspection**: Non-UTF8 files or files containing null bytes are safely handled as binary, displaying metadata diffs (file size, SHA-256 digests, modification timestamps) without garbling text views.
- **SwiftUI Modal & CLI Viewer**:
  - GUI: Added `SideBySideDiffModalView` with synchronized dual-column scrolling, syntax-aware line coloration, and line numbers.
  - CLI: Enhanced `otterkeep diff --profile <id> --file <rel_path> --side-by-side` with terminal column formatting.

### 🛡️ Silent Background Data Scrubber
- **Low-Priority Background Execution**: `DataScrubberEngine` operates using Swift Concurrency `Task(priority: .background)` (Darwin `QOS_CLASS_BACKGROUND`) with adaptive micro-sleep throttling (5ms default) and thermal-governance pausing.
- **Cryptographic Bit-Rot Auditing**: Periodically recomputes full SHA-256 hashes for all physical snapshot files and compares them against the SQLite snapshot catalog.
- **Audit History & Alerts**: Persists scan outcomes to SQLite (`scrub_audits` table) and delivers proactive macOS User Notifications upon detecting corrupted or tampered blocks.
- **CLI & GUI Access**: Run on-demand via `otterkeep scrub --profile <id> [--limit <n>]`.

### 🔒 WORM Immutability & Retention Immunity
- **BSD File Flag Locking**: Added `isFileImmutable` and `setImmutable` in `FileSystemProvider` using BSD `chflags(2)` (`UF_IMMUTABLE` / `SF_IMMUTABLE`).
- **Configurable Retention Duration**: Snapshots can be locked for a configured period (default: 30 days) stored in the database schema (`locked_until`).
- **Pruning Safety Immunity**: `RetentionManager` GFS rotation strictly protects locked snapshots from auto-pruning or manual deletion attempts, returning access denied errors until expiration.
- **CLI Management**: Added `otterkeep lock --profile <id> --snapshot <id> [--days <count>]` and `otterkeep unlock`.

### ☁️ Backblaze B2 Native Cloud Destination
- **B2 Configuration & Storage Provider**: Implemented `B2Configuration` and `B2StorageProvider` supporting Backblaze B2 application keys, automatic S3 region endpoint resolution (`s3.<region>.backblazeb2.com`), and bucket path prefixes.
- **3-2-1 Compliance Integration**: Fully integrated into `RemoteStorageFactory`, `BackupCopyJobCoordinator`, and `RestoreEngine`.
- **GUI Destination Editor**: Added dedicated Backblaze B2 configuration tile, credentials inputs, and live credential validation in `RemoteDestinationEditorModalView`.

### ⚡ Parallel Multi-Destination & Catch-Up Replication
- **Decoupled Failure Isolation**: Local APFS CoW snapshot creation succeeds even if secondary cloud/NAS destinations are offline or fail mid-flight.
- **Replication Catch-Up Coordinator**: Failed or offline secondary destinations queue tasks into the SQLite `pending_replications` table, which automatically catch up in the background once network connectivity is restored.
- **UI Settings Toggle**: Added `isParallelExecutionEnabled` toggle to Profile Copy Job settings.

### 🍏 Dataless iCloud Change Detection
- **Zero-Download Verification**: Enhanced `ChangeDetector` to identify dataless/ubiquitous iCloud Drive files (`isDatalessICloud`) and verify them strictly by file size and modification timestamp.
- **Kernel Fault Prevention**: Completely eliminates inadvertent payload hashing or sampling that triggers forced iCloud file downloads during routine scans.

### 📝 Dual-Tier Diagnostic Logging
- **User-Facing High-Value Summaries**: Default log tier focuses on essential, human-friendly milestones (snapshot started, transfer speed, files scanned, immutability locked, scrub healthy).
- **Forensic Verbose Mode**: Activated via `--debug` or app preferences, outputting detailed per-file decisions, socket state changes, and cryptographic metrics to timestamped `.log` files.

### 🧪 System Test Suite Expansion (Module 11)
- Added **Module 11** to `OtterKeepTestRunner`, expanding the deterministic system test suite to 59 tests with 100% pass rate:
  - 11.1: TextDiffEngine Side-by-Side LCS Text & Binary Detection
  - 11.2: DataScrubberEngine Background Bit-Rot & Corruption Detection
  - 11.3: WORM Immutability Flags & GFS Retention Immunity
  - 11.4: Backblaze B2 S3 Configuration Mapping & Provider Resolution
  - 11.5: ReplicationCatchUpCoordinator Deferred Task Queueing & Lifecycle
  - 11.6: Dataless iCloud Drive Change Detection Without Forced Download

---

## [1.4.0] - 2026-10-07 (Build 1400)

### 🌟 Release Summary
Version **1.4.0** is an intensive engineering and stability release focusing on core architecture hardening, filesystem fidelity, multi-process IPC security, complete test redesign, and comprehensive documentation rewrite with 100% English-Hungarian parity. No new user-facing features were introduced, ensuring maximum focus on rock-solid dependability.

### 🛡️ Core Backend & Architecture
- **Safe External Volume Ejection**: Added explicit database closure (`DatabaseEngine.close()`) utilizing `sqlite3_close_v2` and `PRAGMA wal_checkpoint(TRUNCATE)` prior to disk auto-unmounting. Completely prevents unmount locks when backing up to external USB/Thunderbolt drives.
- **Cooperative Multitasking & Battery Friendliness**: Introduced cooperative task suspension (`await Task.yield()`) every 250 scanned directory items in `FileTreeScanner`, keeping CPU core temperatures low and preventing UI stutters.
- **IPC Peer Validation**: Hardened local Unix domain socket IPC in `SingleInstanceManager` with Darwin `getpeereid(clientFD, &peerUID, &peerGID)` checks, strictly rejecting connections from unauthorized OS users (`peerUID != geteuid()`).
- **Path Traversal Protection**: Implemented canonical path resolution (`resolvingSymlinksInPath()`) across IPC handlers to prevent directory traversal vectors during remote restore requests.
- **Localized Restore Collisions**: Added type-safe localized suffix formatting (`.restoredSuffixFormat`) resolving cleanly to ` (visszaállított %d)` in Hungarian and ` (restored %d)` in English.
- **Subsystem SemVer Alignment**: Aligned all package dependencies and subsystems (`OtterKeepStorage: 1.1.1`, `OtterKeepDatabase: 1.1.1`, `OtterKeepCore: 1.2.2`, `OtterKeepUI: 1.3.2`, `OtterKeepCLI: 1.1.1`, `OtterKeepFinderSyncExtension: 1.0.1`).

### 🧪 Integration Test Suite Redesign
- **Total Test Redesign**: Completely overhauled and replaced legacy tests with a modern 10-module benchmark suite (`OtterKeepTestRunner`) covering 50 thorough system integration tests with 100% pass rate:
  1. System & Version SemVer Alignment (Build 1400 / Appcast audit)
  2. APFS Copy-on-Write (`clonefile`), Hardlinks, and xattr Preservation
  3. SQLite WAL Database Engine, Diff Engine, and Timeline Queries
  4. Differential Incremental Backup Engine and Ransomware Guard
  5. OKENC2 (600,000 PBKDF2 rounds) & DSENC1 Legacy Decryption Compatibility
  6. IPC Bounds, Socket Permissions (0600), and Peer UID Enforcement
  7. Privacy-Preserving Logging & Dual-Tier Diagnostics
  8. Apple Photos Backup, Ephemeral Cache Guards, and XMP Sidecars
  9. 100% English-Hungarian Bilingual Localization Parity
  10. Modern Sanctuary UI Design System & Three-Tier Error Recovery

### 🔄 Full Snapshot Restore & Recovery Engine
- **Full Snapshot Restoration**: Implemented end-to-end full snapshot restore capabilities across Core (`StorageRestorationEngine`), UI (`RestoreExplorerView`), and CLI (`otterkeep restore --snapshot-id <id> --full`).
- **Atomic Restoration Safeguards**: Transaction-safe staging and atomic in-place file restoration preserving POSIX permissions, creation timestamps, and extended attributes (`xattrs`).
- **Interactive Restore Feedback & Diff Modals**: Enhanced restore progress telemetry (`OperationFeedbackModalView`) and pre-restoration snapshot diff sheet inspector with storage provider abstraction.

### 🎨 Settings & Profile Experience Modernization
- **Equal-Height Card Layouts**: Re-architected multi-column card rows in `SettingsView` (Language, Appearance, Startup, and Permission HUD) and `ProfileRulesAndMaintenanceView` (Retention Consolidation and Disaster Recovery) using native SwiftUI `Grid` and `GridRow` containers with `.frame(maxHeight: .infinity)`, ensuring pixel-aligned card heights.
- **Contextual Profile Metadata & Identifiers**: Cleaned up the global Preferences window by removing the technical profile UUID card list. Added a discreet, dedicated *Profile Identifiers & Metadata* section at the bottom of the Profile Settings view featuring monospaced UUIDs and a one-click clipboard copy action.
- **De-cluttered Profile Rules**: Replaced bulky, redundant directory selection cards with a sleek, single-row `folderSummaryHeader` banner linking directly to the Main Dashboard overview pipeline.
- **Bilingual Localization Parity**: Extended `Localization.swift` with Hungarian and English strings for the new profile metadata and system information sections.

### 📖 Documentation & Community
- **Documentation Overhaul**: Authored 15 brand-new, drift-free guides spanning architecture specifications, storage engine mechanics, database schemas, security manuals, CLI references, and 5 end-user guides in complete English and Hungarian parity.
- **Distribution Packages**: Updated Sparkle 2.0 appcast feed (`Distribution/appcast.xml`) and Homebrew formula template (`Distribution/otterkeep.rb.template`) targeting v1.4.0.
