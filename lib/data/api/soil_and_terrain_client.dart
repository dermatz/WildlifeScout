import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/privacy/coordinate_guard.dart';
import '../../domain/models/soil_substrate_profile.dart';

/// Fragt echte geologische Bodenuntergrund-Daten (BGR BÜK200 / ISRIC SoilGrids)
/// sowie präzise Geländehöhen & Hangneigungen (Copernicus DEM via Open-Meteo Elevation)
/// ab. Alle Abfragen sind 100 % API-Key-frei und DSGVO-geschützt.
class SoilAndTerrainClient {
  static final Map<String, SoilSubstrateProfile> _soilCache = {};
  static final Map<String, TerrainSlopeSample> _slopeCache = {};

  /// Ermittelt das geologische Bodenuntergrund-Profil für den Sektor.
  /// Nutzt zwingend [CoordinateGuard.obfuscateForWeatherApi] (2-km-Raster).
  static Future<SoilSubstrateProfile> fetchSoilSubstrateForSector(
    double latitude,
    double longitude,
  ) async {
    if (!CoordinateGuard.isValidCoordinate(latitude, longitude)) {
      return _fallbackSoilProfile();
    }

    final safe = CoordinateGuard.obfuscateForWeatherApi(latitude, longitude);
    final cacheKey = '${safe.lat}_${safe.lon}';
    final cached = _soilCache[cacheKey];
    if (cached != null) return cached;

    // 1. Primär-Abfrage: Amtliche Bodenübersichtskarte BGR BÜK200 (Deutschland)
    final bgrProfile = await _fetchFromBgrBuek200(safe.lat, safe.lon);
    if (bgrProfile != null) {
      _soilCache[cacheKey] = bgrProfile;
      return bgrProfile;
    }

    // 2. Fallback / International: ISRIC SoilGrids v2.0 (15–30 cm Tiefe: Sand/Schluff/Ton)
    final soilGridsProfile = await _fetchFromIsricSoilGrids(safe.lat, safe.lon);
    if (soilGridsProfile != null) {
      _soilCache[cacheKey] = soilGridsProfile;
      return soilGridsProfile;
    }

    final fallback = _fallbackSoilProfile();
    _soilCache[cacheKey] = fallback;
    return fallback;
  }

  /// Berechnet für eine Liste von Habitat-Koordinaten in einem einzigen gebündelten
  /// Batch-Request (max. 18 Punkte x 5 Messpunkte = 90 Punkte) die echte Geländehöhe,
  /// Hangneigung in Grad (Slope) und Hang-Exposition (Aspect).
  static Future<Map<int, TerrainSlopeSample>> fetchBatchTerrainSlopes(
    List<LatLng> centers,
  ) async {
    if (centers.isEmpty) return const {};

    final result = <int, TerrainSlopeSample>{};
    final uncachedIndices = <int>[];

    for (int i = 0; i < centers.length && uncachedIndices.length < 18; i++) {
      final pt = centers[i];
      final key =
          '${pt.latitude.toStringAsFixed(4)}_${pt.longitude.toStringAsFixed(4)}';
      final cached = _slopeCache[key];
      if (cached != null) {
        result[i] = cached;
      } else {
        uncachedIndices.add(i);
      }
    }

    if (uncachedIndices.isEmpty) return result;

    // Für jeden Kandidaten 5 Punkte im 40m-Kreuz (Zentrum, Nord, Süd, Ost, West)
    // ~40m in Breitengrad: 0.00036°, in Längengrad (~51°N): 0.00057°
    const double dLat = 0.00036;
    const double dLon = 0.00057;
    const double stepMeters = 40.0;

    final lats = <String>[];
    final lons = <String>[];

    for (final idx in uncachedIndices) {
      final c = centers[idx];
      // 0: Center, 1: North, 2: South, 3: East, 4: West
      lats.addAll([
        c.latitude.toStringAsFixed(4),
        (c.latitude + dLat).toStringAsFixed(4),
        (c.latitude - dLat).toStringAsFixed(4),
        c.latitude.toStringAsFixed(4),
        c.latitude.toStringAsFixed(4),
      ]);
      lons.addAll([
        c.longitude.toStringAsFixed(4),
        c.longitude.toStringAsFixed(4),
        c.longitude.toStringAsFixed(4),
        (c.longitude + dLon).toStringAsFixed(4),
        (c.longitude - dLon).toStringAsFixed(4),
      ]);
    }

    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/elevation', {
        'latitude': lats.join(','),
        'longitude': lons.join(','),
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final elevations = decoded['elevation'] as List<dynamic>? ?? const [];

        for (int k = 0; k < uncachedIndices.length; k++) {
          final base = k * 5;
          if (base + 4 >= elevations.length) break;

          final zC = (elevations[base] as num?)?.toDouble() ?? 0.0;
          final zN = (elevations[base + 1] as num?)?.toDouble() ?? zC;
          final zS = (elevations[base + 2] as num?)?.toDouble() ?? zC;
          final zE = (elevations[base + 3] as num?)?.toDouble() ?? zC;
          final zW = (elevations[base + 4] as num?)?.toDouble() ?? zC;

          // Gradient (dz/dx nach Osten, dz/dy nach Norden)
          final dzDx = (zE - zW) / (2.0 * stepMeters);
          final dzDy = (zN - zS) / (2.0 * stepMeters);
          final gradMag = math.sqrt(dzDx * dzDx + dzDy * dzDy);
          final slopeDeg = math.atan(gradMag) * (180.0 / math.pi);

          // Richtung des Gefälles (wohin der Hang abfällt: -dzDx, -dzDy)
          final downX = -dzDx;
          final downY = -dzDy;
          // Azimut in Grad (0° = Nord, 90° = Ost, 180° = Süd, 270° = West)
          final aspectDeg =
              (math.atan2(downX, downY) * (180.0 / math.pi) + 360.0) % 360.0;
          final aspectCardinal = _cardinalFromDegrees(aspectDeg);

          final sample = TerrainSlopeSample(
            elevationMeters: zC,
            slopeDegrees: slopeDeg,
            aspectCardinal: aspectCardinal,
          );

          final origIdx = uncachedIndices[k];
          final pt = centers[origIdx];
          final key =
              '${pt.latitude.toStringAsFixed(4)}_${pt.longitude.toStringAsFixed(4)}';
          _slopeCache[key] = sample;
          result[origIdx] = sample;
        }
      }
    } catch (_) {}

    return result;
  }

  static Future<SoilSubstrateProfile?> _fetchFromBgrBuek200(
    double safeLat,
    double safeLon,
  ) async {
    try {
      final minLon = (safeLon - 0.05).toStringAsFixed(2);
      final minLat = (safeLat - 0.05).toStringAsFixed(2);
      final maxLon = (safeLon + 0.05).toStringAsFixed(2);
      final maxLat = (safeLat + 0.05).toStringAsFixed(2);

      final uri = Uri.https(
        'services.bgr.de',
        '/arcgis/rest/services/boden/buek200/MapServer/identify',
        {
          'geometry': '$safeLon,$safeLat',
          'geometryType': 'esriGeometryPoint',
          'sr': '4326',
          'layers': 'all',
          'tolerance': '1',
          'mapExtent': '$minLon,$minLat,$maxLon,$maxLat',
          'imageDisplay': '400,400,96',
          'returnGeometry': 'false',
          'f': 'json',
        },
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final results = decoded['results'] as List<dynamic>? ?? const [];

      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        final attrs = item['attributes'] as Map<String, dynamic>? ?? const {};
        final rawLegend = attrs['Legendentext']?.toString();
        if (rawLegend != null &&
            rawLegend.isNotEmpty &&
            rawLegend != 'Null') {
          final cleaned = rawLegend.replaceAll('*', '').trim();
          return parseBgrLegendText(cleaned);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Parst den offiziellen Legendentext der BGR BÜK200 in ein strukturiertes
  /// [SoilSubstrateProfile] inklusive Grabfähigkeits-Klassifikation für Dachs & Fuchs.
  static SoilSubstrateProfile parseBgrLegendText(String cleanedLegend) {
    final lower = cleanedLegend.toLowerCase();

    // 1. Prüfung auf Staunässe, Grundwasserböden oder Moor
    final isDominantlyWet =
        lower.startsWith('vorherrschend moor') ||
        lower.startsWith('überwiegend moor') ||
        lower.contains('niedermoor') ||
        lower.contains('hochmoor') ||
        lower.contains('torf') ||
        lower.contains('nassgley') ||
        lower.contains('auenboden') ||
        (lower.contains('gley') && !lower.contains('gering verbreitet'));

    // 2. Prüfung auf flachgründigen Fels, Schutt oder schweren Ton
    final isRockyOrHeavyClay =
        lower.contains('pelosol') ||
        lower.contains('auenton') ||
        lower.contains('kalkstein') ||
        lower.contains('dolomit') ||
        lower.contains('tonschiefer') ||
        lower.contains('festgestein');

    // 3. Prüfung auf optimal grabfähige, trockene Sand-/Löss-/Braunerde-Substrate
    final isOptimalDrySandOrLoess =
        lower.contains('braunerde') ||
        lower.contains('parabraunerde') ||
        lower.contains('fahlerde') ||
        lower.contains('decksand') ||
        lower.contains('schmelzwassersand') ||
        lower.contains('löss') ||
        lower.contains('sandlöss') ||
        lower.contains('regosol');

    final SoilDiggability diggability;
    if (isDominantlyWet) {
      diggability = SoilDiggability.waterloggedOrPeat;
    } else if (isRockyOrHeavyClay && !isOptimalDrySandOrLoess) {
      diggability = SoilDiggability.rockyOrHeavyClay;
    } else if (isOptimalDrySandOrLoess) {
      diggability = SoilDiggability.optimalDryDiggable;
    } else {
      diggability = SoilDiggability.moderateLoam;
    }

    // Kompakten Kurznamen (Bodentyp + Ausgangssubstrat) extrahieren
    final soilType = _extractPrimarySoilType(lower);
    final substrate = _extractPrimarySubstrate(lower);
    final shortLabel = substrate.isNotEmpty
        ? '$soilType aus $substrate'
        : soilType;

    return SoilSubstrateProfile(
      shortLabel: shortLabel,
      fullGeologicalDescription: cleanedLegend,
      dataSource: 'BGR BÜK200 (Geologie)',
      diggability: diggability,
    );
  }

  static String _extractPrimarySoilType(String lower) {
    if (lower.contains('moor')) return 'Moorboden';
    if (lower.contains('parabraunerde')) return 'Parabraunerde';
    if (lower.contains('podsol-braunerde') || lower.contains('podsolige braunerde')) {
      return 'Podsol-Braunerde';
    }
    if (lower.contains('braunerde')) return 'Braunerde';
    if (lower.contains('fahlerde')) return 'Fahlerde';
    if (lower.contains('vega') || lower.contains('vegen')) return 'Auen-Vega';
    if (lower.contains('gley')) return 'Gley (Grundwasserboden)';
    if (lower.contains('pseudogley')) return 'Pseudogley (Stauwasser)';
    if (lower.contains('rendzina') || lower.contains('pararendzina')) {
      return 'Rendzina';
    }
    if (lower.contains('schwarzerde') || lower.contains('tschernosem')) {
      return 'Schwarzerde';
    }
    if (lower.contains('pelosol')) return 'Pelosol (Tonboden)';
    return 'Waldboden';
  }

  static String _extractPrimarySubstrate(String lower) {
    if (lower.contains('lösslehm') || lower.contains('löss')) return 'Lösslehm';
    if (lower.contains('geschiebedecksand') || lower.contains('decksand')) {
      return 'Decksand';
    }
    if (lower.contains('schmelzwassersand')) return 'Schmelzwassersand';
    if (lower.contains('geschiebemergel') || lower.contains('geschiebelehm')) {
      return 'Geschiebelehm';
    }
    if (lower.contains('auenschluff') || lower.contains('auenlehm')) {
      return 'Auenlehm';
    }
    if (lower.contains('torf')) return 'Torf';
    if (lower.contains('sandstein')) return 'Sandstein-Verwitterung';
    if (lower.contains('kalkstein')) return 'Kalkstein';
    if (lower.contains('sand')) return 'Sand';
    if (lower.contains('lehm')) return 'Lehm';
    return '';
  }

  static Future<SoilSubstrateProfile?> _fetchFromIsricSoilGrids(
    double safeLat,
    double safeLon,
  ) async {
    try {
      final uri = Uri(
        scheme: 'https',
        host: 'rest.isric.org',
        path: '/soilgrids/v2.0/properties/query',
        query:
            'lon=$safeLon&lat=$safeLat&property=sand&property=silt&property=clay&depth=15-30cm&value=mean',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final props = decoded['properties'] as Map<String, dynamic>? ?? const {};
      final layers = props['layers'] as List<dynamic>? ?? const [];

      double? sandPct;
      double? siltPct;
      double? clayPct;

      for (final layer in layers) {
        if (layer is! Map<String, dynamic>) continue;
        final name = layer['name']?.toString();
        final depths = layer['depths'] as List<dynamic>? ?? const [];
        if (depths.isEmpty) continue;
        final firstDepth = depths.first as Map<String, dynamic>? ?? const {};
        final values = firstDepth['values'] as Map<String, dynamic>? ?? const {};
        final rawMean = (values['mean'] as num?)?.toDouble();
        if (rawMean == null) continue;
        // SoilGrids liefert g/kg (d_factor = 10 -> durch 10 teilen für %)
        final pct = rawMean / 10.0;
        if (name == 'sand') sandPct = pct;
        if (name == 'silt') siltPct = pct;
        if (name == 'clay') clayPct = pct;
      }

      if (sandPct == null && clayPct == null) return null;

      final s = sandPct ?? 45.0;
      final u = siltPct ?? 35.0;
      final c = clayPct ?? 20.0;

      final SoilDiggability diggability;
      final String textureLabel;
      if (c >= 35.0) {
        diggability = SoilDiggability.rockyOrHeavyClay;
        textureLabel = 'Schwerer Tonlehm';
      } else if (s >= 45.0 && c <= 22.0) {
        diggability = SoilDiggability.optimalDryDiggable;
        textureLabel = 'Sandiger Lehm / Waldsand';
      } else {
        diggability = SoilDiggability.moderateLoam;
        textureLabel = 'Schluffiger Lehm';
      }

      return SoilSubstrateProfile(
        shortLabel:
            '$textureLabel (${s.round()}% Sand, ${u.round()}% Schluff, ${c.round()}% Ton)',
        fullGeologicalDescription:
            'Korngrößenverteilung in 15–30 cm Grabtiefe: ${s.toStringAsFixed(0)} % Sand, ${u.toStringAsFixed(0)} % Schluff, ${c.toStringAsFixed(0)} % Ton.',
        dataSource: 'ISRIC SoilGrids (15–30cm)',
        diggability: diggability,
        sandPercent: s,
        siltPercent: u,
        clayPercent: c,
      );
    } catch (_) {}
    return null;
  }

  static SoilSubstrateProfile _fallbackSoilProfile() {
    return const SoilSubstrateProfile(
      shortLabel: 'Humoser Waldboden (Lehm-Sand)',
      fullGeologicalDescription:
          'Typischer mitteleuropäischer Waldboden (Offline-Profil).',
      dataSource: 'Offline-Bodenmodell',
      diggability: SoilDiggability.unknown,
    );
  }

  static String _cardinalFromDegrees(double deg) {
    const dirs = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
    final idx = ((deg + 22.5) % 360 / 45).floor();
    return dirs[idx % 8];
  }
}
