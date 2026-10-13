# Mentési és visszaállítási útmutató

Ez a kézikönyv részletesen bemutatja az OtterKeep növekményes pillanatkép-kezelését, a módosulás-érzékelési mechanizmust, valamint az egyes fájlok és teljes mappák biztonságos helyreállítását.

---

## 1. Hogyan működnek a növekményes pillanatképek?

Minden egyes mentési munkamenet egy önálló, befejezett **Pillanatképet** (Snapshot) hoz létre:

1. **Szkennelési fázis**: A motor bejárja a kijelölt forráskönyvtárakat. A változatlan elemeket a fájlméret, a nanoszekundumos pontosságú módosítási időbélyeg és az APFS inode azonosító alapján azonosítja.
2. **CoW Klónozás**: A célköteten már létező, változatlan fájlok esetében az OtterKeep az Apple natív `clonefile(2)` hívását használja, amely fizikai adatmozgatás nélkül mutat a meglévő blokkokra. Ezredmásodpercek alatt lefut, és zéró plusz tárhelyet igényel.
3. **Adatátvitel**: Kizárólag az újonnan létrehozott vagy ténylegesen módosult fájlok másolódnak át a célmeghajtóra.
4. **Katalógus indexelés**: A teljes fájllistát egy helyi SQLite adatbázis rögzíti Write-Ahead Logging (WAL) üzemmódban.

---

## 2. Pillanatképek és verziók böngészése

A főablak **Visszaállítás** lapján:

- **Pillanatkép-választó**: Időrendi sorrendben áttekintheti az elkészült mentéseket azok pontos időbélyegével, fájlszámával és méretével.
- **Fájlböngésző**: Megtekintheti a mappákat pontosan abban az állapotban, ahogyan a mentés pillanatában léteztek.
- **Globális kereső**: Írjon be bármilyen fájlnevet vagy névrészletet a keresőmezőbe, és az OtterKeep azonnal kilistázza a fájl összes korábbi változatát a mentési történetből.
- **Különbség-nézet (Diff)**: Hasonlítson össze két pillanatképet, hogy pontosan lássa, mi került hozzáadásra, módosításra vagy törlésre.

---

## 3. Fájlok biztonságos visszaállítása

A helyreállítás során az OtterKeep elsődleges alapelve az adatvédelem:

### Ütközésvédelem
Amennyiben a célhelyen már létezik egy azonos nevű fájl:
- Az OtterKeep soha nem írja felül némán az Ön meglévő munkáját.
- Egyértelmű, lokalizált verziósorszámot fűz a fájlnévhez:
  - Magyarul: `Jelentés (visszaállított 1).pdf`
  - Angolul: `Report (restored 1).pdf`

### Eredeti helyre vagy egyéni mappába
- **Helyreállítás az eredeti helyre**: A fájlt közvetlenül az eredeti mappájába állítja vissza.
- **Helyreállítás máshová...**: Kiválaszthatja a Mac bármely mappáját (például az Íróasztalt vagy egy vizsgálati mappát) a biztonságos ellenőrzéshez.

---

## 4. Megőrzési és törlési szabályzat

Annak érdekében, hogy a mentési merevlemez ne teljen be feleslegesen, a **Beállítások** menüben testreszabhatja az automatikus megőrzési időszakokat:
- **Óránkénti mentések**: Az elmúlt 24 órára visszamenőleg.
- **Napi mentések**: Az elmúlt 30 napra.
- **Heti mentések**: Az elmúlt 12 hónapra.
- A feleslegessé vált pillanatképek törlésekor az SQLite katalógus automatikusan frissül, és az APFS azonnal felszabadítja a már nem hivatkozott adatblokkokat.
