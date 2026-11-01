# WildlifeScout 🦌📸

> **Präzisions-Feldkarte, Habitat-Analyse & Ansitz-Planer für Natur- & Wildlife-Fotografen.**  
> Entwickelt mit Flutter – Local-First, kompromisslos datenschutzfreundlich und optimiert für den Einsatz draußen im Feld.

---

## 🌟 Highlights & Features

- 🎯 **Präzisions-Feldkarte ("Field Nature Glass"):**
  - Integrierte OpenStreetMap-Vektorkarte mit dynamischem Witterungskegel (*Scent Cone*).
  - Interaktive Vorhersage von Windrichtung, Windgeschwindigkeit und Geruchsausbreitung (z. B. 250 m bei Rehwild bis 450 m bei Rotwild).
  - Zeitschieberegler (*Time Scrubber*) zur Simulation der Wind- und Lichtbedingungen über den Tagesverlauf.

- 🌙 **Night-Vision Red Mode (Tarnzelt-Rotlicht):**
  - Ein-Klick-Umschaltung in ein monochromes, augenschonendes Tiefrot-Interface (`🌙 Rotlicht`).
  - Schützt die Dunkeladaption der Augen und verhindert störenden Lichtschein im Tarnzelt in der Dämmerung.

- 🔒 **DSGVO & Privacy by Design (100 % Zero-Track):**
  - **Local-First:** Ansitz-Spots, Notizen und Sichtungen verbleiben ausschließlich lokal auf dem Endgerät (verschlüsselt via Hardware-Keystore/Keychain).
  - **Koordinaten-Guard (Coordinate Rounding):** Wetter- und Umweltdaten von Open-Meteo werden vor dem Abruf auf ein 2-km-Raster gerundet. Die exakte GPS-Position des Ansitzes verlässt niemals das Gerät.
  - **Keine Tracker, keine Cloud-Zwänge, keine extern nachgeladenen Fonts.**

- 🦌 **Tierarten-Steckbriefe & Aktivitäts-Scores:**
  - Spezifische Profile für heimische Wildarten (u. a. Rehwild, Rotwild, Schwarzwild, Eisvogel, Feldhase).
  - Berechnung des Aktivitäts-Scores anhand von Sonnenstand (Goldene/Blaue Stunde), Mondphase, Temperatur und Wetter.
  - Ausnahmslos lizenzfreie Tierfotos mit transparentem Urhebernachweis.

- 🧤 **One-Handed & Glove-Friendly UX:**
  - Untere Daumen-Bedienzone (Bottom HUD) für entspannte Einhand-Bedienung mit Teleobjektiv in der anderen Hand.
  - Großzügige Touch-Targets (mind. 48×48 dp) für Bedienung mit Handschuhen.

---

## 🏗 Architektur

Das Projekt folgt einer strikten **Feature-First Clean Architecture**:

```
lib/
├── core/
│   ├── theme/          # Design-Tokens, Obsidian Forest & Night-Vision Themes
│   ├── privacy/        # CoordinateGuard (DSGVO-Rundung), SecureKeyService
│   └── utils/          # Mathematische & astronomische Berechnungen (SunCalc, Geo)
├── domain/
│   ├── models/         # Unveränderliche Dart-Datenmodelle (SpeciesProfile, Spot, WeatherFrame)
│   └── services/       # Business-Logik (HabitatEngine, ActivityScoreCalculator)
├── data/
│   ├── api/            # API-Clients (Open-Meteo, Overpass) mit Offline-Caching
│   └── repositories/   # SpotVaultRepository (lokal verschlüsselt), SpeciesRepository
└── presentation/
    ├── state/          # Reaktiver App-State
    ├── screens/        # FieldMapScreen, SpotVaultScreen, PrivacyScreen
    └── widgets/        # Glassmorphic HUD, ScentConePainter, TimeScrubber
```

Detaillierte Design- und Sicherheitsrichtlinien findest du in der [DESIGN_AND_SECURITY_CHARTER.md](DESIGN_AND_SECURITY_CHARTER.md).

---

## 🚀 Erste Schritte

### Voraussetzungen
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Version >= 3.3.0)
- Dart SDK
- Xcode (für iOS / macOS Builds) oder Android Studio (für Android Builds)

### Installation & Start

1. Repository klonen:
   ```bash
   git clone git@github.com:dermatz/WildlifeScout.git
   cd WildlifeScout
   ```

2. Abhängigkeiten installieren:
   ```bash
   flutter pub get
   ```

3. App im Debug-Modus starten:
   ```bash
   flutter run
   ```

4. Tests ausführen:
   ```bash
   flutter test
   ```

---

## 📜 Lizenz & Bildnachweis

- Der Quellcode steht unter freier Nutzung für das WildlifeScout-Projekt.
- Alle verwendeten Tierbilder und Medien unterliegen freien, lizenzfreien Lizenzen (Unsplash License / CC0 / Public Domain). Bildautoren und Originalquellen sind in den jeweiligen Species-JSON-Dateien unter `assets/species/` transparent hinterlegt.
