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

## 2. Pillanatképek és verziók böngészése, offline idővonal

A főablak **Visszaállítás** lapján:

- **Offline metaadat-elérés**: Az OtterKeep perzisztens Központi Adatbázisának (`~/.otterkeep/central.sqlite`) köszönhetően a korábbi pillanatképek, mentett könyvtárak és fájlok akkor is böngészhetők és kereshetők, ha a külső mentési meghajtó nincs csatlakoztatva.
- **Pillanatkép-választó**: Időrendi sorrendben áttekintheti az elkészült mentéseket azok pontos időbélyegével, fájlszámával, méretével és pecsét-státuszával.
- **Fájlböngésző**: Megtekintheti a mappákat pontosan abban az állapotban, ahogyan a mentés pillanatában léteztek.
- **Globális kereső**: Írjon be bármilyen fájlnevet vagy névrészletet a keresőmezőbe, és az OtterKeep azonnal kilistázza a fájl összes korábbi változatát a mentési történetből.
- **Különbség-nézet (Diff)**: Hasonlítson össze két pillanatképet, hogy pontosan lássa, mi került hozzáadásra, módosításra vagy törlésre.

---

## 3. Fájlok és mappák biztonságos visszaállítása

A helyreállítás során az OtterKeep szigorú összeomlás-biztossági és adatvédelmi elveket érvényesít:

### Fájl-ütközésvédelem
Amennyiben a célhelyen már létezik egy azonos nevű fájl:
- Az OtterKeep soha nem írja felül némán az Ön meglévő munkáját.
- Egyértelmű, lokalizált verziósorszámot fűz a fájlnévhez:
  - Magyarul: `Jelentés (visszaállított 1).pdf`
  - Angolul: `Report (restored 1).pdf`

### 3-Fázisú Atomi Mappavisszaállítás `.old` védelemmel
Teljes könyvtárstruktúrák helyreállításakor vagy eredeti helyre történő visszatöltéskor:
1. **Előkészítés átmeneti mappába**: A fájlok először egy elkülönített, átmeneti staging mappába (`.staging_<uuid>`) kerülnek kicsomagolásra és ellenőrzésre.
2. **Biztonsági áthelyezés `.old` mappába**: A meglévő célkönyvtár törlés helyett átnevezésre kerül egy `.old_<időbélyeg>` biztonsági mappába.
3. **Atomi beemelés és végleges takarítás**: Az ellenőrzött átmeneti könyvtár atomi művelettel a helyére kerül. A rendszer csak a sikeres beemelést követően törli a `.old` biztonsági könyvtárat. Amennyiben bármilyen hiba, lekapcsolódás vagy megszakítás történne ezelőtt, a `.old` könyvtár azonnal és automatikusan visszagörgetésre kerül, így zéró adatvesztés következik be.

### Eredeti helyre vagy egyéni mappába
- **Helyreállítás az eredeti helyre**: A fájlokat és mappákat közvetlenül az eredeti helyükre állítja vissza.
- **Helyreállítás máshová...**: Kiválaszthatja a Mac bármely mappáját (például az Íróasztalt vagy egy vizsgálati mappát) a biztonságos ellenőrzéshez.

---

## 4. 100%-os bizonyosságú katalógus-egyeztetés

Amennyiben olyan mentési meghajtót csatlakoztat, amelyen egy másik rendszeren készült, vagy még nem indexelt mentések találhatók:
- Az OtterKeep **Katalógus Egyeztetője** automatikusan megvizsgálja a lemezen lévő pillanatkép-könyvtárakat.
- Szigorú teljességi vizsgálatot végez: ellenőrzi a könyvtárszerkezetet, a fájlok nem-ürességét és az érvényes lezárási pecsétet.
- Kizárólag a 100%-ig ellenőrzött, hiánytalan pillanatképek kerülnek felvételre a helyi adatbázisba, garantálva a hibás vagy sérült mentések kizárását.

---

## 5. Megőrzési és törlési szabályzat

Annak érdekében, hogy a mentési merevlemez ne teljen be feleslegesen, a **Profil beállítások** menüben testreszabhatja az automatikus megőrzési időszakokat:
- **Óránkénti mentések**: Az elmúlt 24 órára visszamenőleg.
- **Napi mentések**: Az elmúlt 30 napra.
- **Heti mentések**: Az elmúlt 12 hónapra.
- A feleslegessé vált pillanatképek törlésekor az SQLite katalógus automatikusan frissül, és az APFS azonnal felszabadítja a már nem hivatkozott adatblokkokat. Az aktív WORM zárral védett pillanatképek szigorú védelmet élveznek, a zárolási idő lejárta előtt a rendszer nem törli őket.
