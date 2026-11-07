# Security & Unified Logging Architecture

This document details security controls, cryptographic implementations, IPC protections, privacy-preserving observability, and data resilience invariants in OtterKeep v2.0.0.

---

## 1. Zero-Knowledge Cryptography (OKENC2)

Remote archives and cloud backups are encrypted client-side using **AES-256-GCM**:

### Key Derivation
- Key Derivation Function: **PBKDF2-HMAC-SHA256**
- Iteration Rounds: **600,000 rounds** (aligned with modern OWASP standards)
- Salt Size: **32 bytes** generated cryptographically via `SecRandomCopyBytes`
- Header Identifier: `OKENC2\0` (Modern) with automatic backward compatibility for legacy `DSENC2\0` and `DSENC1\0` blobs.

### Envelope Structure
```
[ 7 bytes Magic: "OKENC2\0" ]
[ 32 bytes Salt ]
[ 12 bytes AES-GCM Nonce ]
[ N bytes Ciphertext ]
[ 16 bytes Authentication Tag ]
```

---

## 2. Process Security & Local IPC

OtterKeep utilizes a hardened Unix Domain Socket architecture:
- **Socket Path**: `~/.otterkeep/gui.sock`
- **File Permissions**: `0600` (owner read/write only). The containing configuration and database folder `~/.otterkeep/` is set to `0700`.
- **Peer UID Verification**:
  ```c
  uid_t peerUID;
  gid_t peerGID;
  if (getpeereid(clientFD, &peerUID, &peerGID) == 0) {
      if (peerUID != geteuid()) {
          // Reject foreign local user
          close(clientFD);
      }
  }
  ```
- **Shell Argument Injection Neutralization**: Remote SFTP parameters and paths are sanitized against shell injection attacks.

---

## 3. Privacy-Preserving Unified Logging

To ensure diagnostic logs can be safely exported without leaking personal information, all telemetry passes through `LogPrivacySanitizer` and adheres to Apple platform standards:

### Standard Log Directory
- **Storage Path**: `~/Library/Logs/OtterKeep/` (standard macOS user log repository).
- **Log Files**: Daily rolling text logs (e.g., `otterkeep-2026-10-13.log`) formatted for native inspection with Console.app or CLI tools (`tail -f`).
- **Separation of Concerns**: State configuration and databases remain in `~/.otterkeep/`, keeping logs separated in the OS-managed directory.

### Redacted Elements
- **Usernames**: NSUserName and NSFullUserName replaced with `<USER>`.
- **Home Paths**: User home paths replaced with `<USER_HOME>`.
- **AWS Credentials**: `AKIA...` access keys replaced with `<AWS_ACCESS_KEY_ID>`.
- **Tokens & Passwords**: URL query parameters (`?token=...`) replaced with `<REDACTED>`.
- **Webhooks**: Slack and Discord webhook endpoints redacted.

### Preserved Diagnostic Context
- File extensions (`.pdf`, `.sqlite`, `.heic`)
- Error codes (`ENOENT`, `EACCES`, `ENOSPC`, `EIO`, `ENODEV`, `EROFS`)
- Snapshot IDs and ISO 8601 timestamps
- File sizes and transfer byte rates

---

## 4. Data Resilience & Atomic Recovery Invariants

OtterKeep enforces three key resilience invariants to protect user data from corruption during hardware or network failures:

### A. Volume Circuit Breaker
- When an I/O operation encounters volume detachment (`EIO`, `ENODEV`, `EROFS`) or disk exhaustion (`ENOSPC`), the `VolumeCircuitBreaker` triggers immediately.
- Pending queue processing is aborted, preventing CPU thrashing and unbounded log error spam.

### B. 100% Certainty Catalog Reconciliation
- Drives with unindexed snapshots undergo strict validation before registration:
  1. Non-empty directory structure.
  2. Snapshot completeness seal verification.
  3. No partial or corrupted stages accepted.

### C. 3-Phase Atomic Folder Restore with `.old` Safety Hold
- Restoring over an existing directory never deletes data in advance:
  1. **Phase 1 (Staging)**: Content is extracted to `.staging_<uuid>`.
  2. **Phase 2 (Hold)**: The existing target directory is renamed to `.old_<timestamp>`.
  3. **Phase 3 (Swap & Cleanup)**: Staging is renamed to the target directory. Only on confirmed success is `.old_<timestamp>` removed. Any failure immediately triggers rollback of `.old_<timestamp>` to the original target.
