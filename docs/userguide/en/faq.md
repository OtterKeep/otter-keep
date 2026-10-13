# Frequently Asked Questions (FAQ)

Find answers to common questions regarding OtterKeep's architecture, permissions, performance, and disk usage.

---

### Q: How is OtterKeep different from Apple Time Machine?
**A:** Time Machine creates whole-system local and network backups designed for complete OS recovery. OtterKeep is focused on your personal **data sanctuary**:
- Pure file-level visibility: files in your destination are regular directories you can browse natively in Finder or Terminal.
- Multi-destination flexibility: supports local APFS volumes, external USB drives, NAS shares, SFTP servers, and S3 buckets.
- Zero-knowledge encryption: protects files on remote storage before transmission.
- Granular exclude rules with GitIgnore-compatible pattern matching.

---

### Q: Why does my backup drive not run out of space with multiple snapshots?
**A:** OtterKeep uses **APFS Copy-on-Write (`clonefile(2)`)**. When an unchanged file is included in a new snapshot, the filesystem simply creates a new directory entry pointing to the exact same data blocks on disk. Only when you modify a file does APFS allocate new blocks for the changes.

---

### Q: Why do I get a warning that Full Disk Access is required?
**A:** macOS limits app access to protected user directories (such as Documents, Mail, and Messages) through TCC. Without Full Disk Access, OtterKeep cannot read or protect these files. Follow our [Getting Started Guide](getting-started.md) to enable it.

---

### Q: Can I safely unplug my external drive after a backup?
**A:** **Yes!** Unlike other tools that hold SQLite database handles open, OtterKeep explicitly checkpoints and closes its database (`PRAGMA wal_checkpoint(TRUNCATE)`) and frees all active file locks immediately after backup completion. You can safely eject your disk via Finder or let OtterKeep auto-eject it for you.

---

### Q: Does OtterKeep collect telemetry or crash reports?
**A:** **No.** OtterKeep contains zero remote tracking, telemetry, or third-party analytics. Diagnostic logs are stored strictly on your local Mac (`~/.otterkeep/`) and scrub all usernames, passwords, tokens, and personal filenames using `LogPrivacySanitizer`.
