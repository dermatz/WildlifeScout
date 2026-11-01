import 'package:latlong2/latlong.dart';
import '../models/habitat_zone.dart';
import '../models/species_profile.dart';
import '../models/weather_frame.dart';
import 'sun_moon_calculator.dart';

class TacticalAssessment {
  final int activityScorePercent; // 0 bis 100
  final String ratingLabel; // z. B. "Exzellentes Austrittsfenster"
  final String barometerInsight;
  final String windTacticalAdvice;
  final String lightQualityAdvice;
  final bool hasScentCollision;
  final String? scentCollisionWarning;

  const TacticalAssessment({
    required this.activityScorePercent,
    required this.ratingLabel,
    required this.barometerInsight,
    required this.windTacticalAdvice,
    required this.lightQualityAdvice,
    required this.hasScentCollision,
    this.scentCollisionWarning,
  });
}

/// Berechnet den biologischen Aktivitäts-Index (0–100 %) und prüft live, ob der
/// eigene Witterungskegel (Geruch) in eine aktive Habitat-Zone der gewählten
/// Wildart weht.
class ActivityScoreCalculator {
  const ActivityScoreCalculator._();

  static const Distance _geoDistance = Distance();

  static TacticalAssessment evaluate({
    required SpeciesProfile species,
    required WeatherFrame weather,
    required SunMoonPosition astro,
    required LatLng hidePosition,
    required List<HabitatZone> habitatZones,
  }) {
    // 1. Tageszeit-Gewichtung (45 % Gewicht)
    double timeFactor = 0.25;
    if (species.behavior.primaryActivityPeriods.contains(astro.currentPeriod)) {
      timeFactor = astro.isGoldenHour || astro.isBlueHour ? 1.0 : 0.85;
    } else if (astro.isGoldenHour) {
      timeFactor = 0.75;
    }

    // 2. Barometer-Trend (30 % Gewicht)
    // Fallender Luftdruck (< -1.5 hPa in 6h) triggert Äsungsaktivität vor Wetterumschwung
    double baroFactor = 0.55;
    String baroInsight;
    final delta = weather.pressureDelta6hHpa;
    if (delta <= -2.5) {
      baroFactor = 0.95 * species.behavior.barometerDropSensitivity + 0.15;
      baroInsight =
          'Druckabfall (${delta.toStringAsFixed(1)} hPa) • Starker Fress-Trigger vor Front!';
    } else if (delta <= -0.8) {
      baroFactor = 0.80;
      baroInsight =
          'Leicht fallender Druck (${delta.toStringAsFixed(1)} hPa) • Gute Bewegung';
    } else if (delta >= 2.0) {
      baroFactor = 0.72;
      baroInsight =
          'Steigendes Hoch (+${delta.toStringAsFixed(1)} hPa) • Ruhiges Austreten';
    } else {
      baroFactor = 0.62;
      baroInsight =
          'Stabiler Luftdruck (${weather.surfacePressureHpa.round()} hPa)';
    }

    // 3. Wind-Komfortfaktor (15 % Gewicht)
    final maxWind = species.behavior.maxToleratedWindSpeedKmh;
    double windFactor;
    if (weather.windSpeedKmh <= 4.0) {
      // Fast windstill -> Umlaufender Wind / Thermik-Risiko im Wald
      windFactor = 0.75;
    } else if (weather.windSpeedKmh <= maxWind * 0.45) {
      // Konstante leichte Brise -> Perfekte, stabile Witterung!
      windFactor = 1.0;
    } else if (weather.windSpeedKmh <= maxWind) {
      windFactor = 0.55;
    } else {
      // Sturm -> Wild bleibt in der Dickung (Ästebruch / Geräuschkulisse)
      windFactor = 0.15;
    }

    // 4. Solunar / Mond-Faktor (10 % Gewicht)
    double solunarFactor = 0.6;
    if (astro.currentPeriod == ActivityPeriod.night) {
      solunarFactor = 0.35 + (astro.moonIlluminationFraction * 0.65);
    } else if (astro.moonIlluminationFraction < 0.25) {
      // Nach dunklen Neumondnächten äst Schalenwild morgens intensiver im Hellen!
      solunarFactor = 0.95;
    }

    final rawScore =
        (timeFactor * 45.0) +
        (baroFactor.clamp(0.0, 1.0) * 30.0) +
        (windFactor * 15.0) +
        (solunarFactor * 10.0);

    final finalScore = rawScore.round().clamp(8, 99);

    final String ratingLabel;
    if (finalScore >= 80) {
      ratingLabel = 'Exzellentes Fotofenster';
    } else if (finalScore >= 62) {
      ratingLabel = 'Gute Austrittschance';
    } else if (finalScore >= 42) {
      ratingLabel = 'Mäßige Aktivität (Einstand)';
    } else {
      ratingLabel = 'Geringe Aktivität (Ruhephase)';
    }

    // 5. Witterungs-Kollisionsprüfung (Weht unser Geruch in eine Top-Habitat-Zone?)
    bool hasCollision = false;
    String? collisionMessage;

    if (species.behavior.scentSensitivityMeters > 0) {
      final scentDir = weather.scentBlowDirectionDegrees;
      final halfCone = species.behavior.scentConeAngleDegrees / 2.0;
      final maxRange = species.behavior.scentSensitivityMeters;

      for (final zone in habitatZones) {
        if (zone.isDisturbance) continue;
        final distMeters = _geoDistance.as(
          LengthUnit.Meter,
          hidePosition,
          zone.center,
        );
        if (distMeters <= maxRange * 1.15 && distMeters >= 15) {
          final bearing = _geoDistance.bearing(hidePosition, zone.center);
          final normalizedBearing = (bearing + 360.0) % 360.0;
          final angleDiff = _smallestAngleDifference(
            scentDir,
            normalizedBearing,
          );

          if (angleDiff <= halfCone + 12.0) {
            hasCollision = true;
            collisionMessage =
                'Witterungs-Alarm: Dein Windkegel zieht direkt in „${zone.title}“ (${distMeters.round()}m)! Ansitz seitlich zum Wind verlegen.';
            break;
          }
        }
      }
    }

    final String windAdvice;
    if (species.behavior.scentSensitivityMeters <= 0) {
      windAdvice =
          'Wind aus ${weather.windCardinalLabel} (${weather.windSpeedKmh.round()} km/h) • Vögel landen gegen den Wind!';
    } else if (hasCollision) {
      windAdvice = collisionMessage!;
    } else if (weather.windSpeedKmh < 4.0) {
      windAdvice =
          'Schwachwind (${weather.windSpeedKmh.round()} km/h) • Achtung auf kreisende Abendthermik am Waldrand!';
    } else {
      windAdvice =
          'Sicherer Wind aus ${weather.windCardinalLabel} (${weather.windSpeedKmh.round()} km/h) • Witterung zieht frei ab.';
    }

    final String lightAdvice;
    if (astro.isGoldenHour) {
      lightAdvice =
          'Goldenes Streiflicht aus ${_cardinalFromAzimuth(astro.sunAzimuthDegrees)} (${astro.sunElevationDegrees.toStringAsFixed(1)}° Höhe)';
    } else if (astro.isBlueHour) {
      lightAdvice =
          'Blaue Stunde / Restlicht • Hohe ISO & lichtstarkes Tele empfohlen';
    } else if (astro.sunElevationDegrees > 25) {
      lightAdvice =
          'Hartes Sonnenlicht (${astro.sunElevationDegrees.round()}°) • Waldschatten & Suhlen bevorzugen';
    } else if (astro.sunElevationDegrees < -6.5) {
      lightAdvice =
          'Dunkelheit • Mondbeleuchtung ${(astro.moonIlluminationFraction * 100).round()}%';
    } else {
      lightAdvice =
          'Weiches Fotolicht aus ${_cardinalFromAzimuth(astro.sunAzimuthDegrees)}';
    }

    return TacticalAssessment(
      activityScorePercent: finalScore,
      ratingLabel: ratingLabel,
      barometerInsight: baroInsight,
      windTacticalAdvice: windAdvice,
      lightQualityAdvice: lightAdvice,
      hasScentCollision: hasCollision,
      scentCollisionWarning: collisionMessage,
    );
  }

  static double _smallestAngleDifference(double a, double b) {
    final diff = (a - b).abs() % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  static String _cardinalFromAzimuth(double deg) {
    const dirs = ['Nord', 'Nordost', 'Ost', 'Südost', 'Süd', 'Südwest', 'West', 'Nordwest'];
    final idx = ((deg + 22.5) % 360 / 45).floor();
    return dirs[idx % 8];
  }
}
