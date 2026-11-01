import 'package:flutter/material.dart';
import '../../core/theme/wildscout_theme.dart';
import '../../data/services/app_settings_service.dart';
import 'weather_frame.dart';

/// Art des Unwetters / der Wettergefahr am Fotospot.
enum SevereWeatherType {
  thunderstorm,
  stormGusts,
  heavyRain,
  squallFront,
}

/// Gefahrenstufe für die Fotosession im Naturgebiet.
enum SevereWeatherSeverity {
  warning, // Warnung: Vorsicht & Vorbereitung zum Abbruch
  danger, // Akute Gefahr: Fotosession sofort abbrechen / Schutz suchen
}

/// Detaillierte Unwetter-Warnung für die aktive Fotosession.
class SevereWeatherAlert {
  final SevereWeatherType type;
  final SevereWeatherSeverity severity;
  final String headline;
  final String subheadline;
  final String description;
  final String safetyRecommendation;
  final double peakGustKmh;
  final double precipitationMm;
  final int weatherCode;
  final DateTime eventTime;
  final int hoursUntilEvent; // 0 = aktuell/jetzt, >0 = in X Stunden

  const SevereWeatherAlert({
    required this.type,
    required this.severity,
    required this.headline,
    required this.subheadline,
    required this.description,
    required this.safetyRecommendation,
    required this.peakGustKmh,
    required this.precipitationMm,
    required this.weatherCode,
    required this.eventTime,
    required this.hoursUntilEvent,
  });

  bool get isImminent => hoursUntilEvent <= 1;
  bool get isDanger => severity == SevereWeatherSeverity.danger;

  Color get accentColor =>
      isDanger ? WildScoutTheme.crimsonScent : WildScoutTheme.amberGold;

  IconData get icon {
    switch (type) {
      case SevereWeatherType.thunderstorm:
        return Icons.thunderstorm_rounded;
      case SevereWeatherType.stormGusts:
        return Icons.air_rounded;
      case SevereWeatherType.heavyRain:
        return Icons.water_drop_rounded;
      case SevereWeatherType.squallFront:
        return Icons.cyclone_rounded;
    }
  }

  String get timeLabel {
    if (hoursUntilEvent == 0) {
      return 'Jetzt aktiv';
    } else if (hoursUntilEvent == 1) {
      return 'In ca. 1 Stunde';
    } else {
      return 'In ca. $hoursUntilEvent Stunden (${eventTime.hour.toString().padLeft(2, '0')}:00 Uhr)';
    }
  }
}

/// Analysiert die Wetterdaten für eine aktive Fotosession auf akute Unwettergefahren.
class SevereWeatherEvaluator {
  const SevereWeatherEvaluator._();

  /// Überprüft die Wettervorhersage ab dem aktuellen Vorhersage-Index
  /// (inklusive eines taktischen 4-Stunden-Vorausschau-Fensters).
  ///
  /// Gibt `null` zurück, wenn in den Einstellungen die Warnung deaktiviert ist
  /// oder keine Unwetterbedingungen vorliegen.
  static SevereWeatherAlert? evaluateActiveSession({
    required List<WeatherFrame> forecast,
    required int activeForecastIndex,
    required AppSettings settings,
  }) {
    if (!settings.warnSevereWeatherDuringAnsitz) {
      return null;
    }
    if (forecast.isEmpty || activeForecastIndex >= forecast.length) {
      return null;
    }

    // Taktisches Vorausschau-Fenster: Aktuelle Stunde + bis zu 3 Folgestunden
    final windowEnd = (activeForecastIndex + 4).clamp(0, forecast.length);
    final candidateFrames = forecast.sublist(activeForecastIndex, windowEnd);

    SevereWeatherAlert? highestAlert;

    for (int offset = 0; offset < candidateFrames.length; offset++) {
      final frame = candidateFrames[offset];
      final hoursUntil = offset;

      // 1. Priorität: Gewitter & Blitzschlag (höchste Lebensgefahr auf offenen Flächen & Hochständen!)
      if (frame.isThunderstorm) {
        final alert = SevereWeatherAlert(
          type: SevereWeatherType.thunderstorm,
          severity: SevereWeatherSeverity.danger,
          headline: hoursUntil == 0
              ? 'Akutes Gewitter am Fotospot!'
              : 'Gewitterfront zieht auf (${frame.time.hour.toString().padLeft(2, '0')}:00 Uhr)',
          subheadline: 'Blitzschlaggefahr & Gewitterböen im Naturgebiet',
          description:
              'Gewitterzellen bringen unvorhersehbare Fallböen und tödliche Blitzschlaggefahr auf offenen Flächen und Hochständen.',
          safetyRecommendation:
              'Offenes Gelände sofort verlassen! Nicht unter freistehenden Bäumen verharren. Metallische Stative sichern und geschützten Unterschlupf aufsuchen.',
          peakGustKmh: frame.windGustsKmh,
          precipitationMm: frame.precipitationMm,
          weatherCode: frame.weatherCode,
          eventTime: frame.time,
          hoursUntilEvent: hoursUntil,
        );
        return alert; // Sofort höchste Priorität zurückgeben
      }

      // 2. Priorität: Schwere Sturmböen / Orkan (ab 75 km/h = Bft 9)
      if (frame.windGustsKmh >= 75.0) {
        final alert = SevereWeatherAlert(
          type: SevereWeatherType.stormGusts,
          severity: SevereWeatherSeverity.danger,
          headline: hoursUntil == 0
              ? 'Schwere Sturmböen (${frame.windGustsKmh.round()} km/h)!'
              : 'Sturmböen bis ${frame.windGustsKmh.round()} km/h erwartet',
          subheadline: 'Lebensgefahr durch Baumbruch & Astwurf',
          description:
              'Windstärken ab Bft 9 führen zu Windwurf, herabfallenden Ästen und Stammbrüchen im Wald.',
          safetyRecommendation:
              'Fotosession unverzüglich abbrechen! Waldgebiet auf kürzestem, sicherem Weg verlassen.',
          peakGustKmh: frame.windGustsKmh,
          precipitationMm: frame.precipitationMm,
          weatherCode: frame.weatherCode,
          eventTime: frame.time,
          hoursUntilEvent: hoursUntil,
        );
        return alert;
      }

      // 3. Sturmböen ab Benutzer-Schwelle (Standard: 60 km/h = Bft 8)
      if (frame.windGustsKmh >= settings.severeWeatherWindGustThresholdKmh) {
        final alert = SevereWeatherAlert(
          type: SevereWeatherType.stormGusts,
          severity: SevereWeatherSeverity.warning,
          headline: hoursUntil == 0
              ? 'Sturmböen (${frame.windGustsKmh.round()} km/h) am Fotospot'
              : 'Sturmböen (${frame.windGustsKmh.round()} km/h) in ${hoursUntil}h',
          subheadline: 'Erhöhte Astbruchgefahr in Altholzbeständen',
          description:
              'Böen ab Bft 8 reißen vermehrt Totholz und schwere Äste von Eichen und Buchen ab.',
          safetyRecommendation:
              'Baumbestand über dir prüfen. Bei Auffrischen des Windes die Fotosession vorzeitig beenden.',
          peakGustKmh: frame.windGustsKmh,
          precipitationMm: frame.precipitationMm,
          weatherCode: frame.weatherCode,
          eventTime: frame.time,
          hoursUntilEvent: hoursUntil,
        );
        if (highestAlert == null || !highestAlert.isDanger) {
          highestAlert = alert;
        }
      }

      // 4. Starkregen / Unwetter-Niederschlag (ab 8.0 mm/h oder Wolkenbruch)
      if (frame.precipitationMm >= 8.0 || (frame.isHeavyRain && frame.precipitationMm >= 6.0)) {
        final alert = SevereWeatherAlert(
          type: SevereWeatherType.heavyRain,
          severity: SevereWeatherSeverity.warning,
          headline: hoursUntil == 0
              ? 'Starkregen (${frame.precipitationMm.toStringAsFixed(1)} mm/h) am Fotospot'
              : 'Starkregen in ${hoursUntil}h erwartet',
          subheadline: 'Sichtverlust & aufweichende Wald- und Pfadwege',
          description:
              'Extremer Niederschlag behindert Wildbeobachtung und kann Waldwege unpassierbar machen.',
          safetyRecommendation:
              'Fotoausrüstung vor Nässe schützen und Rückweg vor Einbruch der Dunkelheit antreten.',
          peakGustKmh: frame.windGustsKmh,
          precipitationMm: frame.precipitationMm,
          weatherCode: frame.weatherCode,
          eventTime: frame.time,
          hoursUntilEvent: hoursUntil,
        );
        highestAlert ??= alert;
      }

      // 5. Rapider Druckabfall vor Front (starker Drucksturz < -3.0 hPa / 6h + Böen >= 45 km/h)
      if (frame.pressureDelta6hHpa <= -3.0 && frame.windGustsKmh >= 45.0) {
        final alert = SevereWeatherAlert(
          type: SevereWeatherType.squallFront,
          severity: SevereWeatherSeverity.warning,
          headline: hoursUntil == 0
              ? 'Rasante Druckfront (${frame.pressureDelta6hHpa.toStringAsFixed(1)} hPa)'
              : 'Unwetterfront naht in ${hoursUntil}h',
          subheadline: 'Plötzlicher Wetterumschwung & Winddreher',
          description:
              'Starker Druckabfall signalisiert eine herannahende markante Kaltfront oder Gewitterlinie.',
          safetyRecommendation:
              'Wetterradar und Horizont beobachten; Fotosession beenden, bevor die Sturmfront eintrifft.',
          peakGustKmh: frame.windGustsKmh,
          precipitationMm: frame.precipitationMm,
          weatherCode: frame.weatherCode,
          eventTime: frame.time,
          hoursUntilEvent: hoursUntil,
        );
        highestAlert ??= alert;
      }
    }

    return highestAlert;
  }

  /// Alias für Rückwärtskompatibilität.
  static SevereWeatherAlert? evaluateActiveAnsitz({
    required List<WeatherFrame> forecast,
    required int activeForecastIndex,
    required AppSettings settings,
  }) => evaluateActiveSession(
    forecast: forecast,
    activeForecastIndex: activeForecastIndex,
    settings: settings,
  );
}
