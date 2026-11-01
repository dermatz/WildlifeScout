import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/privacy/coordinate_guard.dart';
import 'device_location_stub.dart'
    if (dart.library.js_interop) 'device_location_web.dart';

class DeviceLocationResult {
  final LatLng coordinate;
  final String? label;
  final bool isExactGps;

  const DeviceLocationResult({
    required this.coordinate,
    this.label,
    required this.isExactGps,
  });
}

class DeviceLocationService {
  static const String _lastLatKey = 'wildlifescout_last_user_lat_v1';
  static const String _lastLonKey = 'wildlifescout_last_user_lon_v1';
  static const String _lastTitleKey = 'wildlifescout_last_user_title_v1';
  static const String _legacyLastLatKey = 'wildscout_last_user_lat_v1';
  static const String _legacyLastLonKey = 'wildscout_last_user_lon_v1';
  static const String _legacyLastTitleKey = 'wildscout_last_user_title_v1';

  /// Lädt den zuletzt verwendeten Standort aus dem lokalen Speicher, damit
  /// die Karte sofort ohne Sprung am richtigen Ort startet.
  static Future<DeviceLocationResult?> loadLastSavedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_lastLatKey) ?? prefs.getDouble(_legacyLastLatKey);
      final lon = prefs.getDouble(_lastLonKey) ?? prefs.getDouble(_legacyLastLonKey);
      final title = prefs.getString(_lastTitleKey) ?? prefs.getString(_legacyLastTitleKey);
      if (lat != null &&
          lon != null &&
          CoordinateGuard.isValidCoordinate(lat, lon)) {
        // Ignoriere alten Schorfheide-Default (52.9742, 13.7562)
        if ((lat - 52.9742).abs() < 0.001 && (lon - 13.7562).abs() < 0.001) {
          return null;
        }
        return DeviceLocationResult(
          coordinate: LatLng(lat, lon),
          label: title,
          isExactGps: false,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveLastLocation(LatLng coordinate, String title) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_lastLatKey, coordinate.latitude);
      await prefs.setDouble(_lastLonKey, coordinate.longitude);
      await prefs.setString(_lastTitleKey, title);
    } catch (_) {}
  }

  /// Ermittelt den aktuellen Standort:
  /// 1. Primär über echte Geräte-/Browser-Geolocation (GPS / WLAN).
  /// 2. Falls im Browser/OS blockiert oder nicht verfügbar: grobe IP-basierte
  ///    Standortbestimmung als Fallback, damit man nicht an einem fremden
  ///    Dummy-Ort landet.
  static Future<DeviceLocationResult?> determineCurrentLocation() async {
    final gpsCoord = await getBrowserGeolocation();
    if (gpsCoord != null &&
        CoordinateGuard.isValidCoordinate(
          gpsCoord.latitude,
          gpsCoord.longitude,
        )) {
      return DeviceLocationResult(
        coordinate: gpsCoord,
        isExactGps: true,
      );
    }

    final ipFallback = await _fetchApproximateIpLocation();
    if (ipFallback != null) {
      return ipFallback;
    }

    return null;
  }

  static Future<DeviceLocationResult?> _fetchApproximateIpLocation() async {
    try {
      final res = await http
          .get(
            Uri.parse('https://get.geojs.io/v1/ip/geo.json'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final lat = double.tryParse(data['latitude']?.toString() ?? '');
        final lon = double.tryParse(data['longitude']?.toString() ?? '');
        final city = data['city']?.toString();
        if (lat != null &&
            lon != null &&
            CoordinateGuard.isValidCoordinate(lat, lon)) {
          return DeviceLocationResult(
            coordinate: LatLng(lat, lon),
            label: (city != null && city.isNotEmpty)
                ? 'Aktueller Standort ($city)'
                : 'Aktueller Standort',
            isExactGps: false,
          );
        }
      }
    } catch (_) {}
    return null;
  }
}
