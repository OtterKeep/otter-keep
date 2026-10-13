# Build, Packaging & Release Protocols

This document details how to build, test, package, and publish releases of OtterKeep.

---

## 1. Prerequisites

- macOS 15.0 (Sequoia) or later
- Xcode 16.0+ with Command Line Tools
- Swift 6 toolchain

---

## 2. Compilation

Compile all targets in debug mode:
```bash
swift build
```

Run the integration test suite:
```bash
scripts/test.sh
```

Verify that every derived version literal matches `version.json`:
```bash
scripts/sync_version.sh --check
```

Synchronize them after a version bump:
```bash
scripts/sync_version.sh
```

---

## 3. Automated Release Packaging

OtterKeep provides an automated build and release packaging script:

```bash
./scripts/build_release.sh "1.4.0" release 1400
```

### Script Workflow
1. Verifies Git working tree state and branch conventions.
2. Compiles `OtterKeepApp` and `otterkeep-cli` with Release optimizations.
3. Builds the macOS application bundle `OtterKeep.app`.
4. Creates a compressed DMG archive: `.build/dist/OtterKeep-1.4.0.dmg`.
5. Computes cryptographic SHA-256 checksums.
6. Generates Sparkle 2.0 appcast entries.

> Version literals are derived from `version.json` (see `scripts/sync_version.sh`). Bump the
> manifest first, run the synchronization script, and commit the derived files together.
