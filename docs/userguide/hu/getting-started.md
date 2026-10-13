# Első lépések az OtterKeep használatával

> *„Őrizd a legfontosabb kincseidet biztos kezekben.”*  
> A tengeri vidrák egész életükben a mellső lábuk alatti apró bőrzsebben őrzik legkedvesebb kavicsukat, és soha nem engedik el. Az OtterKeep ugyanezzel a féltő gondoskodással és éberséggel védi az Ön Macjét.

Üdvözöljük az **OtterKeep** alkalmazásban! Ez az útmutató végigvezeti Önt a letöltésen, telepítésen, a szükséges macOS engedélyek megadásán és az első biztonsági mentés futtatásán.

---

## 1. Rendszerkövetelmények

- **macOS Sequoia (15.0)** vagy újabb operációs rendszer.
- Apple Silicon (M1/M2/M3/M4) vagy Intel 64 bites Mac számítógép.
- Fájlrendszer: **APFS** formátumú belső lemez és célkötet (erősen ajánlott az azonnali Copy-on-Write pillanatképekhez).

---

## 2. Telepítés

### A) lehetőség: Homebrew (Ajánlott)
```bash
brew tap richardeszeshu/otter-keep
brew install --cask otterkeep
```

### B) lehetőség: Lemezkép (.dmg) közvetlen letöltése
1. Töltse le a legfrissebb `OtterKeep-1.4.0.dmg` fájlt a [Kiadások (Releases)](https://github.com/richardeszeshu/otter-keep/releases) oldalról.
2. Kattintson duplán a letöltött DMG fájlra.
3. Húzza az **OtterKeep.app** ikont az `Alkalmazások` (Applications) mappába.
4. Indítsa el az OtterKeep alkalmazást a Launchpadről vagy a Spotlight keresőből.

---

## 3. Teljes hozzáférés a lemezhez (Full Disk Access) megadása

A macOS védi a személyes fájlokat (Dokumentumok, Mail, Fotók, Safari adatok) a TCC biztonsági alrendszeren keresztül. Ahhoz, hogy az OtterKeep megbízhatóan biztonsági másolatot készíthessen ezekről a védett könyvtárakról, **Teljes hozzáférés a lemezhez** jogosultság szükséges:

1. Nyissa meg a Mac **Rendszerbeállítások** (System Settings) menüjét.
2. Válassza az **Adatvédelem és biztonság** (Privacy & Security) → **Teljes hozzáférés a lemezhez** (Full Disk Access) pontot.
3. Kattintson a **+** gombra (vagy azonosítsa magát Touch ID-val / jelszóval).
4. Válassza ki az `OtterKeep.app` alkalmazást az `Alkalmazások` mappából.
5. Győződjön meg róla, hogy a kapcsoló **BE** állásban van.

> [!NOTE]
> Amennyiben a parancssori felületet is használja (`otterkeep-cli`), ellenőrizze, hogy az Ön által használt terminál alkalmazásnak (pl. Terminal, iTerm2, Ghostty) is megvan-e a Teljes lemezhozzáférési engedélye.

---

## 4. Az első mentés 3 egyszerű lépésben

1. **Forrásmappák kiválasztása**:
   Alapértelmezésben az OtterKeep a felhasználói mappát (`~`) védi, automatikusan kihagyva az ideiglenes gyorsítótárakat (`~/Library/Caches`). A **Profilok és szabályok** menüben testreszabhatja a védett könyvtárakat.

2. **Célmeghajtó kijelölése**:
   Válasszon ki egy külső APFS meghajtót, egy különálló APFS kötetet vagy egy hálózati megosztást.

3. **Mentés indítása**:
   Kattintson a **Mentés indítása** gombra a menüsorban vagy a főablakban. Az OtterKeep azonnal létrehozza az első pillanatképet, folyamatos visszajelzést adva a Mac leterhelése nélkül.

---

## 5. További útmutatók

- [Mentés és visszaállítás](backup-and-restore.hu.md) — Pillanatképek böngészése és fájlok helyreállítása.
- [Távoli célállomások](remote-destinations.hu.md) — SFTP és NAS meghajtók beállítása.
- [Fotók védelme](photos-protection.hu.md) — Apple Fotókönyvtár mentése.
