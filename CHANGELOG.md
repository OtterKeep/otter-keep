# Changelog

All notable changes to OtterKeep are documented in this file in accordance with [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [2.0.0] - 2026-10-13 (Build 2000)

### 🌟 Release Summary / Verzióösszefoglaló
Version **2.0.0** initiates the Clean Architecture (Hexagonal / Ports & Adapters) transition for OtterKeep, establishing pure Domain and Application layers, abstract repository and storage interfaces, and dependency inversion across the entire subsystem topology.

A **2.0.0-ás** verzió elindítja az OtterKeep Clean Architecture (Hexagonal / Ports & Adapters) átállását: tiszta Domain és Application rétegek, absztrakt repository és háttértár interface-ek, valamint szigorú függőség-megfordítás kialakításával a teljes alrendszer-topológiában.

- **Subsystem SemVer Alignment**:
  - `OtterKeepStorage`: `2.0.0`
  - `OtterKeepDatabase`: `2.0.0`
  - `OtterKeepCore`: `2.0.0`
  - `OtterKeepUI`: `2.0.0`
  - `OtterKeepCLI`: `2.0.0`
  - `OtterKeepFinderSyncExtension`: `2.0.0`

---

## [1.7.1] - 2026-10-13 (Build 1701)

### 🌟 Release Summary / Verzióösszefoglaló
Version **1.7.1** is a comprehensive architectural modularization, subsystem decomposition, and verification hardening release for OtterKeep. Monolithic files exceeding 800–3,200 lines across all core subsystems have been decoupled into focused, single-responsibility components and domain stores under strict Swift 6 concurrency, with zero regression in functionality or performance:

Az **1.7.1-es** verzió egy átfogó architekturális modularizációs, alrendszer-dekompozíciós és megbízhatósági mérföldkő az OtterKeep ökoszisztémában. A korábbi 800–3200 soros monolitikus fájlok szigorú Swift 6 konkurens elvek mentén önálló, egyetlen felelősséggel bíró komponensekre, protokoll-alapú platformadapterekre és dedikált állapottárakra (Stores) lettek szétbontva – funkcióvesztés vagy sebességcsökkenés nélkül:

- **🏛️ Platform-függetlenítés és Headless működés (Platform Boundaries & Headless Hardening)**:
  - Szigorú réteghatárok a háttérfolyamatokban: a mentési mag (`OtterKeepCore/Pipeline`) teljesen mentesült a közvetlen AppKit és `NSWorkspace` függőségektől.
  - A kötetkezelés és lecsatolás a közös `VolumeEjecting` protokollon keresztül valósul meg (`OtterKeepCore/System/VolumeEjecting.swift`), az AppKit-alapú megvalósítás (`SystemVolumeEjector`) pedig izoláltan injektálódik.
  - A rendszerfigyelés, értesítéskezelés és Finder-beállítások kezelése tiszta protokoll-absztrakciók mögé került (`VolumeObserving`, `NotificationPresenting`, `FinderSettingsOpening`), amelyek platform-adapterei (`SystemVolumeObserver`, `SystemNotificationPresenter`, `SystemFinderSettingsOpener`) `#if canImport(AppKit)` védelemmel vannak ellátva, garantálva a tiszta Darwin / headless CLI és daemon futtathatóságot.

- **🌐 Egyetlen forrású típusbiztos lokalizáció (Single Source of Truth Localization)**:
  - A korábbi különálló `L10n+English.swift` és `L10n+Hungarian.swift` szótárak összevonásra kerültek a `L10n+Strings.swift` táblába, ahol minden kulcshoz egymás mellett definiált a magyar és angol fordítás (`Translation`), megszüntetve a hiányzó fordítások és runtime fallback hibák kockázatát.
  - Szigorított `hasExplicitTranslation(for:in:)` ellenőrzés: automatikusan feloldja a rendszer nyelvét (`.system`) az effektív nyelvre, és ellenőrzi a nem-üres szövegtartalmat.

- **🔄 Egységesített 3-2-1 replikációs motor (Unified Replication Pipeline)**:
  - A WebDAV, SFTP, S3 és helyi/SMB replikáció 850+ sornyi redundáns állapotkezelése és ciklusszervezése felszámolásra került.
  - A háttértárak a közös `ReplicationSink` protokollt valósítják meg, míg a tranzakciós pillanatkép-rekordok, a fájl-nyilvántartás (`recordReplicationFile`), a folyamat-visszajelzés (progress emission) és a hibakezelés egyetlen központi futtató motorban (`executeReplicationPipeline`) összpontosul.

- **🖥️ SwiftUI felület és állapotkezelés dekompozíciója (UI & State Modularization)**:
  - Az `AppState.swift` monolit (több mint 3000 sor) 456 sorra csökkent. A logikai állapotok 5 dedikált `@Observable` Store-ba kerültek: `RestoreTimelineStore`, `PhotosStore`, `ReplicationDestinationStore`, `MaintenanceSettingsStore` és `BackupRuntimeStore`.
  - A nagyméretű nézetek fókuszált kártya- és szekció-kiterjesztésekre lettek bontva:
    - `RemoteDestinationEditorModalView.swift` (975 → 194 sor)
    - `MenuBarContentView.swift` (753 → 54 sor)
    - `SettingsView.swift` (752 → 169 sor)
    - `PhotosBackupView.swift` (550 → 46 sor)
    - `RestoreExplorerView.swift` (1266 → 205 sor)
    - `ProfileRulesView.swift` (1067 → 102 sor)

- **🗄️ Adatbázis- és CLI-architektúra modularizációja (Database & CLI Decoupling)**:
  - A `DatabaseEngine.swift` (1592 sor) szétbontásra került: `DatabaseRecords.swift`, `DatabaseEngine+Snapshots.swift`, `DatabaseEngine+FileCatalog.swift`, `DatabaseEngine+Replication.swift`, és `DatabaseEngine+ScrubbingAndPhotos.swift`.
  - Az `OtterKeepCLI/main.swift` (1323 sor) fókuszált parancsmodulokra tagolódott: `BackupCommands.swift`, `ProfileCommands.swift`, `MaintenanceCommands.swift`, `ReplicationAndPhotosCommands.swift`, `SystemCommands.swift`, és `CLIHelpers.swift`.

- **🧪 Hivatalos Swift-Testing integrációs tesztcsomag (Official Swift-Testing Suite)**:
  - A korábbi 1,748 soros kézi CLI futtató (`OtterKeepTestRunner`) leváltásra került egy hivatalos `swift-testing` integrációs targetre (`Tests/OtterKeepIntegrationTests`, 12 modul, 62 teszt).
  - A tesztek közvetlenül a `swift test` paranccsal és az Xcode-ból futtathatók és szűrhetők (`--filter`).
  - A `scripts/test.sh` felkészítésre került a Command Line Tools `TestingMacros` fordítópluginjának automatikus feloldására és a stabil futtatásra.

- **📌 Központi verziókezelési manifeszt (Single Version Manifest)**:
  - Bevezetésre került a `version.json` és a `scripts/sync_version.sh` eszköz, amely egyetlen forrásból származtatja a `CoreEngine` konstansait, a `package_app.sh` alapértelmezéseit és a Sparkle `appcast.xml` metaadatait, megszüntetve a korábbi dokumentációs és verzió-eltéréseket.

- **Subsystem SemVer Alignment**:
  - `OtterKeepStorage`: `1.3.0`
  - `OtterKeepDatabase`: `1.3.1` (Patch refactor)
  - `OtterKeepCore`: `1.7.1` (Patch refactor)
  - `OtterKeepUI`: `1.7.1` (Patch refactor)
  - `OtterKeepCLI`: `1.3.1` (Patch refactor)
  - `OtterKeepFinderSyncExtension`: `1.0.1`
  - Teljes tesztcsomag ellenőrizve: 62/62 integrációs teszt 100%-os sikerességgel lefut.

---

## [1.7.0] - 2026-10-09 (Build 1700)

### 🌟 Release Summary / Verzióösszefoglaló
Version **1.7.0** is a major backend maintenance, architectural stability, and security hardening release for OtterKeep, establishing the rock-solid foundation for broad public distribution:
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
  - Replaced alarmist `ABORT` badge with warm amber `Auto-Pause` (`Automatikus megállítás`) badge in `ProfileRulesView`.
  - Standardized diff modal footer to native "Close" (`Bezárás`) with Escape shortcut.
  - Added path hover tooltips and bordered button styling in `BackupPipelineView`.
  - Corrected documentation and release URLs to `richardeszeshu/otter-keep`.
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

### 🌟 Release Summary / Verzióösszefoglaló
Version **1.6.0** delivers a comprehensive UX, human interface, and architectural polish across the entire OtterKeep GUI, adhering to native macOS Human Interface Guidelines (HIG) and the brand's Sanctuary Principle:
- **Profile-Aware Last Backup Status**: Switching between backup profiles immediately reflects that profile's last backup outcome, relative timestamp, and snapshot count across the sidebar, header bar, and dashboard hero card.
- **Dynamic 3D Pixar Ottie Mascot in Overview**: Replaced the static logo in the Sanctuary Hero card with 3 expressive, transparent-background mascot illustrations reflecting system and storage health:
  - **Safe**: Ottie is proud and joyful, holding a sparkling crystal.
  - **Warning**: Ottie is gently attentive, inspecting a glowing river pebble with care (no alarmist stress).
  - **Danger / Action Needed**: Ottie is empathetic and determined, clutching the protected stone securely to reassure the user that their data is safe.
- **Integrated Storage Forecasting in Sanctuary Hero Card**: Elevated the card height and integrated live storage depletion telemetry (daily growth rate, days remaining, health badges, quota warnings) directly beside Ottie, eliminating the standalone forecast box.
- **Direct Pipeline Folder Management**: Moved "Change folder" and "Reveal in Finder" actions directly inside the Source and Destination nodes of the visual `BackupPipelineView`, removing the redundant cards from the bottom of the Overview dashboard.
- **3-Tab Segmented Rules & Maintenance Workspace**: Reorganized the previously overwhelming 12-card configuration view into three focused sub-tabs:
  1. *Rules & Exclusions (`Szabályok és kizárások`)*: Directory headers, exclusions with quick presets & gitignore, iCloud strategy, metered Wi-Fi protection, and ransomware guard.
  2. *Automation & Schedule (`Automatizáció és ütemezés`)*: Backup triggers, external drive auto-backup on mount, 3-2-1 offsite replication, and outbound webhooks (Slack/Discord/Pushover).
  3. *Maintenance & Storage (`Karbantartás és tárhely`)*: Unified snapshot retention policy (synchronizing auto-pruning and maximum snapshots), WORM immutability & manual data scrubber, catalog disaster recovery, and technical metadata.
- **Time Machine Timeline Mode Reactivation**: Reactivated the vertical snapshot timeline view (`RestoreBrowseMode.timeline`) alongside Snapshot Browser and Global Search, with file difference comparison and QuickLook preview (`Space`).
- **macOS Native Keyboard Shortcuts**: Fast navigation with `⌘1` (Overview), `⌘2` (Time Machine), `⌘3` (Rules & Maintenance), `⌘B` (Backup Now), `⌘D` (Dry-Run), and `⌘.` (Stop).
- **System Notification on Software Updates**: When an update is detected (automatically or manually), OtterKeep chimes a friendly macOS system banner via `UNUserNotificationCenter` with sound and version details.
- **Arculat Token Purge & Bilingual Localization**: Eliminated legacy color tokens in favor of OtterKeep's signature `otterAmber` and `oceanicTeal`, and fully localized system status subtitles, units, and menu bar descriptions in English and Hungarian.

---

### 🎨 Sanctuary Experience & Mascot Art / Sanctuary élmény és Ottie kabalafigurák
- Added 3 transparent 3D Pixar-styled PNG assets: `OttieSanctuarySafe.png`, `OttieSanctuaryWarning.png`, `OttieSanctuaryDanger.png`.
- Introduced `SanctuaryMascotMood` (`.safe`, `.warning`, `.danger`) and `OttieSanctuaryMascotView` in `OtterKeepUI`.
- Mascot state dynamically evaluates backup error counts, snapshot presence, single-point-of-failure volume configurations, and storage depletion velocity.

### 🛠️ Workspace Architecture & Maintenance Harmonization / Munkaterület újratervezés
- Replaced the linear 12-block scroll with `ProfileMaintenanceSubTab` segmented navigation (`appState.activeMaintenanceSubTab`).
- Eliminated duplicate snapshot retention steppers, consolidating `appState.maxSnapshotsToKeep` and `profile.pruningPolicy.maxSnapshotsToKeep` into a single unified control with live prune confirmation.
- Integrated pipeline diagram actions with macOS `NSWorkspace.shared.activateFileViewerSelecting` and directory selection panels.

### 🔔 System Telemetry & Notifications / Rendszerértesítések
- Software update checks trigger system notification chimes with sound (`.default`) and interactive app launch handler upon discovery.

### 🎨 Human Interface & Sanctuary UX / Felhasználói élmény és felület
- **Sidebar Profile Status Indicators**: Each profile row in the sidebar list now displays a dynamic status dot and localized status line (e.g. *"Utolsó mentés: 5 perce"* / *"Last backup: 5 minutes ago"*, snapshot count, or live phase).
- **Workspace Header Status Badge**: The header bar displays the selected profile's last backup state directly adjacent to its APFS Copy-on-Write badge.
- **Cross-Profile Isolation**: Resolved summary leaks between profiles by implementing per-profile snapshot caching and status resolution (`lastStatusInfo(for:)`).
- **QuickLook (`⎵`) Integration**: File rows in the restore explorer timeline support native macOS QuickLook file previews.

### ⌨️ Native macOS Keyboard Shortcuts / Gyorsbillentyűk
- `⌘1`: Áttekintés / Overview workspace tab
- `⌘2`: Időgép / Time Machine restore explorer tab
- `⌘3`: Szabályok és karbantartás / Rules & Maintenance tab
- `⌘B`: Mentés indítása / Start backup now
- `⌘D`: Próbafuttatás / Quick dry-run analysis
- `⌘.`: Mentés megszakítása / Cancel active backup

### 🌐 Bilingual Parity & String Localization / Kétnyelvű lokalizáció
- Replaced hardcoded replication strings in `MenuBarContentView` with localized tokens (`.menuBarReplicationRunning`, `.menuBarMoreProfilesFormat`).
- Localized Full Disk Access and Finder Extension card status descriptions in `SettingsView`.
- Replaced raw unit strings with `.unitCountFormat` and `.daysCountUnitFormat`.

---

## [1.5.0] - 2026-10-08 (Build 1500)

### 🌟 Release Summary / Verzióösszefoglaló
Version **1.5.0** introduces major modern data protection, verification, and comparison capabilities to OtterKeep:
- **Side-by-side file content diffing** between snapshots (Myers LCS algorithm for text, binary metadata comparison).
- **Silent background data scrubber** running with Darwin `.background` I/O QoS to detect bit-rot and silent corruption with native notifications.
- **WORM (Write Once, Read Many) immutability locking** with BSD `uchg` flags protecting snapshots from accidental deletion, ransomware, or premature pruning for configurable retention periods (default: 30 days).
- **Backblaze B2 Cloud Storage API support** as a native remote secondary backup target via S3-compatible endpoints.
- **Intelligent parallel multi-destination backup** allowing simultaneous CoW local and remote transfers with decoupled fault tolerance and background catch-up replication upon reconnection.
- **Dataless iCloud file change detection** eliminating unwanted cloud download triggers by strictly evaluating metadata.
- **Enhanced dual-tier logging** offering clear user-facing operational summaries alongside forensic verbose diagnostics.

---

### 🔍 Side-by-Side File Content Comparison / Egymás melletti fájlösszehasonlítás
- **Myers LCS Alignment**: Implemented `TextDiffEngine` computing line-by-line differences with side-by-side row alignment, additions/deletions counts, and modification markers.
- **Binary Signature Inspection**: Non-UTF8 files or files containing null bytes are safely handled as binary, displaying metadata diffs (file size, SHA-256 digests, modification timestamps) without garbling text views.
- **SwiftUI Modal & CLI Viewer**:
  - GUI: Added `SideBySideDiffModalView` with synchronized dual-column scrolling, syntax-aware line coloration, and line numbers.
  - CLI: Enhanced `otterkeep diff --profile <id> --file <rel_path> --side-by-side` with terminal column formatting.

### 🛡️ Silent Background Data Scrubber / Csendes háttérbeli adatintegritás-ellenőrző
- **Low-Priority Background Execution**: `DataScrubberEngine` operates using Swift Concurrency `Task(priority: .background)` (Darwin `QOS_CLASS_BACKGROUND`) with adaptive micro-sleep throttling (5ms default) and thermal-governance pausing.
- **Cryptographic Bit-Rot Auditing**: Periodically recomputes full SHA-256 hashes for all physical snapshot files and compares them against the SQLite snapshot catalog.
- **Audit History & Alerts**: Persists scan outcomes to SQLite (`scrub_audits` table) and delivers proactive macOS User Notifications upon detecting corrupted or tampered blocks.
- **CLI & GUI Access**: Run on-demand via `otterkeep scrub --profile <id> [--limit <n>]`.

### 🔒 WORM Immutability & Retention Immunity / WORM immutabilitás és törlésvédelem
- **BSD File Flag Locking**: Added `isFileImmutable` and `setImmutable` in `FileSystemProvider` using BSD `chflags(2)` (`UF_IMMUTABLE` / `SF_IMMUTABLE`).
- **Configurable Retention Duration**: Snapshots can be locked for a configured period (default: 30 days) stored in the database schema (`locked_until`).
- **Pruning Safety Immunity**: `RetentionManager` GFS rotation strictly protects locked snapshots from auto-pruning or manual deletion attempts, returning access denied errors until expiration.
- **CLI Management**: Added `otterkeep lock --profile <id> --snapshot <id> [--days <count>]` and `otterkeep unlock`.

### ☁️ Backblaze B2 Native Cloud Destination / Backblaze B2 felhőtárhely támogatás
- **B2 Configuration & Storage Provider**: Implemented `B2Configuration` and `B2StorageProvider` supporting Backblaze B2 application keys, automatic S3 region endpoint resolution (`s3.<region>.backblazeb2.com`), and bucket path prefixes.
- **3-2-1 Compliance Integration**: Fully integrated into `RemoteStorageFactory`, `BackupCopyJobCoordinator`, and `RestoreEngine`.
- **GUI Destination Editor**: Added dedicated Backblaze B2 configuration tile, credentials inputs, and live credential validation in `RemoteDestinationEditorModalView`.

### ⚡ Parallel Multi-Destination & Catch-Up Replication / Párhuzamos többcélpontos mentés és utólagos replikáció
- **Decoupled Failure Isolation**: Local APFS CoW snapshot creation succeeds even if secondary cloud/NAS destinations are offline or fail mid-flight.
- **Replication Catch-Up Coordinator**: Failed or offline secondary destinations queue tasks into the SQLite `pending_replications` table, which automatically catch up in the background once network connectivity is restored.
- **UI Settings Toggle**: Added `isParallelExecutionEnabled` toggle to Profile Copy Job settings.

### 🍏 Dataless iCloud Change Detection / Adat nélküli iCloud változásdetektálás
- **Zero-Download Verification**: Enhanced `ChangeDetector` to identify dataless/ubiquitous iCloud Drive files (`isDatalessICloud`) and verify them strictly by file size and modification timestamp.
- **Kernel Fault Prevention**: Completely eliminates inadvertent payload hashing or sampling that triggers forced iCloud file downloads during routine scans.

### 📝 Dual-Tier Diagnostic Logging / Kétszintű diagnosztikai naplózás
- **User-Facing High-Value Summaries**: Default log tier focuses on essential, human-friendly milestones (snapshot started, transfer speed, files scanned, immutability locked, scrub healthy).
- **Forensic Verbose Mode**: Activated via `--debug` or app preferences, outputting detailed per-file decisions, socket state changes, and cryptographic metrics to timestamped `.log` files.

### 🧪 System Test Suite Expansion (Module 11) / Rendszerteszt bővítés
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
