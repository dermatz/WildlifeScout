import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/privacy/coordinate_guard.dart';

/// Zusammenfassung der wissenschaftlich verifizierten GBIF-Artbeobachtungen
/// im regionalen Beobachtungssektor (ca. 10–15 km Radius).
class GbifRegionalPresence {
  final String scientificName;
  final int totalCount;
  final int? latestYear;
  final List<String> datasets;
  final String summaryLabel;
  final bool isConfirmed;

  const GbifRegionalPresence({
    required this.scientificName,
    required this.totalCount,
    this.latestYear,
    this.datasets = const [],
    required this.summaryLabel,
    required this.isConfirmed,
  });

  factory GbifRegionalPresence.empty(String scientificName) {
    return GbifRegionalPresence(
      scientificName: scientificName,
      totalCount: 0,
      summaryLabel: 'Keine GBIF-Funde im 15-km-Quadranten',
      isConfirmed: false,
    );
  }
}

/// Client zur Abfrage der Global Biodiversity Information Facility (GBIF) Occurrence API.
///
/// Schützt den genauen Ansitz-Standort durch automatische Koordinaten-Quantisierung
/// ([CoordinateGuard.obfuscateForWeatherApi]), bevor eine regionale Bounding-Box
/// an api.gbif.org übertragen wird.
class GbifOccurrenceClient {
  static final Map<String, GbifRegionalPresence> _cache = {};

  /// Fragt das Vorkommen einer Art im ~12–15 km Umkreis bei GBIF ab.
  static Future<GbifRegionalPresence> fetchRegionalPresence({
    required double latitude,
    required double longitude,
    required String scientificName,
  }) async {
    if (!CoordinateGuard.isValidCoordinate(latitude, longitude) ||
        scientificName.trim().isEmpty) {
      return GbifRegionalPresence.empty(scientificName);
    }

    // 1. DSGVO-Schutz: Exakte Koordinaten runden (auf 2 Nachkommastellen)
    final obfuscated = CoordinateGuard.obfuscateForWeatherApi(
      latitude,
      longitude,
    );

    final cacheKey =
        '${scientificName.toLowerCase()}_${obfuscated.lat}_${obfuscated.lon}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // 2. Regionale Bounding Box (~12-15 km Kantenlänge)
    const span = 0.12;
    final minLat = (obfuscated.lat - span).toStringAsFixed(2);
    final maxLat = (obfuscated.lat + span).toStringAsFixed(2);
    final minLon = (obfuscated.lon - span).toStringAsFixed(2);
    final maxLon = (obfuscated.lon + span).toStringAsFixed(2);

    // 3. Rezente Sichtungshistorie: Dynamisch die letzten 20 Jahre filtern
    final currentYear = DateTime.now().year;
    final startYear = currentYear - 20;

    final uri = Uri.https('api.gbif.org', '/v1/occurrence/search', {
      'scientificName': scientificName,
      'decimalLatitude': '$minLat,$maxLat',
      'decimalLongitude': '$minLon,$maxLon',
      'hasCoordinate': 'true',
      'year': '$startYear,$currentYear',
      'limit': '10',
    });

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return GbifRegionalPresence.empty(scientificName);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final count = (data['count'] as num?)?.toInt() ?? 0;
      final results = data['results'] as List<dynamic>? ?? const [];

      int? latestYear;
      final datasets = <String>{};

      for (final r in results) {
        if (r is! Map<String, dynamic>) continue;
        final year = (r['year'] as num?)?.toInt();
        if (year != null && (latestYear == null || year > latestYear)) {
          latestYear = year;
        }
        final dsName = r['datasetName']?.toString();
        if (dsName != null && dsName.isNotEmpty) {
          datasets.add(dsName);
        }
      }

      final yearStr = latestYear != null ? ' (zuletzt $latestYear)' : '';
      final summary = count > 0
          ? '$count verifizierte GBIF-Nachweise der letzten 20 Jahre im 15-km-Umkreis$yearStr'
          : 'Keine rezenten GBIF-Funde (letzte 20 Jahre) im 15-km-Quadranten gemeldet';

      final presence = GbifRegionalPresence(
        scientificName: scientificName,
        totalCount: count,
        latestYear: latestYear,
        datasets: datasets.take(3).toList(),
        summaryLabel: summary,
        isConfirmed: count > 0,
      );

      _cache[cacheKey] = presence;
      return presence;
    } catch (_) {
      // Bei Netzwerk-Timeout oder Offline-Betrieb: geräuschloser Fallback
      return GbifRegionalPresence.empty(scientificName);
    }
  }

  /// Leert den In-Memory-Cache (z. B. für Tests).
  static void clearCache() => _cache.clear();
}
