# OtterKeep 🦦

> **The Serene Guardian for Your macOS Digital Sanctuary**  
> *Lightning-fast, whisper-quiet incremental backups powered by native APFS Copy-on-Write and modern Swift 6.*

[![macOS](https://img.shields.io/badge/macOS-15.0%2B%20%28Sequoia%29-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Version](https://img.shields.io/badge/version-1.7.1-emerald.svg)](https://github.com/richardeszeshu/otter-keep/releases)
[![Build](https://img.shields.io/badge/build-1701-cyan.svg)](https://github.com/richardeszeshu/otter-keep)
[![Tests](https://img.shields.io/badge/tests-61%2F61%20passed-brightgreen.svg)](https://github.com/richardeszeshu/otter-keep)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)
[![Hungarian](https://img.shields.io/badge/Magyar%20nyelv-README.hu.md-red.svg)](README.hu.md)

---

## Overview

> 🌊 **The Story of OtterKeep (Brand Lore)**  
> Sea otters have an extraordinary, instinctive ritual: throughout their entire lives, they carry their most prized favorite pebble tucked securely into a hidden pocket of skin beneath their forearms. They use it to open shells, play with it on the waves, and never let it go under any circumstances.  
>  
> **OtterKeep** protects the files, historical snapshots, and precious memories on your Mac with that exact same tender vigilance and devotion.

**OtterKeep** is an open-source, human-centric backup and recovery solution engineered exclusively for modern macOS. Designed around **Ollie the Otter**—the calm guardian who meticulously collects and preserves treasures in an underwater pouch—OtterKeep treats your files as cherished memories that deserve lifelong sanctuary.

Unlike traditional backup utilities that trigger thermal throttling, battery drain, and unmount locks, OtterKeep leverages Apple's native **APFS Copy-on-Write (`clonefile`)** primitives to create instantaneous, differential filesystem snapshots with **zero additional storage overhead** until files change.

---

## Key Highlights

- ⚡ **Near-Zero Byte Duplication**: Leverages APFS Copy-on-Write (`clonefile(2)`) so duplicate and unchanged files consume zero extra blocks on APFS destinations.
- 🧭 **Sanctuary Experience & Profile State Harmony**: Native macOS HIG-compliant multi-profile UI with instant per-profile last backup status awareness, reactivated vertical Time Machine timeline browsing, and native keyboard shortcuts (`⌘1`, `⌘2`, `⌘3`, `⌘B`, `⌘D`).
- 🔍 **Side-by-Side Snapshot Diffing**: Aligned dual-column file comparison with Myers LCS text diffing and binary inspection directly in GUI and CLI.
- 🛡️ **Silent Background Data Scrubber**: Whisper-quiet background process (`I/O QoS: .background`) continually re-verifying SHA-256 hashes against silent bit-rot.
- 🔒 **WORM Immutability Locking**: Hardware/BSD-enforced `uchg` flags protect snapshots from deletion or ransomware for configurable retention periods (30 days default).
- ☁️ **Backblaze B2 Cloud Integration**: Native Backblaze B2 S3-compatible cloud storage destination.
- ⚡ **Parallel Multi-Destination & Catch-Up**: Simultaneous APFS CoW local and remote replication with offline tolerance and automated background catch-up.
- 🍏 **Dataless iCloud Change Detection**: Detects modified iCloud files purely from file size and mtime without triggering unwanted downloads.
- 🔒 **Zero-Knowledge Privacy & Client Encryption**: Client-side AES-256-GCM encryption with PBKDF2-HMAC-SHA256 key derivation (600,000 rounds) protects remote archives before transmission.
- 🪶 **Whisper-Quiet Efficiency**: Strict cooperative concurrency (`Task.yield()`), I/O throttling, QoS scheduling, and macOS power state awareness eliminate fan noise and thermal spikes.
- 🛡️ **Ransomware & Anomaly Shield**: Analyzes differential change ratios and mass extension changes before committing snapshots, shielding against mass file corruption.
- 📸 **Apple Photos Sanctuary**: Native PhotoKit integration with differential asset scanning, live metadata sidecar generation (EXIF/IPTC/GPS to XMP), and ephemeral cache rate-limiting.
- 🔌 **Safe Drive Management**: Explicit SQLite database closure (`PRAGMA wal_checkpoint(TRUNCATE)`) and connection release prevents external drive unmount locks during volume ejection.
- 🇭🇺 **100% Native Bilingual Parity**: Fully localized in English and Hungarian across every interface screen, CLI command, and documentation guide.

---

## Architectural Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    OtterKeep User Surface                   │
│      SwiftUI Menu Bar Extra  •  Window  •  CLI Engine       │
└──────────────────────────────┬──────────────────────────────┘
                               │
            Unix Domain Socket │ (AF_UNIX / Single Instance)
            Peer UID Validated │ (getpeereid 0600 socket)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                       OtterKeepCore                         │
│  ┌───────────────────────┐       ┌───────────────────────┐  │
│  │ BackupSession         │       │ RestoreEngine         │  │
│  │ Coordinator           │       │ Safe Collision Avoid. │  │
│  └───────────┬───────────┘       └───────────┬───────────┘  │
│              │                               │              │
│  ┌───────────▼───────────┐       ┌───────────▼───────────┐  │
│  │ Differential Scanner  │       │ Ransomware Anomaly    │  │
│  │ GitIgnore Rule Engine │       │ Detection Guard       │  │
│  └───────────────────────┘       └───────────────────────┘  │
└──────────────┬───────────────────────────────┬──────────────┘
               │                               │
               ▼                               ▼
┌─────────────────────────────┐ ┌─────────────────────────────┐
│      OtterKeepDatabase      │ │      OtterKeepStorage       │
│  SQLite WAL Mode            │ │  APFS CoW (clonefile)       │
│  Batch File Cataloging      │ │  POSIX Hardlinks Fallback   │
│  Timeline & Full-Text Search│ │  SFTP & S3 Adapters         │
└─────────────────────────────┘ └─────────────────────────────┘
```

---

## Installation & Quick Start

### Homebrew Tap (Recommended)

```bash
brew tap richardeszeshu/otter-keep
brew install --cask otterkeep
```

### Direct Download

Download the signed and notarized `.dmg` or `.zip` package from the [Releases](https://github.com/richardeszeshu/otter-keep/releases) page. Mount the DMG and drag `OtterKeep.app` to your `/Applications` directory.

### CLI Setup

OtterKeep includes a fully standalone command-line executable `otterkeep-cli`:

```bash
# Verify installation
otterkeep-cli version

# Run a dry-run backup session
otterkeep-cli backup run --dry-run

# Inspect snapshot catalog
otterkeep-cli snapshots list
```

---

## Documentation Index

Explore our comprehensive technical and user documentation:

### User Guides (`docs/userguide/en/`)
- [**Getting Started**](docs/userguide/en/getting-started.md) — First-time setup, permissions (Full Disk Access), and quick configuration.
- [**Backup & Restore**](docs/userguide/en/backup-and-restore.md) — Differential backup flows, snapshot browsing, and safe file restoration.
- [**Remote Destinations**](docs/userguide/en/remote-destinations.md) — Configuring SFTP, NAS volumes, and S3-compatible cloud storage.
- [**Photos Protection**](docs/userguide/en/photos-protection.md) — Apple Photos library backup, XMP sidecars, and iCloud eviction safeguards.
- [**Frequently Asked Questions (FAQ)**](docs/userguide/en/faq.md) — Common questions, troubleshooting, and disk space management.

### Developer Guides (`docs/dev/`)
- [**Architecture Blueprint**](docs/dev/architecture.md) — Actor isolation, multi-subsystem topology, and concurrency models.
- [**Storage Engine & Filesystem Fidelity**](docs/dev/storage-engine.md) — APFS `clonefile(2)`, POSIX fallbacks, and metadata preservation.
- [**Database Design & Cataloging**](docs/dev/database-design.md) — SQLite schema, WAL mode, timeline queries, and batch indexing.
- [**Security & Unified Logging**](docs/dev/security-and-logging.md) — IPC peer validation, AES-256-GCM encryption, and log sanitization.
- [**Testing Standards & Verification**](docs/dev/testing.md) — 10-module integration test suite, fault injection, and verification benchmarks.
- [**CLI Reference**](docs/dev/cli-reference.md) — Complete manual for commands, options, and shell integration.
- [**Build & Release Protocols**](docs/dev/build-and-packaging.md) — Compiling, DMG generation, notarization, and Sparkle appcasts.
- [**Contributing Guidelines**](docs/dev/contributing.md) — Coding conventions, Git release flow, and PR checklist.

---

## Community & Philosophy

OtterKeep is built on three core pillars:
1. **Sanctuary Over Storage**: Backups should not feel like an onerous IT chore. They should evoke feelings of warmth, safety, and reassurance.
2. **Apple Silicon Harmony**: Modern Macs are powerful yet energy-conscious. Our software honors your battery and hardware by running unobtrusively.
3. **Absolute Transparency**: Zero telemetry, zero cloud lock-in, open-source code, and native open file formats.

---

## License

OtterKeep is licensed under the permissive [MIT License](LICENSE).
