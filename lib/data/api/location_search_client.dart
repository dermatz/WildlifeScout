import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/privacy/coordinate_guard.dart';

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
}

/// DSGVO-freundliche Orts-, Wald- und Gebietssuche über OpenStreetMap Nominatim
/// sowie direkte GPS-Koordinaten-Erkennung.
class LocationSearchClient {
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
          subtitle: '${direct.latitude.toStringAsFixed(5)}, ${direct.longitude.toStringAsFixed(5)}',
          coordinate: direct,
          categoryLabel: 'GPS-Direkt',
        ),
      ];
    }

    // 2. OpenStreetMap Nominatim Geocoding-Suche
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '8',
        'addressdetails': '1',
        'accept-language': 'de',
      });

      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
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

        final displayName = item['display_name']?.toString() ?? 'Unbekannter Ort';
        final parts = displayName.split(',').map((s) => s.trim()).toList();
        final title = parts.first;
        final subtitle = parts.length > 1
            ? parts.skip(1).take(3).join(', ')
            : displayName;
        final typeLabel = item['type']?.toString() ?? 'Ort';

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

  /// Ermittelt über Nominatim (DSGVO-konform auf 2 Nachkommastellen gerundet)
  /// den Orts- oder Gebietsnamen zum aktuellen Standort.
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

      final response = await http
          .get(
            uri,
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return null;
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
    } catch (_) {}
    return null;
  }
}
