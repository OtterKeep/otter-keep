# Apple Fotók védelmi útmutató

Az OtterKeep dedikált, natív védelmi képességeket kínál az Apple Fotókönyvtár (`Photos.photoslibrary`) biztonsági mentéséhez. Megőrzi az eredeti nyers képeket, a szerkesztett változatokat és a Live Photo felvételeket anélkül, hogy adatvesztést kockáztatna.

---

## 1. Miért igényel különös figyelmet az Apple Fotók?

Az Apple Fotókönyvtár nem egyszerű képmappa, hanem egy összetett rendszer, amely SQLite adatbázisokból, gyorsítótárakból és az **iCloud Fotók (Mac-tárhely optimalizálása)** által felhőbe mozgatott fájlokból áll.

A hagyományos fájlmásoló eszközök gyakran kudarcot vallanak, mert:
1. Az eredeti felvételek helyett csupán a kis felbontású előnézeteket mentik le.
2. A felhőből letöltendő fájlok váratlan I/O hibákat okoznak.
3. A tömeges letöltés hirtelen betöltheti a helyi SSD teljes szabad kapacitását.
4. Az albumok, kedvencek és GPS koordináták elvesznek.

---

## 2. Az OtterKeep Fotó-architektúrája

Az OtterKeep közvetlenül a macOS PhotoKit keretrendszeréhez kapcsolódik:

- **Differenciális kereső (`PhotosDeltaScanner`)**: Pontosan felméri az új és módosított képeket anélkül, hogy feleslegesen beolvasná a több gigabájtnyi változatlan állományt.
- **XMP metaadat-kísérők (`PhotoMetadataExtractor`)**: A készítési dátumokat, GPS koordinátákat, kedvenc jelöléseket és az albumok elnevezéseit automatikusan szabványos Adobe **XMP kísérőfájlokba** (`.xmp`) exportálja, biztosítva a gyártófüggetlen megőrzést.
- **Live Photos és RAW párok**: A mozgóképes videókomponenseket (`.mov`) és a RAW+JPEG fotópárokat együtt, elválaszthatatlanul menti le.
- **Tárhelyvédő átmeneti puffer (`EphemeralStorageGuard`)**: A csak felhőben lévő fájlokat egy szigorúan korlátozott átmeneti tárterületen (alapértelmezetten 512 MB) keresztül tölti le. Amint a fájl rögzítésre kerül a célmeghajtón, a helyi ideiglenes másolat azonnal törlődik, megvédve a Mac belső lemezét a megteléstől.

---

## 3. Mappaelrendezési struktúrák

A **Profilok és szabályok → Fotók beállításai** alatt kiválaszthatja a kívánt célkönyvtár-szerkezetet:

1. **Dátum szerinti hierarchia (`dateHierarchy`)** (Alapértelmezett):
   `Originals/2026/10/IMG_0412.HEIC` + `IMG_0412.xmp`
2. **Albumok szerinti hierarchia (`albumHierarchy`)**:
   `Originals/Albums/Nyári Nyaralás/IMG_0412.HEIC`
3. **Egy szintű mappa (`flat`)**:
   `Originals/IMG_0412_UUID.HEIC`
