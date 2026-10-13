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
scripts/test.sh --filter Module04Tests
scripts/test.sh --filter test4_3_RansomwareAnomalyGuard
```

`swift test` also works with a Command Line Tools-only toolchain — `XCTest` is not required. Note a
toolchain quirk: swift-testing expands `@Test`/`@Suite` through the `TestingMacros` compiler plugin,
and SwiftPM's build sandbox can rewrite the plugin-server path incorrectly on CLT-only installs,
producing `external macro implementation type 'TestingMacros…' could not be found`. `scripts/test.sh`
runs with `--disable-sandbox` and retries only that specific diagnostic, so real test failures are
still reported immediately.

---

## 2. The 12 Test Modules

| Module | Focus |
| :--- | :--- |
| **1. System, Version & SemVer** | Version/sub-system matrix consistency against `version.json`, SemVer parsing, Sparkle appcast audit |
| **2. APFS CoW & Storage Fidelity** | `clonefile(2)` block sharing, hardlink fallback, xattr preservation, atomic tree rename, driver registry |
| **3. SQLite Engine & Crash Consistency** | WAL pragmas, batch cataloging, diff engine, timeline queries, connection closure, cascading deletes |
| **4. Incremental Lifecycle & Change Detection** | GitIgnore glob parser, APFS nanosecond tolerances, ransomware guard, end-to-end backup/restore |
| **5. Client-Side Cryptography** | OKENC2 (600,000 PBKDF2 rounds), DSENC1 legacy compatibility, tamper resistance, SHA-256 calculators |
| **6. IPC & Process Security** | `AF_UNIX` buffer bounds, socket permissions (0600), `getpeereid` peer validation, message serialization |
| **7. Observability & Diagnostics** | `LogPrivacySanitizer` scrubbing, path masking, dual-tier diagnostics, debug file logger append |
| **8. Photos Backup & iCloud Eviction** | Export structures, metadata extraction, `EphemeralStorageGuard` buffering, coordinator initialization |
| **9. Bilingual Localization** | Key coverage of the unified string table, non-empty translations, format-specifier parity |
| **10. UI Design System & Error Recovery** | `OtterTheme` tokens, three-part error architecture, configuration archive serialization, multi-profile tracking |
| **11. Modern Capabilities** | Side-by-side text/binary diff, data scrubber bit-rot detection, WORM immutability, B2 provider, catch-up replication |
| **12. Backend Architecture & Layering** | Catalog services, compliance evaluation, layering invariants |

---

## 3. Adding a Test

1. Add the test to the module file that matches the subsystem (`Module04Tests.swift`, …).
2. Use a throwing `@Test` function (async when the code under test is async) and the shared
   assertion helpers.
3. Keep hermetic fixtures: create temporary directories with `createTempDirectory(prefix:)` and
   clean them up with `defer { removeTempDirectory(url) }`.
4. Avoid new version literals — load `VersionManifest` and assert against it.
5. Run `swift test --filter <Module>` before opening a pull request.

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
