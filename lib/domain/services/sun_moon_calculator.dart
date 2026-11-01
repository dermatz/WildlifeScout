import 'dart:math' as math;
import '../models/species_profile.dart';

class SunMoonPosition {
  final double sunAzimuthDegrees; // 0 = Nord, 90 = Ost, 180 = Süd, 270 = West
  final double sunElevationDegrees; // < 0 = unter Horizont
  final double moonIlluminationFraction; // 0.0 (Neumond) bis 1.0 (Vollmond)
  final String moonPhaseName; // z.B. Neumond, Zunehmende Sichel, Erstes Viertel, etc.
  final ActivityPeriod currentPeriod;
  final String lightPhaseLabel;
  final bool isGoldenHour;
  final bool isBlueHour;

  const SunMoonPosition({
    required this.sunAzimuthDegrees,
    required this.sunElevationDegrees,
    required this.moonIlluminationFraction,
    required this.moonPhaseName,
    required this.currentPeriod,
    required this.lightPhaseLabel,
    required this.isGoldenHour,
    required this.isBlueHour,
  });
}

/// Reiner, 100% offlinefähiger Astronomie-Rechner für Sonnenstand, Dämmerung
/// (Blaue Stunde / Golden Hour) und Mondphase basierend auf NOAA/Meeus-Gleichungen.
class SunMoonCalculator {
  const SunMoonCalculator._();

  static const double _rad = math.pi / 180.0;
  static const double _deg = 180.0 / math.pi;

  static SunMoonPosition calculate({
    required DateTime dateTime,
    required double latitude,
    required double longitude,
  }) {
    final utc = dateTime.toUtc();
    // Julian Date
    final jd = utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;
    final d = jd - 2451545.0;

    // Mittlere Anomalie & Ekliptikale Länge der Sonne
    final m = (357.5291 + 0.98560028 * d) % 360.0;
    final mRad = m * _rad;
    final c =
        1.9148 * math.sin(mRad) +
        0.0200 * math.sin(2 * mRad) +
        0.0003 * math.sin(3 * mRad);
    final lambda = (m + c + 180.0 + 102.9372) % 360.0;
    final lambdaRad = lambda * _rad;

    // Schiefe der Ekliptik
    final obliq = 23.4397 * _rad;

    // Deklination & Rektaszension
    final sinDec = math.sin(lambdaRad) * math.sin(obliq);
    final dec = math.asin(sinDec);
    final ra = math.atan2(
      math.sin(lambdaRad) * math.cos(obliq),
      math.cos(lambdaRad),
    );

    // Sternzeit & Stundenwinkel
    final theta = (280.1600 + 360.9856235 * d + longitude) * _rad;
    final h = theta - ra;

    final latRad = latitude * _rad;

    // Sonnenhöhe (Elevation)
    final sinAlt =
        math.sin(latRad) * math.sin(dec) +
        math.cos(latRad) * math.cos(dec) * math.cos(h);
    final elevation = math.asin(sinAlt.clamp(-1.0, 1.0)) * _deg;

    // Sonnen-Azimut (0° = Nord, 90° = Ost, 180° = Süd, 270° = West)
    final y = math.sin(h);
    final x = math.cos(h) * math.sin(latRad) - math.tan(dec) * math.cos(latRad);
    final azimuth = (math.atan2(y, x) * _deg + 180.0) % 360.0;

    // Mondphase (Synodischer Monat = 29.530588 Tage, Referenz-Neumond JD 2451550.1)
    final lunarAge = (jd - 2451550.1) % 29.53058867;
    final normalizedAge =
        (lunarAge < 0 ? lunarAge + 29.53058867 : lunarAge) / 29.53058867;
    final moonIllum = 0.5 * (1.0 - math.cos(2.0 * math.pi * normalizedAge));

    // Exakte astronomische Mondphase
    final String phaseName;
    if (normalizedAge < 0.03 || normalizedAge >= 0.97) {
      phaseName = 'Neumond';
    } else if (normalizedAge < 0.22) {
      phaseName = 'Zunehmende Sichel';
    } else if (normalizedAge < 0.28) {
      phaseName = 'Erstes Viertel';
    } else if (normalizedAge < 0.47) {
      phaseName = 'Zunehmender Mond';
    } else if (normalizedAge < 0.53) {
      phaseName = 'Vollmond';
    } else if (normalizedAge < 0.72) {
      phaseName = 'Abnehmender Mond';
    } else if (normalizedAge < 0.78) {
      phaseName = 'Letztes Viertel';
    } else {
      phaseName = 'Abnehmende Sichel';
    }

    // Lichtphasen-Klassifikation für Naturfotografen
    final isMorning = dateTime.hour < 12;
    final bool isGolden = elevation >= -1.0 && elevation <= 6.5;
    final bool isBlue = elevation >= -6.5 && elevation < -1.0;

    final ActivityPeriod period;
    final String phaseLabel;

    if (elevation >= -6.5 && elevation <= 8.0) {
      period = isMorning ? ActivityPeriod.dawn : ActivityPeriod.dusk;
      if (isGolden) {
        phaseLabel = isMorning
            ? 'Goldene Stunde (Morgenlicht)'
            : 'Goldene Stunde (Abendlicht)';
      } else {
        phaseLabel = isMorning
            ? 'Morgendämmerung / Blaue Stunde'
            : 'Abenddämmerung / Blaue Stunde';
      }
    } else if (elevation > 8.0) {
      period = ActivityPeriod.day;
      phaseLabel = 'Tageslicht (${elevation.toStringAsFixed(0)}° Sonnenhöhe)';
    } else {
      period = ActivityPeriod.night;
      final moonPct = (moonIllum * 100).round();
      phaseLabel = 'Nacht • Mondlicht $moonPct%';
    }

    return SunMoonPosition(
      sunAzimuthDegrees: azimuth,
      sunElevationDegrees: elevation,
      moonIlluminationFraction: moonIllum,
      moonPhaseName: phaseName,
      currentPeriod: period,
      lightPhaseLabel: phaseLabel,
      isGoldenHour: isGolden,
      isBlueHour: isBlue,
    );
  }
}
