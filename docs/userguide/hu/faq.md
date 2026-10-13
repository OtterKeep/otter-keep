# Gyakran Ismételt Kérdések (GYIK)

Válaszok a leggyakoribb kérdésekre az OtterKeep működésével, jogosultságaival, sebességével és lemezhasználatával kapcsolatban.

---

### K: Miben különbözik az OtterKeep az Apple Time Machine-tól?
**V:** A Time Machine a teljes macOS rendszert menti a teljes helyreállíthatóság céljából. Az OtterKeep az Ön személyes **digitális menedékére** fókuszál:
- Tiszta, natív fájlstruktúra: a célállomáson lévő fájlok hagyományos könyvtárak, amelyeket közvetlenül böngészhet Finderben vagy Terminálban speciális szoftver nélkül is.
- Rugalmas célállomások: helyi APFS kötetek, külső USB meghajtók, NAS megosztások, SFTP szerverek és S3 tárhelyek.
- Nulla-ismeretű kliensoldali titkosítás: a távoli szerverekre küldött adatok már a Macen titkosításra kerülnek.
- Részletesen testreszabható kizárási szabályok (GitIgnore szintaxis).

---

### K: Miért nem telik be a mentési meghajtó a sok pillanatkép ellenére?
**V:** Az OtterKeep az **APFS Copy-on-Write (`clonefile(2)`)** technológiát használja. Amikor egy változatlan fájl bekerül egy újabb mentésbe, a fájlrendszer mindössze egy új mutatót hoz létre a már lemezen lévő adatblokkokra. Az APFS csak akkor foglal el tényleges új tárhelyet, ha egy fájl tartalma valóban módosul.

---

### K: Miért szükséges a Teljes hozzáférés a lemezhez (Full Disk Access)?
**V:** A macOS TCC védelmi rendszere korlátozza a hozzáférést a személyes adatokhoz (Dokumentumok, Levelezés, Fotók). Ezen engedély nélkül az OtterKeep nem tudná megbízhatóan lementeni ezeket az állományokat. Kövesse az [Első lépések](getting-started.hu.md) útmutatót az engedélyezéshez.

---

### K: Biztonságosan leválaszthatom a külső meghajtót a mentés után?
**V:** **Igen!** Az OtterKeep a mentés végeztével azonnal lezárja az SQLite adatbázis-kapcsolatokat (`PRAGMA wal_checkpoint(TRUNCATE)`), elengedi az összes fájlleírót, így a külső meghajtó lecsatolása soha nem akad el „a lemez használatban van” típusú rendszerhibák miatt.

---

### K: Gyűjt az OtterKeep telemetriát vagy használati statisztikákat?
**V:** **Nem.** Az OtterKeep zéró külső nyomkövetést, telemetriát vagy felhős elemzést tartalmaz. A diagnosztikai naplók kizárólag az Ön Mac számítógépén maradnak (`~/.otterkeep/`), és a `LogPrivacySanitizer` automatikusan anonimizálja a felhasználóneveket, jelszavakat és magánjellegű fájlneveket.
