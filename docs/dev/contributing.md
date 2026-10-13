# Contributing to OtterKeep

We welcome contributions to OtterKeep! As a software project dedicated to data preservation, reliability and test verification are our highest priorities.

---

## 1. Core Principles

1. **Safety First**: Never perform destructive filesystem operations without affirmative verification.
2. **Swift 6 Concurrency**: Write strict actor-isolated, Sendable-safe Swift code. Avoid locks or `@unchecked Sendable` unless strictly required for C-interop.
3. **Bilingual Parity**: Any new user-facing string must be registered in the unified string table
   (`Sources/OtterKeepCore/Diagnostics/L10n+Strings.swift`) with both Hungarian and English text.
4. **Comprehensive Testing**: Any architectural enhancement must include corresponding test cases in
   `Tests/OtterKeepIntegrationTests` (the `OtterKeepIntegrationTests` target).
5. **Single Version Source**: Never hard-code a version. Bump `version.json` and run
   `scripts/sync_version.sh`; `CoreEngine`, the packaging scripts and `Distribution/appcast.xml`
   are derived from it and verified by `scripts/sync_version.sh --check`.

---

## 2. Development Workflow

1. Fork the repository and create a feature branch (`feature/your-feature-name` or `bugfix/issue-description`).
2. Implement your changes.
3. Ensure the test suite passes with 100% success rate:
   ```bash
   scripts/test.sh
   ```
4. Format the files you touched with the shared configuration:
   ```bash
   scripts/format.sh path/to/File.swift
   ```
5. Commit your changes using [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat(...)`: New feature
   - `fix(...)`: Bug fix
   - `chore(...)`: Maintenance or release
6. Open a Pull Request against the `release` or `develop` branch.
