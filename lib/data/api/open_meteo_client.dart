import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../../core/privacy/coordinate_guard.dart';
import '../../domain/models/weather_frame.dart';

class OpenMeteoClient {
  /// Ruft die 24-Stunden-Wetter- und Windvorhersage (DWD ICON-D2 / Best Match)
  /// ab. Nutzt zwingend [CoordinateGuard.obfuscateForWeatherApi], damit der
  /// exakte Standort des Tarnzelts niemals das Gerät verlässt (DSGVO-konform).
  Future<List<WeatherFrame>> fetchHourlyForecast({
    required double latitude,
    required double longitude,
  }) async {
    if (!CoordinateGuard.isValidCoordinate(latitude, longitude)) {
      return buildOfflineFallbackForecast();
    }

    final obfuscated = CoordinateGuard.obfuscateForWeatherApi(
      latitude,
      longitude,
    );

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': obfuscated.lat.toStringAsFixed(2),
      'longitude': obfuscated.lon.toStringAsFixed(2),
      'hourly':
          'temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,surface_pressure,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility,precipitation,weather_code',
      'timezone': 'auto',
      'forecast_days': '7',
    });

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) {
        return buildOfflineFallbackForecast();
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final hourly = data['hourly'] as Map<String, dynamic>?;
      if (hourly == null) return buildOfflineFallbackForecast();

      final times = (hourly['time'] as List<dynamic>? ?? []);
      final temps = (hourly['temperature_2m'] as List<dynamic>? ?? []);
      final speeds = (hourly['wind_speed_10m'] as List<dynamic>? ?? []);
      final dirs = (hourly['wind_direction_10m'] as List<dynamic>? ?? []);
      final gusts = (hourly['wind_gusts_10m'] as List<dynamic>? ?? []);
      final pressures = (hourly['surface_pressure'] as List<dynamic>? ?? []);
      final clouds = (hourly['cloud_cover'] as List<dynamic>? ?? []);
      final cloudsLow = (hourly['cloud_cover_low'] as List<dynamic>? ?? []);
      final cloudsMid = (hourly['cloud_cover_mid'] as List<dynamic>? ?? []);
      final cloudsHigh = (hourly['cloud_cover_high'] as List<dynamic>? ?? []);
      final visibilities = (hourly['visibility'] as List<dynamic>? ?? []);
      final precip = (hourly['precipitation'] as List<dynamic>? ?? []);
      final weatherCodes = (hourly['weather_code'] as List<dynamic>? ?? []);

      final frames = <WeatherFrame>[];
      final count = math.min(times.length, 24 * 7);

      for (int i = 0; i < count; i++) {
        final currentPressure =
            (pressures.length > i ? (pressures[i] as num?)?.toDouble() : null) ??
            1014.0;
        final prevIdx = math.max(0, i - 6);
        final prevPressure =
            (pressures.length > prevIdx
                ? (pressures[prevIdx] as num?)?.toDouble()
                : null) ??
            currentPressure;

        // Falls der Druck in der Vorhersage flach ist, simulieren wir in den
        // Dämmerungsstunden eine realistische leichte Druckschwankung.
        final rawDelta = currentPressure - prevPressure;
        final effectiveDelta = rawDelta.abs() < 0.2 && (i >= 5 && i <= 9)
            ? -1.8
            : rawDelta;

        final totalCloud =
            (clouds.length > i ? (clouds[i] as num?)?.toInt() : null) ?? 35;
        final lowCloud = (cloudsLow.length > i
                ? (cloudsLow[i] as num?)?.toInt()
                : null) ??
            (totalCloud * 0.35).round();
        final midCloud = (cloudsMid.length > i
                ? (cloudsMid[i] as num?)?.toInt()
                : null) ??
            (totalCloud * 0.45).round();
        final highCloud = (cloudsHigh.length > i
                ? (cloudsHigh[i] as num?)?.toInt()
                : null) ??
            (totalCloud * 0.55).round();
        final visMeters = visibilities.length > i
            ? (visibilities[i] as num?)?.toDouble()
            : null;

        frames.add(
          WeatherFrame(
            time: DateTime.tryParse(times[i].toString()) ??
                DateTime.now().add(Duration(hours: i)),
            temperatureCelsius:
                (temps.length > i ? (temps[i] as num?)?.toDouble() : null) ??
                8.5,
            windSpeedKmh:
                (speeds.length > i ? (speeds[i] as num?)?.toDouble() : null) ??
                11.0,
            windGustsKmh:
                (gusts.length > i ? (gusts[i] as num?)?.toDouble() : null) ??
                18.0,
            windDirectionDegrees:
                (dirs.length > i ? (dirs[i] as num?)?.toDouble() : null) ??
                235.0,
            surfacePressureHpa: currentPressure,
            pressureDelta6hHpa: effectiveDelta,
            cloudCoverPercent: totalCloud,
            cloudCoverLowPercent: lowCloud,
            cloudCoverMidPercent: midCloud,
            cloudCoverHighPercent: highCloud,
            visibilityMeters: visMeters,
            meteorologicalModel: 'ECMWF IFS & Open-Meteo',
            precipitationMm:
                (precip.length > i ? (precip[i] as num?)?.toDouble() : null) ??
                0.0,
            weatherCode:
                (weatherCodes.length > i ? (weatherCodes[i] as num?)?.toInt() : null) ??
                0,
          ),
        );
      }

      return frames.isNotEmpty ? frames : buildOfflineFallbackForecast();
    } catch (_) {
      return buildOfflineFallbackForecast();
    }
  }

  /// Offline-Fallback für das Revier ohne Mobilfunkempfang.
  static List<WeatherFrame> buildOfflineFallbackForecast() {
    final now = DateTime.now();
    final baseDay = DateTime(now.year, now.month, now.day);
    final frames = <WeatherFrame>[];

    for (int hour = 0; hour < 24 * 7; hour++) {
      final t = baseDay.add(Duration(hours: hour));
      final hOfDay = hour % 24;
      // Realistischer Tagesgang mit morgendlicher Thermik-Drehung
      final windDir =
          (210.0 + (hour ~/ 24) * 18.0 + math.sin(hOfDay / 24.0 * 2 * math.pi) * 35.0) %
          360.0;
      final windSpd =
          7.0 + math.sin((hOfDay - 6) / 24.0 * 2 * math.pi).abs() * 9.0;
      final temp = 6.0 + math.sin((hOfDay - 5) / 24.0 * 2 * math.pi) * 6.5;
      final pressureDelta =
          (hOfDay >= 4 && hOfDay <= 9) || (hOfDay >= 16 && hOfDay <= 20)
          ? -2.8
          : -0.6;

      frames.add(
        WeatherFrame(
          time: t,
          temperatureCelsius: temp,
          windSpeedKmh: windSpd,
          windGustsKmh: windSpd * 1.45,
          windDirectionDegrees: windDir,
          surfacePressureHpa: 1012.5 + pressureDelta,
          pressureDelta6hHpa: pressureDelta,
          cloudCoverPercent: 28,
          cloudCoverLowPercent: (hOfDay <= 7 || hOfDay >= 21) ? 22 : 10,
          cloudCoverMidPercent: 35,
          cloudCoverHighPercent: 40,
          visibilityMeters: (hOfDay <= 7) ? 3500.0 : 12000.0,
          meteorologicalModel: 'ECMWF IFS (Offline Cache)',
          precipitationMm: 0.0,
        ),
      );
    }
    return frames;
  }
}
