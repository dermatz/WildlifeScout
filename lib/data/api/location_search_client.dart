import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/privacy/coordinate_guard.dart';
import '../services/nearby_nature_regions_service.dart';

class LocationSearchResult {
  final String title;
  final String subtitle;
  final LatLng coordinate;
  final String categoryLabel;

  const LocationSearchResult({
    required this.title,
    required this.subtitle,
    required this.coordinate,
    required this.categoryLabel,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationSearchResult &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          subtitle == other.subtitle &&
          coordinate.latitude == other.coordinate.latitude &&
          coordinate.longitude == other.coordinate.longitude &&
          categoryLabel == other.categoryLabel;

  @override
  int get hashCode => Object.hash(
        title,
        subtitle,
        coordinate.latitude,
        coordinate.longitude,
        categoryLabel,
      );
}

/// DSGVO-freundliche Orts-, Wald- und Gebietssuche über OpenStreetMap Nominatim,
/// Fallback über Open-Meteo Geocoding, kuratierte Offline-Naturgebiete
/// sowie direkte GPS-Koordinaten-Erkennung.
class LocationSearchClient {
  /// Gültiger User-Agent gemäß OpenStreetMap Nominatim Usage Policy
  static const String userAgent =
      'WildlifeScout/1.0 (https://github.com/melle/wildlifescout; contact: support@wildlifescout.app)';

  final http.Client _httpClient;

  LocationSearchClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Parst direkte GPS-Koordinaten in unterschiedlichen Formaten
  /// (z. B. "51.234, 9.876", "51,234 9,876", "51.234; 9.876", "N 51.234, E 9.876").
  /// Gibt null zurück, wenn kein gültiges Koordinatenpaar vorliegt.
  LatLng? parseDirectCoordinates(String rawQuery) {
    var query = rawQuery.trim();
    if (query.isEmpty) return null;

    // Entferne Himmelsrichtungs-Präfixe wie N, S, E, W, O
    var clean = query
        .replaceAll(RegExp(r'^[NSEWO]\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[,;/]\s*[NSEWO]\s*', caseSensitive: false), ', ');

    final coordMatch = RegExp(
      r'^(-?\d+[.,]\d+)\s*[,;/\s]\s*(-?\d+[.,]\d+)$',
    ).firstMatch(clean);

    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!.replaceAll(',', '.'));
      final lon = double.tryParse(coordMatch.group(2)!.replaceAll(',', '.'));
      if (lat != null &&
          lon != null &&
          lat >= -90 &&
          lat <= 90 &&
          lon >= -180 &&
          lon <= 180) {
        return LatLng(lat, lon);
      }
    }
    return null;
  }

  /// Sucht nach Orten, Wäldern, Naturschutzgebieten oder parst direkte
  /// GPS-Koordinaten (z. B. "51.234, 9.876").
  Future<List<LocationSearchResult>> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const [];

    // 1. Prüfe auf direkte GPS-Koordinaten-Eingabe (z.B. "51.123, 10.456")
    final direct = parseDirectCoordinates(query);
    if (direct != null) {
      return [
        LocationSearchResult(
          title: 'Direkte GPS-Koordinate',
          subtitle:
              '${direct.latitude.toStringAsFixed(5)}, ${direct.longitude.toStringAsFixed(5)}',
          coordinate: direct,
          categoryLabel: 'GPS-Direkt',
        ),
      ];
    }

    // 2. Lokale Treffer aus kuratierten Naturgebieten (sofort & offline verfügbar)
    final localMatches = _findMatchingLocalRegions(query);

    // 3. OpenStreetMap Nominatim Suche mit gültigem User-Agent
    final nominatimResults = await _searchNominatim(query);

    // 4. Falls Nominatim fehlschlägt oder keine Treffer hat: Open-Meteo Geocoding
    List<LocationSearchResult> openMeteoResults = const [];
    if (nominatimResults.isEmpty) {
      openMeteoResults = await _searchOpenMeteo(query);
    }

    // 5. Ergebnisse zusammenführen und deduplizieren
    final combined = <LocationSearchResult>[];
    final seen = <String>{};

    void addResult(LocationSearchResult r) {
      final key =
          '${r.title.toLowerCase().trim()}_${r.coordinate.latitude.toStringAsFixed(2)}_${r.coordinate.longitude.toStringAsFixed(2)}';
      if (seen.add(key)) {
        combined.add(r);
      }
    }

    for (final r in localMatches) {
      addResult(r);
    }
    for (final r in nominatimResults) {
      addResult(r);
    }
    for (final r in openMeteoResults) {
      addResult(r);
    }

    return combined;
  }

  List<LocationSearchResult> _findMatchingLocalRegions(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.length < 3) return const [];

    final matches = <LocationSearchResult>[];
    for (final reg in NearbyNatureRegionsService.allRegions) {
      final name = reg.name.toLowerCase();
      final cat = reg.category.toLowerCase();
      final state = reg.state.toLowerCase();
      if (name.contains(clean) ||
          cat.contains(clean) ||
          (clean.length >= 4 && state.contains(clean))) {
        matches.add(
          LocationSearchResult(
            title: reg.name,
            subtitle: '${reg.state} • ${reg.category}',
            coordinate: reg.coordinate,
            categoryLabel: reg.categoryLabel,
          ),
        );
        if (matches.length >= 3) break;
      }
    }
    return matches;
  }

  Future<List<LocationSearchResult>> _searchNominatim(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '8',
        'addressdetails': '1',
        'accept-language': 'de',
      });

      final response = await _httpClient
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': userAgent,
            },
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return [];

      final list = jsonDecode(response.body) as List<dynamic>;
      final results = <LocationSearchResult>[];

      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        if (lat == null || lon == null) continue;

        final displayName =
            item['display_name']?.toString() ?? 'Unbekannter Ort';
        final parts = displayName.split(',').map((s) => s.trim()).toList();
        final rawName = item['name']?.toString();
        final title = (rawName != null && rawName.isNotEmpty)
            ? rawName
            : parts.first;
        final subtitle = parts.length > 1
            ? parts.skip(1).take(3).join(', ')
            : displayName;
        final type = item['type']?.toString();
        final cat = item['category']?.toString();
        final typeLabel = _mapOsmTypeToCategory(type, cat);

        results.add(
          LocationSearchResult(
            title: title,
            subtitle: subtitle,
            coordinate: LatLng(lat, lon),
            categoryLabel: typeLabel,
          ),
        );
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  Future<List<LocationSearchResult>> _searchOpenMeteo(String query) async {
    final cleanQuery = query.replaceAll(RegExp(r'[-–—]+$'), '').trim();
    final effectiveQuery = cleanQuery.isNotEmpty ? cleanQuery : query;

    try {
      final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': effectiveQuery,
        'count': '8',
        'language': 'de',
        'format': 'json',
      });

      final response = await _httpClient
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': userAgent,
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final resultsList = data['results'] as List<dynamic>?;
      if (resultsList == null) return [];

      final list = <LocationSearchResult>[];
      for (final item in resultsList) {
        if (item is! Map<String, dynamic>) continue;
        final lat = (item['latitude'] as num?)?.toDouble();
        final lon = (item['longitude'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;

        final name = item['name']?.toString() ?? 'Unbekannter Ort';
        final adminParts = [
          item['admin3']?.toString(),
          item['admin1']?.toString(),
          item['country']?.toString(),
        ].where((s) => s != null && s.isNotEmpty).cast<String>().toList();

        final subtitle =
            adminParts.isNotEmpty ? adminParts.join(', ') : name;
        final featureCode = item['feature_code']?.toString() ?? '';
        final category = _mapFeatureCodeToCategory(featureCode);

        list.add(
          LocationSearchResult(
            title: name,
            subtitle: subtitle,
            coordinate: LatLng(lat, lon),
            categoryLabel: category,
          ),
        );
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  static String _mapFeatureCodeToCategory(String featureCode) {
    if (featureCode.startsWith('MTS') || featureCode.startsWith('PK')) {
      return 'Gipfel / Berg';
    } else if (featureCode.startsWith('FRST') ||
        featureCode.startsWith('WDLND')) {
      return 'Waldgebiet';
    } else if (featureCode.startsWith('LK') ||
        featureCode.startsWith('RESW') ||
        featureCode.startsWith('STM')) {
      return 'Gewässer';
    } else if (featureCode.startsWith('PRK') ||
        featureCode.startsWith('RESN')) {
      return 'Naturschutz';
    } else if (featureCode.startsWith('PPLA') ||
        featureCode.startsWith('PPLC')) {
      return 'Stadt';
    } else if (featureCode.startsWith('PPL')) {
      return 'Ort';
    }
    return 'Ort';
  }

  static String _mapOsmTypeToCategory(String? type, String? category) {
    if (type == null) return 'Ort';
    final t = type.toLowerCase();
    final c = category?.toLowerCase() ?? '';
    if (t == 'forest' || t == 'wood' || (c == 'natural' && t == 'tree')) {
      return 'Wald';
    }
    if (t == 'nature_reserve' ||
        t == 'national_park' ||
        t == 'protected_area') {
      return 'Naturschutz';
    }
    if (t == 'water' || t == 'lake' || t == 'river' || t == 'reservoir') {
      return 'Gewässer';
    }
    if (t == 'peak' ||
        t == 'volcano' ||
        t == 'mountain_range' ||
        t == 'hill') {
      return 'Gipfel / Berg';
    }
    if (t == 'city' || t == 'town') {
      return 'Stadt';
    }
    if (t == 'village' ||
        t == 'hamlet' ||
        t == 'suburb' ||
        t == 'administrative') {
      return 'Ort';
    }
    return 'Ort';
  }

  /// Ermittelt über Nominatim (DSGVO-konform auf 2 Nachkommastellen gerundet)
  /// den Orts- oder Gebietsnamen zum aktuellen Standort mit Fallback auf Naturgebiete.
  Future<String?> reverseGeocodeRegionName(LatLng coord) async {
    final safe = CoordinateGuard.obfuscateForWeatherApi(
      coord.latitude,
      coord.longitude,
    );
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': safe.lat.toString(),
        'lon': safe.lon.toString(),
        'format': 'jsonv2',
        'zoom': '13',
        'accept-language': 'de',
      });

      final response = await _httpClient
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': userAgent,
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final place = address['forest'] ??
              address['nature_reserve'] ??
              address['village'] ??
              address['town'] ??
              address['city'] ??
              address['municipality'] ??
              address['county'];
          if (place != null && place.toString().trim().isNotEmpty) {
            return place.toString().trim();
          }
        }
        final name = data['name']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {}

    // Fallback auf kuratierte Naturgebiete in der Nähe
    try {
      final nearby = NearbyNatureRegionsService.findNearby(
        userCoordinate: coord,
        maxRadiusKm: 20,
        limit: 1,
      );
      if (nearby.isNotEmpty && nearby.first.distanceKm <= 15) {
        return nearby.first.region.name;
      }
    } catch (_) {}

    return null;
  }
}
