import 'package:latlong2/latlong.dart';
import '../../core/privacy/coordinate_guard.dart';

/// Repräsentiert ein bekanntes, prominentes Wald-, Natur- oder Schutzgebiet.
class NearbyNatureRegion {
  final String name;
  final String category; // z. B. 'Nationalpark', 'Biosphärenreservat', 'Naturpark', 'Waldgebiet'
  final String categoryLabel; // z. B. 'Nationalpark', 'Naturschutz', 'Wald', 'Gipfel / Berg', 'Gewässer'
  final String state; // z. B. 'Baden-Württemberg', 'Bayern', 'NRW', etc.
  final LatLng coordinate;

  const NearbyNatureRegion({
    required this.name,
    required this.category,
    required this.categoryLabel,
    required this.state,
    required this.coordinate,
  });
}

/// Eintrag für ein Nahegelegenes Gebiet inklusive vorberechneter Distanz in Kilometern.
class NearbyNatureRegionEntry {
  final NearbyNatureRegion region;
  final double distanceKm;

  const NearbyNatureRegionEntry({
    required this.region,
    required this.distanceKm,
  });
}

/// Kuratierter Datenbestand bekannter Wald-, Natur- und Wildschutzregionen
/// im DACH-Raum (Deutschland, Österreich, Schweiz) mit Entfernungsberechnung.
class NearbyNatureRegionsService {
  static const Distance _geoDistance = Distance();

  /// Vollständige Liste prominenter deutscher und alpiner Wald- und Naturgebiete.
  static const List<NearbyNatureRegion> allRegions = [
    // Norddeutschland
    NearbyNatureRegion(
      name: 'Müritz-Nationalpark',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Mecklenburg-Vorpommern',
      coordinate: LatLng(53.4244, 12.8711),
    ),
    NearbyNatureRegion(
      name: 'Lüneburger Heide',
      category: 'Naturschutzgebiet',
      categoryLabel: 'Naturschutz',
      state: 'Niedersachsen',
      coordinate: LatLng(53.1700, 9.9500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Südheide',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Niedersachsen',
      coordinate: LatLng(52.8200, 10.1500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Holsteinische Schweiz',
      category: 'Naturpark',
      categoryLabel: 'Gewässer',
      state: 'Schleswig-Holstein',
      coordinate: LatLng(54.1800, 10.5500),
    ),
    NearbyNatureRegion(
      name: 'Biosphärenreservat Schaalsee',
      category: 'Biosphärenreservat',
      categoryLabel: 'Gewässer',
      state: 'MV / Schleswig-Holstein',
      coordinate: LatLng(53.6000, 10.9500),
    ),
    NearbyNatureRegion(
      name: 'Nationalpark Wattenmeer',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Niedersachsen / SH',
      coordinate: LatLng(53.8500, 8.4000),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Wildeshauser Geest',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Niedersachsen',
      coordinate: LatLng(52.9200, 8.4500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Hümmling',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Niedersachsen',
      coordinate: LatLng(52.9000, 7.6000),
    ),

    // Ostdeutschland
    NearbyNatureRegion(
      name: 'Naturpark Barnim',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Brandenburg / Berlin',
      coordinate: LatLng(52.7000, 13.5000),
    ),
    NearbyNatureRegion(
      name: 'Döberitzer Heide',
      category: 'Naturschutzgebiet',
      categoryLabel: 'Naturschutz',
      state: 'Brandenburg',
      coordinate: LatLng(52.5100, 13.0500),
    ),
    NearbyNatureRegion(
      name: 'Schorfheide-Chorin',
      category: 'Biosphärenreservat',
      categoryLabel: 'Naturschutz',
      state: 'Brandenburg',
      coordinate: LatLng(52.9742, 13.7562),
    ),
    NearbyNatureRegion(
      name: 'Biosphärenreservat Spreewald',
      category: 'Biosphärenreservat',
      categoryLabel: 'Naturschutz',
      state: 'Brandenburg',
      coordinate: LatLng(51.8700, 13.9200),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Dahme-Heideseen',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Brandenburg',
      coordinate: LatLng(52.2000, 13.8000),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Schlaubetal',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Brandenburg',
      coordinate: LatLng(52.1500, 14.4500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Westhavelland',
      category: 'Naturpark',
      categoryLabel: 'Naturschutz',
      state: 'Brandenburg',
      coordinate: LatLng(52.6500, 12.3500),
    ),
    NearbyNatureRegion(
      name: 'Uckermärkische Seen',
      category: 'Naturpark',
      categoryLabel: 'Gewässer',
      state: 'Brandenburg',
      coordinate: LatLng(53.2500, 13.5000),
    ),
    NearbyNatureRegion(
      name: 'Nationalpark Sächsische Schweiz',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Sachsen',
      coordinate: LatLng(50.9300, 14.1800),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Erzgebirge/Vogtland',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Sachsen',
      coordinate: LatLng(50.5500, 13.0000),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Dübener Heide',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Sachsen / Sachsen-Anhalt',
      coordinate: LatLng(51.6500, 12.6500),
    ),

    // Mitteldeutschland & Thüringen / Harz
    NearbyNatureRegion(
      name: 'Nationalpark Harz',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Niedersachsen / Sachsen-Anhalt',
      coordinate: LatLng(51.7833, 10.6167),
    ),
    NearbyNatureRegion(
      name: 'Thüringer Wald',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Thüringen',
      coordinate: LatLng(50.6500, 10.7500),
    ),
    NearbyNatureRegion(
      name: 'Nationalpark Hainich',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Thüringen',
      coordinate: LatLng(51.1000, 10.4500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Kyffhäuser',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Thüringen',
      coordinate: LatLng(51.4100, 11.0800),
    ),
    NearbyNatureRegion(
      name: 'Biosphärenreservat Rhön',
      category: 'Biosphärenreservat',
      categoryLabel: 'Naturschutz',
      state: 'Hessen / Bayern / Thüringen',
      coordinate: LatLng(50.4500, 10.0000),
    ),
    NearbyNatureRegion(
      name: 'Nationalpark Kellerwald-Edersee',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Hessen',
      coordinate: LatLng(51.1500, 9.0000),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Habichtswald',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Hessen',
      coordinate: LatLng(51.3100, 9.3500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Taunus',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Hessen',
      coordinate: LatLng(50.2200, 8.4500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Spessart',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Bayern / Hessen',
      coordinate: LatLng(50.0500, 9.4000),
    ),
    NearbyNatureRegion(
      name: 'Geo-Naturpark Bergstraße-Odenwald',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Hessen / BW / Bayern',
      coordinate: LatLng(49.6000, 8.9000),
    ),

    // Westdeutschland & NRW
    NearbyNatureRegion(
      name: 'Teutoburger Wald',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Nordrhein-Westfalen',
      coordinate: LatLng(51.9000, 8.8500),
    ),
    NearbyNatureRegion(
      name: 'Rothaargebirge / Rothaarsteig',
      category: 'Waldgebiet',
      categoryLabel: 'Wald',
      state: 'Nordrhein-Westfalen / Hessen',
      coordinate: LatLng(51.1000, 8.3500),
    ),
    NearbyNatureRegion(
      name: 'Arnsberger Wald / Sauerland',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Nordrhein-Westfalen',
      coordinate: LatLng(51.4500, 8.1500),
    ),
    NearbyNatureRegion(
      name: 'Nationalpark Eifel',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Nordrhein-Westfalen',
      coordinate: LatLng(50.5600, 6.4200),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Bergisches Land',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Nordrhein-Westfalen',
      coordinate: LatLng(51.0500, 7.3000),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Hohes Venn - Eifel',
      category: 'Naturpark',
      categoryLabel: 'Naturschutz',
      state: 'Nordrhein-Westfalen / RLP',
      coordinate: LatLng(50.5200, 6.1800),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Schwalm-Nette',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Nordrhein-Westfalen',
      coordinate: LatLng(51.2700, 6.2200),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Siebengebirge',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Nordrhein-Westfalen',
      coordinate: LatLng(50.6700, 7.2300),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Dümmer',
      category: 'Naturpark',
      categoryLabel: 'Naturschutz',
      state: 'Niedersachsen / NRW',
      coordinate: LatLng(52.5100, 8.3500),
    ),

    // Südwestdeutschland & Rheinland-Pfalz
    NearbyNatureRegion(
      name: 'Nationalpark Schwarzwald',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Baden-Württemberg',
      coordinate: LatLng(48.5600, 8.2100),
    ),
    NearbyNatureRegion(
      name: 'Biosphärenreservat Pfälzerwald',
      category: 'Biosphärenreservat',
      categoryLabel: 'Wald',
      state: 'Rheinland-Pfalz',
      coordinate: LatLng(49.3000, 7.8500),
    ),
    NearbyNatureRegion(
      name: 'Nationalpark Hunsrück-Hochwald',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Rheinland-Pfalz / Saarland',
      coordinate: LatLng(49.6700, 7.1000),
    ),
    NearbyNatureRegion(
      name: 'Biosphärengebiet Schwäbische Alb',
      category: 'Biosphärengebiet',
      categoryLabel: 'Naturschutz',
      state: 'Baden-Württemberg',
      coordinate: LatLng(48.4000, 9.3500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Schönbuch',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Baden-Württemberg',
      coordinate: LatLng(48.6000, 9.0500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Stromberg-Heuchelberg',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Baden-Württemberg',
      coordinate: LatLng(49.0300, 8.9500),
    ),

    // Bayern & Süddeutschland
    NearbyNatureRegion(
      name: 'Ebersberger Forst',
      category: 'Waldgebiet',
      categoryLabel: 'Wald',
      state: 'Bayern',
      coordinate: LatLng(48.1200, 11.9500),
    ),
    NearbyNatureRegion(
      name: 'Isarauen / Pupplinger Au',
      category: 'Naturschutzgebiet',
      categoryLabel: 'Naturschutz',
      state: 'Bayern',
      coordinate: LatLng(47.9300, 11.4600),
    ),
    NearbyNatureRegion(
      name: 'Nationalpark Bayerischer Wald',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Bayern',
      coordinate: LatLng(48.9700, 13.3900),
    ),
    NearbyNatureRegion(
      name: 'Nationalpark Berchtesgaden',
      category: 'Nationalpark',
      categoryLabel: 'Nationalpark',
      state: 'Bayern',
      coordinate: LatLng(47.5500, 12.9200),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Altmühltal',
      category: 'Naturpark',
      categoryLabel: 'Naturschutz',
      state: 'Bayern',
      coordinate: LatLng(48.9500, 11.2000),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Frankenwald',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Bayern',
      coordinate: LatLng(50.3500, 11.5500),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Fichtelgebirge',
      category: 'Naturpark',
      categoryLabel: 'Gipfel / Berg',
      state: 'Bayern',
      coordinate: LatLng(50.0500, 11.9000),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Steigerwald',
      category: 'Naturpark',
      categoryLabel: 'Wald',
      state: 'Bayern',
      coordinate: LatLng(49.8000, 10.5000),
    ),
    NearbyNatureRegion(
      name: 'Allgäuer Hochalpen',
      category: 'Naturschutzgebiet',
      categoryLabel: 'Gipfel / Berg',
      state: 'Bayern',
      coordinate: LatLng(47.4000, 10.2800),
    ),

    // Alpenregion DACH (Österreich / Grenzregion)
    NearbyNatureRegion(
      name: 'Nationalpark Hohe Tauern',
      category: 'Nationalpark',
      categoryLabel: 'Gipfel / Berg',
      state: 'Alpen (Österreich)',
      coordinate: LatLng(47.1000, 12.7000),
    ),
    NearbyNatureRegion(
      name: 'Naturpark Karwendel',
      category: 'Naturpark',
      categoryLabel: 'Gipfel / Berg',
      state: 'Tirol / Bayern',
      coordinate: LatLng(47.4200, 11.4500),
    ),
  ];

  /// Findet die n nächsten Gebiete zum übergebenen Referenzpunkt, sortiert
  /// nach aufsteigender Distanz und optional gefiltert nach [maxRadiusKm].
  static List<NearbyNatureRegionEntry> findNearby({
    required LatLng userCoordinate,
    int limit = 6,
    double? maxRadiusKm,
    bool fallbackToClosestIfEmpty = false,
  }) {
    // Validitätsprüfung der Koordinaten
    final lat = userCoordinate.latitude;
    final lon = userCoordinate.longitude;
    final validCoord = (lat.isNaN || lon.isNaN || !CoordinateGuard.isValidCoordinate(lat, lon))
        ? const LatLng(51.1657, 10.4515)
        : userCoordinate;

    final entries = allRegions.map((region) {
      final distanceKm = _geoDistance.as(
        LengthUnit.Kilometer,
        validCoord,
        region.coordinate,
      );
      return NearbyNatureRegionEntry(
        region: region,
        distanceKm: distanceKm,
      );
    }).toList();

    entries.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    if (maxRadiusKm != null && maxRadiusKm > 0) {
      final withinRadius =
          entries.where((e) => e.distanceKm <= maxRadiusKm).toList();
      if (withinRadius.isNotEmpty || !fallbackToClosestIfEmpty) {
        return withinRadius.take(limit).toList();
      }
    }

    return entries.take(limit).toList();
  }

  /// Sucht lokal nach einem passenden Gebiet anhand des Namens oder Teilnamens.
  /// Ideal für Offline-Resilienz und sofortige Treffer bei Tipp-Vorschlägen.
  static NearbyNatureRegion? findByNameOrKeyword(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.length < 3) return null;

    for (final reg in allRegions) {
      final n = reg.name.toLowerCase();
      if (n == clean || n.contains(clean) || clean.contains(n)) {
        return reg;
      }
    }
    return null;
  }
}
