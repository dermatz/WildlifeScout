# WildScout – Design System, Security & DSGVO Charter

Dieses Dokument definiert die verbindlichen Standards für **UX/UI-Exzellenz**, **Clean Architecture (Wartbarkeit)**, **Security** und **DSGVO-Konformität (Privacy by Design)** für WildScout.

---

## 1. DSGVO & Privacy by Design (100% Zero-Track Architektur)

Wildlife-Fotografen sind extrem sensibel bezüglich ihrer Standortdaten (Geheimhaltung von Brutplätzen, Einständen und Ansitzen). Gleichzeitig spart eine strikte Zero-Data-Architektur jeglichen juristischen Aufwand bezüglich Auftragsverarbeitungsverträgen (AVV) und Cookie-Bannern:

1. **Local-First & Zero-Knowledge für Spots:**
   - Alle gespeicherten Ansitze, Sichtungen, Notizen und Fotos verbleiben **ausschließlich lokal auf dem Endgerät** (verschlüsselt via `flutter_secure_storage` + lokaler Datenbank).
   - Es gibt **keinen Cloud-Zwang** und keine Übertragung von Nutzer-Standorten an eigene Server.
2. **Koordinaten-Obfuskation (Coordinate Rounding) bei Wetter-Requests:**
   - Wenn die App Wetter- oder Winddaten von *Open-Meteo* abruft, wird niemals die exakte GPS-Position des Tarnzelts gesendet.
   - Koordinaten werden vor jedem Netzwerk-Call automatisch auf ein **2-km-Raster gerundet** (z. B. `51.23841, 7.45192` → `51.24, 7.45`). Da Wettermodelle (DWD ICON-D2) ohnehin eine Auflösung von 2,2 km haben, bleibt die Vorhersage zu 100 % präzise, während der exakte Ansitz-Spot niemals das Gerät verlässt!
3. **Keine versteckten Tracker / Keine Drittanbieter-Fonts:**
   - Kein Google Analytics, kein Firebase Crashlytics ohne explizites Opt-in, kein Nachladen von Google Fonts zur Laufzeit (Abmahnfalle!). Alle Schriften und Icons sind lokal im App-Bundle (`assets/fonts/`) eingebettet.
   - Alle externen Datenquellen (Kartenkacheln, Open-Meteo, Overpass) sind im „Datenschutz & Quellen“-Screen transparent aufgelistet.

---

## 2. Security-Standards

1. **Verschlüsselter lokaler Tresor (Spot-Vault):**
   - Lokale Datenbank-Schlüssel (AES-256) werden in der Hardware-Keychain (iOS Secure Enclave / Android Keystore) über `flutter_secure_storage` abgelegt.
2. **Strikte Input- & API-Validierung:**
   - Alle externen JSON-Antworten (Open-Meteo, Overpass API, Species Profiles) werden streng typisiert geparst und gegen Grenzwerte validiert (Defensives Parsing gegen korrupte Daten).
   - Ausschließlich `HTTPS` (TLS 1.3) Verbindungen.
3. **Abhängigkeits-Minimalismus:**
   - Nur geprüfte, aktiv gepflegte Open-Source-Packages (Zero-Bloat-Prinzip).

---

## 3. Wartbarkeit & Clean Architecture

Die Codebasis folgt einer strikten **Feature-First Clean Architecture**:

```
lib/
├── core/
│   ├── theme/          # Design-Tokens, Farben, Typografie, Night-Vision-Theme
│   ├── privacy/        # CoordinateGuard (DSGVO-Rundung), SecureKeyService
│   └── utils/          # Mathematische Helfer (Trigonometrie, Geo-Projektion)
├── domain/
│   ├── models/         # Reine, unveränderliche Dart-Modelle (SpeciesProfile, Spot, WeatherFrame)
│   └── services/       # Reine Business-Logik (HabitatEngine, ActivityScoreCalculator, SunCalc)
├── data/
│   ├── api/            # OpenMeteoClient, OverpassClient (mit Offline-Cache)
│   └── repositories/   # SpotVaultRepository (Lokal verschlüsselt), SpeciesRepository
└── presentation/
    ├── state/          # Zentraler, reaktiver App-State
    ├── screens/        # TacticalMapScreen, SpotVaultScreen, PrivacyScreen
    └── widgets/        # Glassmorphic HUD, ScentConePainter, TimeScrubber, SpeciesSelector
```

- **100 % Entkopplung:** Die `domain/`-Schicht hat keinerlei Abhängigkeiten zu Flutter-UI oder externen HTTP-Bibliotheken und ist vollständig durch Unit-Tests prüfbar.
- **Erweiterbarkeit:** Neue Wildarten werden ausschließlich als JSON-Profile unter `assets/species/` registriert.

---

## 4. Award-Winning UX/UI Design System: "Tactical Nature Glass"

WildScout kombiniert die Präzision moderner Luftfahrt-/Taktik-Interfaces mit der Ruhe und Ästhetik der Natur:

### 4.1 Zwei adaptive Licht-Modi (inkl. Tarnzelt-Rotlicht!)
1. **Obsidian Forest (Standard Dark HUD):**
   - Tiefes Schiefer-Waldgrün/Anthrazit (`#0B0F0E` / `#121917`), halbtransparentes Milchglas (`BackdropFilter` mit `sigma: 16`), feine 1px-Glanzkanten (`rgba(255,255,255,0.08)`).
   - Akzentfarben: **Amber Gold** (`#F59E0B` für Sonnenstand/Golden Hour), **Emerald Bio** (`#10B981` für optimale Habitate), **Crimson Scent** (`#EF4444` für Witterungs-/Gefahrenkegel).
2. **Night-Vision Red Mode (Tarnzelt-Modus um 04:30 Uhr):**
   - Ein-Tap-Umschalter oben rechts (`🌙 Rotlicht`).
   - Schaltet das gesamte Interface und die Karte mittels Farb-Matrix-Filter in ein monochromes, augenschonendes **Tiefrot (`#991B1B` / `#DC2626` auf `#050000`)**.
   - Bewahrt die Dunkeladaption des menschlichen Auges zu 100 % und verhindert jeglichen Lichtschein aus dem Tarnzelt, der Rot- oder Schwarzwild vergrämen würde.

### 4.2 Ergonomie im Feld (One-Handed & Glove-Friendly)
- **Daumen-Zone (Bottom HUD):** Alle interaktiven Hauptelemente (Zeitschieberegler, Ansitz-Wetterdaten, Stunden-Wahl) liegen im unteren Drittel des Bildschirms – bequem mit einer Hand bedienbar, während die andere Hand am Teleobjektiv oder Fernglas bleibt.
- **Großzügige Touch-Targets:** Mindestens `48x48dp` für alle Buttons (auch mit dünnen Tarnhandschuhen im Spätherbst treffsicher bedienbar).
- **Mikro-Animationen:** Sanfte Übergänge beim Wechsel der Tierart (Witterungskegel passt seine Reichweite von 250m bei Rehwild auf 450m bei Rotwild fließend animiert an).

---

## 5. Lizenzfreiheit für Bilder & Medien (Zero Copyright Risk)

1. **Ausnahmslos lizenzfreie Tierfotos:**
   - Alle Tierfotos in WildScout stammen ausschließlich aus geprüften, **lizenzfreien Quellen** (freie **Unsplash License** via `images.unsplash.com` oder **CC0 / Public Domain**), die sowohl kommerziell als auch nicht-kommerziell kostenfrei und ohne Lizenzzwang nutzbar sind.
   - Kostenpflichtige *Unsplash+*-Bilder (`plus.unsplash.com`) oder urheberrechtlich geschützte Agenturbilder sind strikt untersagt.
2. **Transparenter Lizenz- & Urhebernachweis:**
   - Jedes Tierprofil unter `assets/species/*.json` dokumentiert transparent `imageLicense`, `imageAuthor`, `imageSourceUrl`, `imageUrl` sowie das lokal eingebettete Offline-Bild unter `assets/species/images/`.
   - Im UI (Tierauswahl & Tier-Steckbrief) wird die Lizenzfreiheit (`Unsplash License • Lizenzfrei`) samt Fotografen-Credit sichtbar ausgewiesen.
