# Remote Destinations: SFTP, NAS & S3

OtterKeep supports storing encrypted backups across network attached storage (NAS) and remote servers using modern network storage adapters.

---

## 1. Network Attached Storage (SMB / NFS / AFP)

If your local network includes a Synology, QNAP, TrueNAS, or macOS file server:

1. Mount the network share in Finder (`Finder` → `Connect to Server` or `Cmd + K`, e.g. `smb://nas.local/backups`).
2. Open OtterKeep and navigate to **Profile & Rules**.
3. Under **Destination**, select the mounted volume path (e.g. `/Volumes/backups/OtterKeep`).
4. **POSIX Hardlink Fallback**: When saving to an SMB/NFS share (which lacks APFS Copy-on-Write support), OtterKeep seamlessly falls back to POSIX hardlinks or intelligent differential file syncing to conserve disk bandwidth.

---

## 2. Secure Shell File Transfer (SFTP)

For dedicated Linux servers or offsite storage hosts:

- Protocol: SFTP over SSH (Port 22 by default).
- Authentication:
  - **SSH Private Key** (Recommended): Ed25519 or RSA keys stored in `~/.ssh/`.
  - **Password Authentication**: Persisted securely in the macOS Keychain.
- **Security Features**:
  - Arguments are shell-escaped to prevent command injection.
  - Strict host key checking verifies server identity.
  - Connections are verified before the backup begins.

---

## 3. S3-Compatible Cloud Storage & Client Encryption

When streaming backups to Amazon S3, Cloudflare R2, Backblaze B2, or MinIO:

### Zero-Knowledge Cryptography
Before any file or metadata record leaves your Mac:
1. **Key Derivation**: OtterKeep derives a 256-bit AES encryption key using **PBKDF2-HMAC-SHA256** with **600,000 iterations** and a unique cryptographic salt.
2. **Authenticated Encryption**: Payloads are sealed into authenticated envelopes using **AES-256-GCM** with 128-bit authentication tags (`OKENC2` format).
3. **Zero Knowledge**: The remote cloud provider receives only encrypted ciphertext blobs. Even in the event of a cloud server breach, your files remain completely inaccessible without your master passphrase.
