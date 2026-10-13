# OtterKeep 🦦

> **A macOS digitális menedékének derűs és megbízható őre**  
> *Villámgyors, suttogóan csendes növekményes biztonsági mentések natív APFS Copy-on-Write technológiával és modern Swift 6 alapon.*

[![macOS](https://img.shields.io/badge/macOS-15.0%2B%20%28Sequoia%29-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Verzió](https://img.shields.io/badge/verzi%C3%B3-1.7.1-emerald.svg)](https://github.com/richardeszeshu/otter-keep/releases)
[![Build](https://img.shields.io/badge/build-1701-cyan.svg)](https://github.com/richardeszeshu/otter-keep)
[![Tesztek](https://img.shields.io/badge/tesztek-61%2F61%20sikeres-brightgreen.svg)](https://github.com/richardeszeshu/otter-keep)
[![Licenc](https://img.shields.io/badge/licenc-MIT-lightgrey.svg)](LICENSE)
[![English](https://img.shields.io/badge/English-README.md-blue.svg)](README.md)

---

## Áttekintés

> 🌊 **Az OtterKeep története (Márkafilozófia)**  
> A tengeri vidráknak van egy különleges, ösztönös szokásuk: egész életükön át magukkal hordják kedvenc, legféltettebb kavicsukat, amelyet a mellső lábuk alatti apró bőrzsebben őriznek. Ezzel nyitják fel a kagylókat, ezzel játszanak a hullámok hátán ringatózva, és **semmilyen körülmények között sem engedik el**.  
>  
> Az **OtterKeep** pontosan ezzel a gondoskodó éberséggel, odaadással és ragaszkodással őrzi a Macjén található fájlokat, történeti pillanatképeket és féltett emlékeket.

Az **OtterKeep** egy nyílt forráskódú, emberközpontú biztonsági mentési és adat-visszaállítási megoldás, amelyet kifejezetten a modern macOS operációs rendszerhez terveztünk. A rendszer szimbóluma **Ollie, a vidra** – a nyugodt védelmező, aki víz alatti kis erszényében gondosan gyűjti és őrzi legféltettebb kincseit. Az OtterKeep az Ön fájljaira és fotóira nem egyszerű adathalmazként, hanem megőrzendő emlékekként és értékekként tekint.

A hagyományos, ventillátorzajt keltő és akkumulátort merítő mentőszoftverekkel szemben az OtterKeep az Apple natív **APFS Copy-on-Write (`clonefile`)** mechanizmusára épül, így azonnali, differenciális pillanatképeket hoz létre **plusz tárhelyfoglalás nélkül**, amíg a fájlok tartalma meg nem változik.

---

## Főbb jellemzők

- ⚡ **Nulla bájt duplikáció**: Az APFS Copy-on-Write (`clonefile(2)`) révén a változatlan fájlok semennyi extra lemezterületet nem foglalnak az APFS célköteten.
- 🧭 **Menedék élmény és profilállapot-megőrzés**: Natív macOS HIG felhasználói felület, profilok közötti váltáskor azonnali utolsó mentési állapotkijelzéssel, felélesztett Időgép idővonal-böngészéssel és gyorsbillentyűkkel (`⌘1`, `⌘2`, `⌘3`, `⌘B`, `⌘D`).
- 🔍 **Egymás melletti fájl-differencia**: Grafikus és parancssori összehasonlítás Myers LCS algoritmussal és bináris metaadat-vizsgálóval két pillanatkép között.
- 🛡️ **Csendes háttérbeli adatintegritás-ellenőrző**: Folyamatos, alacsony prioritású (`I/O QoS: .background`) SHA-256 hash újraszámolás és bit-rot riasztás.
- 🔒 **WORM immutabilitási zárolás**: BSD `uchg` hardveres/fájlrendszeri zárolás védi a pillanatképeket a zsarolóvírusoktól és a törléstől beállítható ideig (alapértelmezett 30 nap).
- ☁️ **Backblaze B2 felhőtárhely**: Natív S3-kompatibilis B2 integráció távoli felhős másodlagos mentési célpontként.
- ⚡ **Párhuzamos többcélpontos mentés**: Egyidejű helyi APFS CoW és felhő/NAS másolás hibatűréssel és automatikus háttérbeli pótlólagos szinkronizációval.
- 🍏 **Adat nélküli iCloud változásdetektálás**: A felhőben tárolt fájlok változásait pusztán méret és mtime alapján detektálja felesleges letöltések nélkül.
- 🔒 **Kliensoldali nulla-ismeretű titkosítás**: AES-256-GCM titkosítás PBKDF2-HMAC-SHA256 kulcslevezetéssel (600 000 ciklus) védi a távoli szerverekre küldött archívumokat még az átvitel előtt.
- 🪶 **Suttogóan csendes működés**: Kooperatív párhuzamosság (`Task.yield()`), intelligens I/O ütemezés, alacsony QoS prioritás és energiagazdálkodási felügyelet gátolja meg a Mac felmelegedését.
- 🛡️ **Zsarolóvírus- és anomáliavédelem**: Elemzi a módosulási arányokat és a tömeges kiterjesztés-változásokat, így meggátolja a sérült vagy titkosított fájlok rögzítését.
- 📸 **Apple Fotók menedéke**: Natív PhotoKit integráció, differenciális média-szkennelés, metaadatok (EXIF/IPTC/GPS) exportálása XMP kísérőfájlokba, és tárhelyvédő átmeneti puffer.
- 🔌 **Biztonságos meghajtóleválasztás**: Az SQLite adatbázisok explicit lezárása (`PRAGMA wal_checkpoint(TRUNCATE)`) garantálja, hogy a külső meghajtók azonnal és akadálytalanul lecsatolhatók legyenek.
- 🇭🇺 **100%-os anyanyelvi lokalizáció**: Teljes kétnyelvű párhuzamosság magyar és angol nyelven minden felületen, hibaüzenetben és dokumentációban.

---

## Rendszerarchitektúra

```
┌─────────────────────────────────────────────────────────────┐
│                    OtterKeep Felhasználói Felület           │
│      SwiftUI Menüsor Extra  •  Főablak  •  CLI Motor        │
└──────────────────────────────┬──────────────────────────────┘
                               │
            Unix Domain Socket │ (AF_UNIX / Egyetlen példány)
            Peer UID Ellenőrzés│ (getpeereid 0600 socket)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                       OtterKeepCore                         │
│  ┌───────────────────────┐       ┌───────────────────────┐  │
│  │ BackupSession         │       │ RestoreEngine         │  │
│  │ Coordinator           │       │ Ütközésmentes Vissza. │  │
│  └───────────┬───────────┘       └───────────┬───────────┘  │
│              │                               │              │
│  ┌───────────▼───────────┐       ┌───────────▼───────────┐  │
│  │ Differenciális Motor  │       │ Zsarolóvírus &        │  │
│  │ GitIgnore Szabályok   │       │ Anomália Detektor     │  │
│  └───────────────────────┘       └───────────────────────┘  │
└──────────────┬───────────────────────────────┬──────────────┘
               │                               │
               ▼                               ▼
┌─────────────────────────────┐ ┌─────────────────────────────┐
│      OtterKeepDatabase      │ │      OtterKeepStorage       │
│  SQLite WAL Üzemmód         │ │  APFS CoW (clonefile)       │
│  Kötegelt Fájlkatalógus     │ │  POSIX Hardlink Tartalék    │
│  Idővonal & Globális Kereső │ │  SFTP & S3 Illesztők        │
└─────────────────────────────┘ └─────────────────────────────┘
```

---

## Telepítés és gyorsindítás

### Homebrew Tap (Ajánlott)

```bash
brew tap richardeszeshu/otter-keep
brew install --cask otterkeep
```

### Közvetlen letöltés

Töltse le az aláírt és hitelesített `.dmg` csomagot a [Kiadások (Releases)](https://github.com/richardeszeshu/otter-keep/releases) oldalról. Csatolja a lemezképet, majd húzza az `OtterKeep.app` ikont az `Alkalmazások` (Applications) mappába.

### Parancssori felület (CLI)

Az OtterKeep önálló parancssori eszközt is biztosít (`otterkeep-cli`):

```bash
# Verzió lekérdezése
otterkeep-cli version

# Próbamentés futtatása (fájlmódosítás nélkül)
otterkeep-cli backup run --dry-run

# Pillanatképek listázása
otterkeep-cli snapshots list
```

---

## Dokumentációs index

Részletes felhasználói és fejlesztői dokumentációink:

### Felhasználói kézikönyvek (`docs/userguide/`)
- [**Első lépések**](docs/userguide/getting-started.hu.md) — Beállítás, jogosultságok (Teljes hozzáférés a lemezhez / Full Disk Access) és gyorsindítás.
- [**Mentés és visszaállítás**](docs/userguide/backup-and-restore.hu.md) — Pillanatképek készítése, verziók böngészése és biztonságos helyreállítás.
- [**Távoli célállomások**](docs/userguide/remote-destinations.hu.md) — SFTP, hálózati NAS meghajtók és S3 felhőtárhelyek beállítása.
- [**Fotók védelme**](docs/userguide/photos-protection.hu.md) — Apple Fotókönyvtár mentése, XMP kísérőfájlok és az iCloud tárhelyvédelmi funkciók.
- [**Gyakran Ismételt Kérdések (GYIK)**](docs/userguide/faq.hu.md) — Gyakori kérdések, hibaelhárítás és tárhelygazdálkodás.

### Fejlesztői útmutatók (`docs/dev/`)
- [**Architektúra áttekintés**](docs/dev/architecture.md) — Aktorok, alrendszerek és aszinkron Swift 6 modell.
- [**Tárolómotor és fájlrendszer**](docs/dev/storage-engine.md) — APFS `clonefile(2)`, POSIX hardlinkek és metaadat-megőrzés.
- [**Adatbázis-architektúra**](docs/dev/database-design.md) — SQLite WAL mód, idővonalak és kötegelt indexelés.
- [**Biztonság és egységes naplózás**](docs/dev/security-and-logging.md) — IPC auditálás, AES-256 titkosítás és anonimizált diagnosztika.
- [**Tesztszabályzat és minőségbiztosítás**](docs/dev/testing.md) — 10 modulos integrációs tesztcsomag és terheléstesztek.
- [**CLI referencia**](docs/dev/cli-reference.md) — Parancsok, kapcsolók és terminálos integráció.
- [**Build és kiadási protokoll**](docs/dev/build-and-packaging.md) — Fordítás, DMG csomagolás, aláírás és Sparkle appcast.
- [**Közreműködői útmutató**](docs/dev/contributing.md) — Kódolási konvenciók, Git munkafolyamat és ellenőrzőlista.

---

## Licenc

Az OtterKeep nyílt forráskódú szoftver a megengedő [MIT Licenc](LICENSE) feltételei szerint.
