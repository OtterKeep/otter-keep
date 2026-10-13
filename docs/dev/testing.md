# Testing Standards & Verification Suite

This document describes the test architecture, the integration modules, and the verification
workflow of OtterKeep.

---

## 1. Test Architecture

OtterKeep tests are a **`swift-testing`** suite that lives in the dedicated test target
`OtterKeepIntegrationTests` (`Tests/OtterKeepIntegrationTests`).

The suite replaced the legacy hand-rolled `OtterKeepTestRunner` executable in favour of a standard
harness, which brings per-test isolation, filtering, structured reporting, and `swift test` CI
integration:

- `@Suite(.serialized)` per module — the modules mutate process-wide singletons
  (`ProfileStore`, `LogManager`, `LocalizationManager`, sockets) and fixed paths, so they run
  serially.
- Throwing assertion helpers (`assertTrue`, `assertEqual`, `assertNil`, `require`, …) live in
  `Support/AssertionFramework.swift` and throw `TestFailure` with `#file`/`#line` context.
- `Support/TemporaryDirectoryFixtures.swift` provides deterministic temporary-directory fixtures
  (`createTempDirectory`, `removeTempDirectory`).
- `Support/VersionManifest.swift` reads `version.json`, so version expectations are asserted by
  consistency instead of duplicated literals.

### Running the Test Suite

```bash
# Whole suite, sequentially (the wrapper CI and developers use)
scripts/test.sh

# Release configuration, as CI runs it
scripts/test.sh -c release

# A single module or test (arguments are forwarded to `swift test`)
scripts/test.sh --filter BackupPipelineTests
scripts/test.sh --filter testRansomwareAnomalyGuard
```

`swift test` also works with a Command Line Tools-only toolchain — `XCTest` is not required. Note a
toolchain quirk: swift-testing expands `@Test`/`@Suite` through the `TestingMacros` compiler plugin,
and SwiftPM's build sandbox can rewrite the plugin-server path incorrectly on CLT-only installs,
producing `external macro implementation type 'TestingMacros…' could not be found`. `scripts/test.sh`
runs with `--disable-sandbox` and retries only that specific diagnostic, so real test failures are
still reported immediately.

---

## 2. The 12 Semantic Test Suites

| Test Suite File | Subsystem & Focus |
| :--- | :--- |
| **`SystemVersionIntegrityTests.swift`** | Version/subsystem matrix consistency against `version.json`, SemVer parsing, Sparkle appcast audit |
| **`StorageEngineTests.swift`** | APFS `clonefile(2)` block sharing, hardlink fallback, xattr preservation, atomic tree rename, driver registry, B2 configuration |
| **`DatabaseEngineTests.swift`** | SQLite manifest WAL pragmas, batch cataloging, diff engine, timeline queries, connection closure, cascading deletes, text diff, offline inspection |
| **`BackupPipelineTests.swift`** | Incremental backup lifecycle, GitIgnore glob parser, APFS nanosecond tolerances, ransomware guard, end-to-end backup/restore, WORM immutability, dataless iCloud, catalog services |
| **`SecurityCryptographyTests.swift`** | OKENC2 (600,000 PBKDF2 rounds), DSENC1 legacy compatibility, tamper resistance, SHA-256 calculators, data scrubber bit-rot detection |
| **`IPCProcessSecurityTests.swift`** | `AF_UNIX` buffer bounds, socket permissions (0700), peer credential validation, message serialization, SFTP injection defense |
| **`DiagnosticsLoggingTests.swift`** | `LogPrivacySanitizer` scrubbing, path masking, dual-tier diagnostics, debug file logger append, native Apple `~/Library/Logs/OtterKeep` directory |
| **`PhotosProtectionTests.swift`** | Export structures, metadata extraction, `EphemeralStorageGuard` buffering, coordinator initialization |
| **`LocalizationTests.swift`** | Unified string table bilingual parity (English / Hungarian), non-empty translations, format-specifier safety, localized suffix formatting |
| **`PresentationUITests.swift`** | `OtterTheme` tokens, three-part error architecture, configuration archive serialization, multi-profile tracking, settings side-effect propagation |
| **`ReplicationAndComplianceTests.swift`** | 3-2-1 compliance evaluator rules, offsite remote copy jobs, catch-up replication coordination |
| **`CleanArchitectureTests.swift`** | Pure Domain entities, Repository Ports & Adapters, DTO mappings across boundaries, Use Cases, CentralDatabase profiles & JSON export/import |

---

## 3. Adding a Test

1. Add the test to the module file that matches the subsystem (`BackupPipelineTests.swift`, …).
2. Use a throwing `@Test` function (async when the code under test is async) and the shared
   assertion helpers.
3. Keep hermetic fixtures: create temporary directories with `createTempDirectory(prefix:)` and
   clean them up with `defer { removeTempDirectory(url) }`.
4. Avoid new version literals — load `VersionManifest` and assert against it.
5. Run `scripts/test.sh --filter <SuiteName>` before opening a pull request.

---

## 4. CI Verification

`.github/workflows/ci.yml` runs:

```bash
swift build -c release
scripts/sync_version.sh --check
scripts/test.sh -c release
scripts/format.sh --lint   # advisory: reports the pre-existing style backlog
```

A release is only published when the integration suite reports zero failures.
