# WildScout – Verbindliche Projekt- & Agent-Regeln (GEMINI.md)

## 1. Striktes Gebot: 100 % Lizenzfreie Bilder & Medien (Immer gewährleisten!)
- **Ausnahmslos lizenzfreie Bilder:** Alle in diesem Projekt verwendeten Fotos, Tierbilder, Grafiken und Medien müssen **zwingend und jederzeit lizenzfrei** sein (z. B. unter der freien **Unsplash License** über `images.unsplash.com`, **CC0 / Public Domain** oder frei nutzbare Open-Data-Medien ohne Lizenzgebühren).
- **Verbot kostenpflichtiger oder eingeschränkter Bilder:** Es dürfen **niemals** Bilder von *Unsplash+* (`plus.unsplash.com`), Stockfoto-Diensten mit Wasserzeichen/Lizenzpflicht oder Quellen mit unklarem Urheberrecht eingebunden werden.
- **Transparenter Lizenz- & Quellennachweis im Code:** Jedes eingebundene Tierbild muss im jeweiligen JSON-Profil (`assets/species/*.json`) explizit mit folgenden Metadaten hinterlegt sein:
  - `imageAssetPath`: Lokaler Pfad unter `assets/species/images/<id>.jpg` (für Offline-Verfügbarkeit und DSGVO-Schutz ohne unnötige Drittanbieter-Requests).
  - `imageUrl`: Direkte, freie Unsplash-CDN-URL (`https://images.unsplash.com/photo-...`).
  - `imageLicense`: Expliziter Lizenz-Status (z. B. `"Unsplash License (Lizenzfrei & frei nutzbar)"`).
  - `imageAuthor`: Name des Fotografen (Attribution/Credit).
  - `imageSourceUrl`: Link zur Original-Fundstelle auf Unsplash.

## 2. DSGVO & Privacy by Design (Zero-Track Architektur)
- Lokale Speicherung aller sensiblen Ansitz-Spots (`SpotVaultRepository`).
- Automatische 2-km-Koordinaten-Rundung (`CoordinateGuard`) vor externen Wetter-Abfragen.
- Keine versteckten Tracker oder Google Fonts zur Laufzeit.
