import '../models/habitat_zone.dart';
import '../models/species_profile.dart';
import '../models/weather_frame.dart';
import 'sun_moon_calculator.dart';
import 'wildlife_phenology_service.dart';

class TacticalFactorBadge {
  final String icon;
  final String title;
  final String description;
  final double scoreDelta;
  final bool isPositive;

  const TacticalFactorBadge({
    required this.icon,
    required this.title,
    required this.description,
    required this.scoreDelta,
    required this.isPositive,
  });

  String get deltaLabel =>
      scoreDelta >= 0 ? '+${scoreDelta.round()}%' : '${scoreDelta.round()}%';
}

class ZoneTacticalAssessment {
  final double tacticalScoreAdjustment;
  final double effectiveSuitabilityScore;
  final int situationalChanceScore;
  final List<TacticalFactorBadge> badges;
  final String? primaryBadgeLabel;
  final WildlifePhenologyPhase phenology;

  const ZoneTacticalAssessment({
    required this.tacticalScoreAdjustment,
    required this.effectiveSuitabilityScore,
    required this.situationalChanceScore,
    required this.badges,
    this.primaryBadgeLabel,
    required this.phenology,
  });
}

/// Wildbiologisch-taktische Berechnungs-Engine für reale Mikroklima- & Feldfaktoren:
/// 1. Waldkanten-Mikroklima (Luv vs. Lee / Windschatten an Waldrändern)
/// 2. Sonnenwärme & Hangexposition (Morgensonne vs. Abendschatten/Sommerhitze)
/// 3. Jahreszeitlicher Phänologie- & Brunft-Kalender
/// 4. Zeit- & Wochentags-abhängige Pfadstörung (Werktag-Frühe vs. Wochenende)
class WildlifeTacticalEngine {
  const WildlifeTacticalEngine._();

  static ZoneTacticalAssessment assessZone({
    required HabitatZone zone,
    required SpeciesProfile species,
    required WeatherFrame weather,
    required SunMoonPosition astro,
    required int baseActivityScore,
  }) {
    final badges = <TacticalFactorBadge>[];
    double adjustment = 0.0;

    final dateTime = weather.time;
    final phenology = WildlifePhenologyService.evaluate(
      speciesId: species.id,
      dateTime: dateTime,
    );

    // =========================================================================
    // 1. Waldkanten-Mikroklima (Luv vs. Lee / Windschatten)
    // =========================================================================
    if (zone.facingBearingDegrees != null && weather.windSpeedKmh >= 8.0) {
      // Windrichtung = woher der Wind kommt (z.B. 0° = Nord)
      // Wind weht in Richtung: (windDirection + 180) % 360
      final windBlowTowards = (weather.windDirectionDegrees + 180.0) % 360.0;
      final angleDiff = _smallestAngleDifference(
        zone.facingBearingDegrees!,
        windBlowTowards,
      );

      if (angleDiff <= 55.0) {
        // Lee (Windschatten)
        final delta = weather.windSpeedKmh >= 20.0 ? 5.0 : 3.5;
        adjustment += delta;
        badges.add(
          TacticalFactorBadge(
            icon: '🌬️',
            title: 'Lee (Windschatten)',
            description:
                'Der Wald schirmt den Wind (${weather.windSpeedKmh.round()} km/h aus ${weather.windCardinalLabel}) ab. Warme, ruhige Schutzzone für vertrautes Austreten.',
            scoreDelta: delta,
            isPositive: true,
          ),
        );
      } else if (angleDiff >= 125.0) {
        // Luv (Winddruck)
        final delta = weather.windSpeedKmh >= 20.0 ? -5.0 : -3.5;
        adjustment += delta;
        badges.add(
          TacticalFactorBadge(
            icon: '💨',
            title: 'Luv (Winddruck)',
            description:
                'Wind (${weather.windSpeedKmh.round()} km/h aus ${weather.windCardinalLabel}) drückt direkt auf diese Kante. Wild ist wegen Zugluft und Verwirbelungen vorsichtig.',
            scoreDelta: delta,
            isPositive: false,
          ),
        );
      }
    }

    // =========================================================================
    // 2. Sonnenwärme & Hangexposition
    // =========================================================================
    final hour = dateTime.hour;
    final isClearOrPartlyCloudy = weather.cloudCoverPercent < 75;

    // A) Morgensonne (Erste Sonnenstunden bis 10:00 Uhr)
    if (hour <= 10 &&
        astro.sunElevationDegrees > 0 &&
        astro.sunElevationDegrees <= 32 &&
        isClearOrPartlyCloudy &&
        zone.facingBearingDegrees != null) {
      final sunDiff = _smallestAngleDifference(
        zone.facingBearingDegrees!,
        astro.sunAzimuthDegrees,
      );
      if (sunDiff <= 65.0) {
        const delta = 4.0;
        adjustment += delta;
        badges.add(
          const TacticalFactorBadge(
            icon: '☀️',
            title: 'Morgensonne',
            description:
                'Erste wärmende Sonnenstrahlen trocknen taunasse Äsung und locken Wild nach der kalten Nacht bevorzugt an diesen Kantenabschnitt.',
            scoreDelta: delta,
            isPositive: true,
          ),
        );
      }
    }

    // B) Abendsonne (Milde Abendsonne ab 16:00 Uhr)
    if (hour >= 16 &&
        astro.sunElevationDegrees > 0 &&
        astro.sunElevationDegrees <= 25 &&
        isClearOrPartlyCloudy &&
        zone.facingBearingDegrees != null) {
      final sunDiff = _smallestAngleDifference(
        zone.facingBearingDegrees!,
        astro.sunAzimuthDegrees,
      );
      if (sunDiff <= 65.0) {
        const delta = 3.0;
        adjustment += delta;
        badges.add(
          const TacticalFactorBadge(
            icon: '🌅',
            title: 'Abendsonne',
            description:
                'Milde Nachmittagswärme begünstigt frühes Austreten vor Einbruch der Dämmerung.',
            scoreDelta: delta,
            isPositive: true,
          ),
        );
      }
    }

    // C) Sommer-Mittagshitze (Hitze meiden vs. kühlender Schatten-Einstand)
    if (weather.temperatureCelsius >= 25.0 && astro.sunElevationDegrees >= 35.0) {
      if (zone.type == HabitatZoneType.optimalEdge) {
        const delta = -4.0;
        adjustment += delta;
        badges.add(
          TacticalFactorBadge(
            icon: '🌡️',
            title: 'Pralle Mittagshitze',
            description:
                'Hitze auf offener Kante (${weather.temperatureCelsius.round()}°C). Wild döst im kühlen Bestand und meidet sonnige Freiflächen.',
            scoreDelta: delta,
            isPositive: false,
          ),
        );
      } else if (zone.type == HabitatZoneType.coreRefuge ||
          zone.type == HabitatZoneType.waterSuhle) {
        const delta = 4.0;
        adjustment += delta;
        final isSuhle = zone.type == HabitatZoneType.waterSuhle;
        badges.add(
          TacticalFactorBadge(
            icon: isSuhle ? '💧' : '🌲',
            title: isSuhle ? 'Suhlen-Hotspot' : 'Kühler Schatten-Einstand',
            description: isSuhle
                ? 'Wasser- und Schlammstellen bieten wichtige Thermoregulation bei Hitze.'
                : 'Dichte Dickungen und Waldinneres bieten kühlen Schatten bei Sommerhitze.',
            scoreDelta: delta,
            isPositive: true,
          ),
        );
      }
    }

    // =========================================================================
    // 3. Jahreszeitlicher Phänologie- & Brunft-Kalender
    // =========================================================================
    if (phenology.boostEdgesAndMeadows &&
        (zone.type == HabitatZoneType.optimalEdge ||
            zone.title.contains('Äsung') ||
            zone.title.contains('Bucht'))) {
      final delta = species.id == 'red_deer' ? 6.0 : 4.5;
      adjustment += delta;
      badges.add(
        TacticalFactorBadge(
          icon: phenology.emoji,
          title: phenology.phaseName,
          description: phenology.description,
          scoreDelta: delta,
          isPositive: true,
        ),
      );
    } else if (phenology.activityBonus < -5.0 &&
        zone.type == HabitatZoneType.optimalEdge) {
      // Winterruhe: Wild verharrt kraftsparend im Einstand
      const delta = -4.0;
      adjustment += delta;
      badges.add(
        TacticalFactorBadge(
          icon: phenology.emoji,
          title: phenology.phaseName,
          description: phenology.description,
          scoreDelta: delta,
          isPositive: false,
        ),
      );
    }

    // =========================================================================
    // 4. Zeit- & Wochentags-abhängige Pfadstörung
    // =========================================================================
    final isWeekend =
        dateTime.weekday == DateTime.saturday ||
        dateTime.weekday == DateTime.sunday;
    final trailDist = zone.distanceToNearestTrailMeters;

    if (!isWeekend && hour >= 4 && hour <= 7) {
      // Werktag früher Morgen (04:00 - 07:59): Wege komplett leer
      if (trailDist < 140.0) {
        const delta = 3.5;
        adjustment += delta;
        badges.add(
          const TacticalFactorBadge(
            icon: '🔕',
            title: 'Frühe Wochentagsruhe',
            description:
                'Wege menschenleer am Werktagmorgen. Wild äst vertraut auch an sonst begangenen Randstreifen.',
            scoreDelta: delta,
            isPositive: true,
          ),
        );
      }
    } else if (isWeekend && hour >= 9 && hour <= 17) {
      // Wochenende tagsüber: Höchster Spaziergänger- & Hundedruck
      if (trailDist < 65.0) {
        const delta = -7.0;
        adjustment += delta;
        badges.add(
          TacticalFactorBadge(
            icon: '🚶',
            title: 'Wochenend-Freizeitdruck',
            description:
                'Starke Pfadnutzung durch Wanderer & Hunde (${trailDist.round()}m Abstand). Wild flieht in unzugängliche Dickungen.',
            scoreDelta: delta,
            isPositive: false,
          ),
        );
      } else if (trailDist < 130.0) {
        const delta = -4.0;
        adjustment += delta;
        badges.add(
          TacticalFactorBadge(
            icon: '🚶',
            title: 'Wochenend-Unruhe an Wegen',
            description:
                'Regelmäßige Wegnutzung am Wochenende drückt das Wild tiefer in den Bestand.',
            scoreDelta: delta,
            isPositive: false,
          ),
        );
      } else if (zone.type == HabitatZoneType.coreRefuge && trailDist >= 150.0) {
        const delta = 3.5;
        adjustment += delta;
        badges.add(
          const TacticalFactorBadge(
            icon: '🛡️',
            title: 'Ruhiges Rückzugsrefugium',
            description:
                'Vom Wochenendtrubel isolierte Dickung – Wild weicht hierhin aus.',
            scoreDelta: delta,
            isPositive: true,
          ),
        );
      }
    }

    // Begrenzung der taktischen Anpassung auf ±12 Punkte
    final clampedAdjustment = adjustment.clamp(-12.0, 12.0);
    final effectiveSuitability =
        (zone.suitabilityScore + clampedAdjustment).clamp(10.0, 99.0);

    // Gesamter situativer Chance-Score
    final situationalChance =
        ((baseActivityScore + effectiveSuitability) / 2.0).round().clamp(5, 99);

    String? primaryLabel;
    if (badges.isNotEmpty) {
      final first = badges.first;
      primaryLabel = '${first.icon} ${first.title} (${first.deltaLabel})';
    }

    return ZoneTacticalAssessment(
      tacticalScoreAdjustment: clampedAdjustment,
      effectiveSuitabilityScore: effectiveSuitability,
      situationalChanceScore: situationalChance,
      badges: badges,
      primaryBadgeLabel: primaryLabel,
      phenology: phenology,
    );
  }

  static double _smallestAngleDifference(double a, double b) {
    final diff = (a - b).abs() % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }
}
