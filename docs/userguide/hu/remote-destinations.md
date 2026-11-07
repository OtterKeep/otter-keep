# Távoli célállomások: SFTP, NAS és S3

Az OtterKeep a modern hálózati tároló-illesztők révén támogatja a titkosított biztonsági mentések tárolását hálózati adattárakon (NAS) és távoli szervereken is.

---

## 1. Hálózati adattárak (SMB / NFS / AFP)

Amennyiben helyi hálózatán Synology, QNAP, TrueNAS vagy macOS fájlszerver működik:

1. Csatolja a hálózati megosztást a Finderben (`Finder` → `Kapcsolódás szerverhez` vagy `Cmd + K`, pl. `smb://nas.local/backups`).
2. Nyissa meg az OtterKeepet és lépjen a **Profilok és szabályok** fülre.
3. A **Célállomás** résznél válassza ki a csatolt kötet útvonalát (pl. `/Volumes/backups/OtterKeep`).
4. **POSIX hardlink tartalék**: Amennyiben olyan megosztásra ment, amely nem támogatja az APFS Copy-on-Write funkciót, az OtterKeep automatikusan POSIX hardlinkekre vagy intelligens differenciális szinkronizálásra vált át a lemezterület kímélése érdekében.

---

## 2. Biztonságos SFTP fájlátvitel (SSH)

Dedikált Linux szerverek vagy távoli tárhelyek esetén:

- Protokoll: SFTP az SSH protokoll felett (alapértelmezett 22-es port).
- Hitelesítés:
  - **SSH privát kulcs** (Ajánlott): Ed25519 vagy RSA kulcsok a `~/.ssh/` mappából.
  - **Jelszavas hitelesítés**: Biztonságosan elmentve a macOS Kulcskarikájában (Keychain).
- **Biztonsági védelem**:
  - A parancssori paraméterek szigorúan árnyékoltak a parancsinjektálás ellen.
  - Szigorú gazdagép-kulcs ellenőrzés (StrictHostKeyChecking) védi az adatforgalmat a lehallgatás ellen.

---

## 3. S3-kompatibilis felhőtárhelyek és kliensoldali titkosítás

Amennyiben adatait Amazon S3, Cloudflare R2, Backblaze B2 vagy MinIO tárhelyre küldi:

### Nulla-ismeretű (Zero-Knowledge) titkosítás
Mielőtt bármilyen fájl vagy katalógusadat elhagyná a Mac gépet:
1. **Kulcslevezetés**: Az OtterKeep egy 256 bites AES titkosítási kulcsot hoz létre **PBKDF2-HMAC-SHA256** algoritmussal, **600 000 iterációs ciklussal** és egyedi titkosítási sóval.
2. **Hitelesített titkosítás**: A csomagokat **AES-256-GCM** borítékba zárja 128 bites ellenőrző kód kíséretében (`OKENC2` formátum).
3. **Nulla ismeret**: A felhőszolgáltató kizárólag titkosított bájtokat lát. Egy esetleges felhőoldali adatszivárgás esetén is az Ön adatai teljes biztonságban maradnak a mesterjelszó nélkül.
