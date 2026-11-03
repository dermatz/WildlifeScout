import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service zur dynamischen Bereitstellung von hochperformanten,
/// DSGVO-konformen Live-Niederschlagsradarkacheln für Deutschland & Europa.
///
/// Nutzt den offenen Radar-Verbund (inkl. DWD-Radarstationen) via Edge-Tile-Cache,
/// um WMS-Server-Timeouts und Browser-Decodierfehler (AbortError) zu vermeiden.
class RainRadarService {
  static const String _metadataUrl =
      'https://api.rainviewer.com/public/weather-maps.json';

  static String? _cachedUrlTemplate;
  static DateTime? _cacheTimestamp;

  /// Ruft das aktuellste Kachel-URL-Template ab (z. B. 'https://tilecache.rainviewer.com/v2/radar/.../256/{z}/{x}/{y}/2/1_1.png').
  /// Das Ergebnis wird für 5 Minuten gecacht.
  static Future<String?> fetchLatestRadarUrlTemplate({
    http.Client? client,
  }) async {
    final now = DateTime.now();
    if (_cachedUrlTemplate != null &&
        _cacheTimestamp != null &&
        now.difference(_cacheTimestamp!).inMinutes < 5) {
      return _cachedUrlTemplate;
    }

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(Uri.parse(_metadataUrl))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final host =
            data['host'] as String? ?? 'https://tilecache.rainviewer.com';
        final radar = data['radar'] as Map<String, dynamic>?;
        final past = radar?['past'] as List<dynamic>?;

        if (past != null && past.isNotEmpty) {
          final latest = past.last as Map<String, dynamic>;
          final path = latest['path'] as String?;
          if (path != null && path.isNotEmpty) {
            // Farbschema 2: Universelles Wetterradar (Blau -> Grün -> Gelb -> Rot)
            // 1_1: Geglättet mit Schneemaskierung
            final template = '$host$path/256/{z}/{x}/{y}/2/1_1.png';
            _cachedUrlTemplate = template;
            _cacheTimestamp = now;
            return template;
          }
        }
      }
    } catch (_) {
      // Graceful degradation: Bestehenden Cache oder null zurückgeben
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }

    return _cachedUrlTemplate;
  }

  /// Setzt den Cache für Unit-Tests zurück.
  static void resetCacheForTesting() {
    _cachedUrlTemplate = null;
    _cacheTimestamp = null;
  }
}
