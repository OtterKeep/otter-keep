# Apple Photos Protection Guide

OtterKeep provides dedicated, native backup capabilities for the Apple Photos library (`Photos.photoslibrary`), protecting your original raw captures, edited variations, and Live Photos without risk of data loss.

---

## 1. Why Apple Photos Requires Special Handling

A typical Apple Photos library is not just a collection of files—it is a complex bundle containing SQLite databases, proprietary derivative images, thumbnail caches, and cloud-synced assets managed by **iCloud Photos (Optimize Mac Storage)**.

Traditional file copy tools often fail because:
1. Low-resolution thumbnails are backed up instead of full-resolution originals.
2. Cloud-evicted assets trigger unhandled download errors.
3. Rapid batch downloading can exhaust all remaining space on your local SSD.
4. Album arrangements, favorites, and geolocation tags are lost.

---

## 2. OtterKeep's Photos Architecture

OtterKeep interfaces directly with macOS PhotoKit and filesystem layers:

- **Differential Scanner (`PhotosDeltaScanner`)**: Queries newly created and updated photos, identifying changes without re-reading gigabytes of unchanged files.
- **Sidecar Metadata Extraction (`PhotoMetadataExtractor`)**: Automatically extracts creation dates, GPS coordinates, favorite tags, and user album memberships into standard Adobe **XMP sidecar files** (`.xmp`), ensuring vendor neutrality.
- **Live Photos & RAW Pairs**: Backs up paired video files (`.mov`) and twin RAW+JPEG exposures together.
- **Rate-Limited Ephemeral Buffer (`EphemeralStorageGuard`)**: Downloads cloud-evicted originals into a strictly bounded scratch buffer (default: 512 MB). Once an asset is securely cloned to the backup destination, it is immediately evicted from the scratch cache, preventing local disk saturation.

---

## 3. Directory Layout Schemes

Under **Profile & Rules → Photos Settings**, choose your preferred layout on disk:

1. **Date Hierarchy (`dateHierarchy`)** (Default):
   `Originals/2026/10/IMG_0412.HEIC` + `IMG_0412.xmp`
2. **Album Hierarchy (`albumHierarchy`)**:
   `Originals/Albums/Summer Vacations/IMG_0412.HEIC`
3. **Flat Directory (`flat`)**:
   `Originals/IMG_0412_UUID.HEIC`
