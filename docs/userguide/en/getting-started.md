# Getting Started with OtterKeep

> *„Keep what you love close to your chest.”*  
> Sea otters carry their favorite pebble in a pocket under their arm their whole life, never letting it go. OtterKeep brings that same tender vigilance to protecting your Mac.

Welcome to **OtterKeep**! This guide walks you through downloading, installing, configuring permissions, and running your very first backup.

---

## 1. System Requirements

- **macOS Sequoia (15.0)** or later.
- Apple Silicon (M1/M2/M3/M4) or Intel 64-bit Mac.
- File system: **APFS** formatted internal disk and backup destination (recommended for instant Copy-on-Write snapshots).

---

## 2. Installation

### Option A: Homebrew Tap (Recommended)
```bash
brew tap richardeszeshu/otter-keep
brew install --cask otterkeep
```

### Option B: Direct Disk Image (.dmg)
1. Download the latest `OtterKeep-1.4.0.dmg` from the [Releases](https://github.com/richardeszeshu/otter-keep/releases) page.
2. Double-click the DMG to open it.
3. Drag **OtterKeep.app** into your `/Applications` folder.
4. Launch OtterKeep from Launchpad or Spotlight.

---

## 3. Granting Full Disk Access (FDA)

macOS safeguards your personal files (such as Documents, Mail, Photos, and Safari data) using the Transparency, Consent, and Control (TCC) subsystem. For OtterKeep to reliably protect these directories, it requires **Full Disk Access**:

1. Open **System Settings** on your Mac.
2. Navigate to **Privacy & Security** → **Full Disk Access**.
3. Click the **+** button (or authenticate with Touch ID / password).
4. Select `OtterKeep.app` from `/Applications`.
5. Ensure the switch is toggled **ON**.

> [!NOTE]
> If you are also using the command-line interface, ensure your terminal emulator (e.g., Terminal, iTerm2, or Ghostty) has Full Disk Access enabled.

---

## 4. Your First Backup in 3 Steps

1. **Select Source Folders**:
   By default, OtterKeep offers a pre-configured profile protecting your home directory (`~`), excluding temporary caches (`~/Library/Caches`) and build artifacts. You can add or remove custom folders under **Profile & Rules**.

2. **Select Destination**:
   Choose an external APFS drive, a secondary APFS volume, or a dedicated backup folder on your network.

3. **Click Start Backup**:
   Click the **Start Backup** button in the menu bar popover or main window. OtterKeep creates an initial baseline snapshot and displays real-time progress without slowing down your computer.

---

## 5. Next Steps

- [Backup & Restore Guide](backup-and-restore.md) — Learn how to browse snapshot timelines and restore files.
- [Remote Destinations](remote-destinations.md) — Set up network attached storage (NAS) or SFTP destinations.
- [Photos Protection](photos-protection.md) — Protect your Apple Photos library.
