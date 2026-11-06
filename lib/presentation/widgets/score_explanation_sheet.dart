import 'package:flutter/material.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../domain/models/habitat_zone.dart';
import '../../domain/models/species_profile.dart';
import '../../domain/models/weather_frame.dart';
import '../../domain/services/activity_score_calculator.dart';
import '../../domain/services/sun_moon_calculator.dart';
import '../../domain/services/wildlife_tactical_engine.dart';
import 'species_photo_avatar.dart';

class ScoreExplanationSheet {
  static Color colorForActivityScore(int score) {
    if (score >= 78) return WildlifeScoutTheme.emeraldBio;
    if (score >= 55) return WildlifeScoutTheme.amberGold;
    return WildlifeScoutTheme.textMuted;
  }

  static Color colorForChanceScore(int score) {
    if (score >= 70) return WildlifeScoutTheme.emeraldBio;
    if (score >= 45) return WildlifeScoutTheme.amberGold;
    return WildlifeScoutTheme.textMuted;
  }

  static String ratingForChanceScore(int score) {
    if (score >= 80) return 'Exzellent';
    if (score >= 68) return 'Sehr gut';
    if (score >= 50) return 'Gut';
    if (score >= 35) return 'Mäßig';
    return 'Gering';
  }

  static void show({
    required BuildContext context,
    required HabitatZone zone,
    required FieldAssessment zoneAssessment,
    required int chanceScore,
    required ZoneTacticalAssessment tacticalAssessment,
    required WeatherFrame currentWeather,
    required double latitude,
    required double longitude,
    required Color accentColor,
    SpeciesProfile? species,
    void Function(SpeciesProfile species)? onOpenSpeciesInspector,
  }) {
    final activityScore = zoneAssessment.activityScorePercent;
    final activityColor = colorForActivityScore(activityScore);
    final effectiveSuitability = tacticalAssessment.effectiveSuitabilityScore;
    final finalChanceScore = tacticalAssessment.situationalChanceScore;
    final chanceColor = colorForChanceScore(finalChanceScore);
    final chanceRating = ratingForChanceScore(finalChanceScore);

    final astro = SunMoonCalculator.calculate(
      dateTime: currentWeather.time,
      latitude: latitude,
      longitude: longitude,
    );

    String? soilDetail;
    String? slopeDetail;
    for (final part in zone.subtitle.split(' • ')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('Boden:') || trimmed.contains('Boden')) {
        soilDetail = trimmed.replaceFirst('Boden:', '').trim();
      } else if (trimmed.startsWith('Hang') || trimmed.contains('Hang')) {
        slopeDetail = trimmed;
      }
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header: Tier-Foto + Titel + Chance Badge
                Row(
                  children: [
                    if (species != null)
                      GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          onOpenSpeciesInspector?.call(species);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.6),
                              width: 1.3,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SpeciesPhotoAvatar(
                              species: species,
                              width: 48,
                              height: 48,
                              borderRadius: 12,
                              borderWidth: 0,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: chanceColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: chanceColor.withValues(alpha: 0.4)),
                        ),
                        child: Icon(
                          Icons.track_changes_rounded,
                          color: chanceColor,
                          size: 20,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Sichtungs-Chance: $finalChanceScore%',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  color: chanceColor,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: chanceColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: chanceColor.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  chanceRating,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: chanceColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${species?.name ?? 'Wildart'} • ${zone.title}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Button: Voller Steckbrief
                if (species != null) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onOpenSpeciesInspector?.call(species);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.45),
                          width: 1.1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_stories_rounded,
                            size: 18,
                            color: accentColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Voller Steckbrief: ${species.name}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: accentColor,
                                  ),
                                ),
                                const SizedBox(height: 1.5),
                                const Text(
                                  'Biologie, Sinne, Fluchtdistanz, Äsung & Foto-Tipps',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: WildlifeScoutTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Öffnen',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: accentColor,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 11,
                                  color: accentColor,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Erklärung: Was bedeutet die Chance?
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: chanceColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: chanceColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.help_outline_rounded,
                            size: 16,
                            color: chanceColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Was bedeutet $finalChanceScore% Chance?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: chanceColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Keine pauschale Wahrscheinlichkeit, sondern deine konkrete Sichtungs-Chance zu dieser Stunde an genau diesem Ort. Sie verbindet die beiden Kernfragen „Wann?“ und „Wo?“ zu einem Gesamtwert:',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Faktor 1: Live-Wildaktivität (Zeit & Wetter)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: activityColor.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: activityColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.bolt_rounded,
                              color: activityColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  '1. Live-Wildaktivität: $activityScore%',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: activityColor,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Wann?',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: activityColor.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Konkrete Einflussfaktoren zu dieser Stunde (${currentWeather.time.hour.toString().padLeft(2, '0')}:00 Uhr):',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Aufzählung aller Aktivitäts-Faktoren:
                      _buildFactorRow(
                        icon: Icons.wb_twilight_rounded,
                        iconColor: activityColor,
                        label: 'Dämmerung & Tageszeit',
                        value:
                            '${astro.lightPhaseLabel}${astro.isGoldenHour ? ' (Goldene Stunde)' : astro.isBlueHour ? ' (Blaue Stunde)' : ''}',
                        detail: species != null &&
                                species.behavior.primaryActivityPeriods
                                    .contains(astro.currentPeriod)
                            ? 'Hauptaktivitätsphase für ${species.name} (hohe Austrittschance)'
                            : 'Nebenzeiten (typische Einstands- und Ruhephase)',
                      ),
                      _buildFactorRow(
                        icon: Icons.speed_rounded,
                        iconColor: activityColor,
                        label: 'Luftdruck & Barometer',
                        value:
                            '${currentWeather.surfacePressureHpa.round()} hPa (${currentWeather.pressureDelta6hHpa >= 0 ? '+' : ''}${currentWeather.pressureDelta6hHpa.toStringAsFixed(1)} hPa in 6h)',
                        detail: zoneAssessment.barometerInsight.isNotEmpty
                            ? zoneAssessment.barometerInsight
                            : 'Stabiler Luftdrucktrend',
                      ),
                      _buildFactorRow(
                        icon: Icons.air_rounded,
                        iconColor: activityColor,
                        label: 'Wind & Wind-Komfort',
                        value:
                            '${currentWeather.windSpeedKmh.round()} km/h aus ${currentWeather.windCardinalLabel} (Böen: ${currentWeather.windGustsKmh.round()} km/h)',
                        detail: zoneAssessment.windAdvice,
                      ),
                      _buildFactorRow(
                        icon: Icons.thermostat_rounded,
                        iconColor: activityColor,
                        label: 'Temperatur',
                        value:
                            '${currentWeather.temperatureCelsius.toStringAsFixed(1)} °C',
                        detail: currentWeather.temperatureCelsius >= 8 &&
                                currentWeather.temperatureCelsius <= 22
                            ? 'Angenehme Wohlfühltemperatur für das Wild'
                            : currentWeather.temperatureCelsius < 8
                                ? 'Kühle Witterung regt die Nahrungsaufnahme an'
                                : 'Warme Witterung, Wild meidet pralle Sonne',
                      ),
                      _buildFactorRow(
                        icon: Icons.nightlight_round,
                        iconColor: activityColor,
                        label: 'Mondphase & Nachtlicht',
                        value:
                            '${astro.moonPhaseName} (${(astro.moonIlluminationFraction * 100).round()}% Licht)',
                        detail: astro.moonIlluminationFraction < 0.25
                            ? 'Dunkle Neumondnacht: Wild zieht morgens früher und hungriger auf Freiflächen'
                            : 'Helles Mondlicht begünstigt Nachtäsungszyklen',
                      ),
                      _buildFactorRow(
                        icon: Icons.cloud_outlined,
                        iconColor: activityColor,
                        label: 'Bewölkung & Niederschlag',
                        value: '${currentWeather.cloudCoverPercent}% Bewölkung',
                        detail: currentWeather.isHeavyRain
                            ? 'Starkregen hemmt Bewegung (Wild meidet offenes Gelände)'
                            : currentWeather.precipitationMm > 0
                                ? 'Leichter Niederschlag (${currentWeather.precipitationMm.toStringAsFixed(1)} mm) dämpft Geräusche'
                                : 'Trockene Witterung begünstigt vertrauten Austritt',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Faktor 2: Biotop-Eignung (Ort & Gelände)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              zone.type == HabitatZoneType.waterSuhle
                                  ? Icons.water_drop_rounded
                                  : Icons.park_rounded,
                              color: accentColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  '2. Biotop-Güte: ${zone.suitabilityScore.round()}%',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: accentColor,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Wo?',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gelände- & Habitatkriterien für diesen Spot (${zone.title}):',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),

                      _buildFactorRow(
                        icon: Icons.shield_outlined,
                        iconColor: accentColor,
                        label: 'Ruhe & Anthropogene Störung',
                        value:
                            '${zone.distanceToNearestTrailMeters.round()} m zum nächsten Weg/Pfad',
                        detail: zone.distanceToNearestTrailMeters >= 200
                            ? 'Hervorragender Schutz- & Sicherheitsbereich: Hoher Pufferabstand zu Freizeitwegen'
                            : zone.distanceToNearestTrailMeters >= 80
                                ? 'Moderater Abstand: Wild verhält sich vorsichtig sichernd'
                                : 'Geringer Abstand: Fluchtrisiko bei Fußgängern und Hunden',
                      ),
                      _buildFactorRow(
                        icon: Icons.water_drop_outlined,
                        iconColor: accentColor,
                        label: 'Wasserstelle & Suhlen',
                        value: zone.distanceToWaterMeters < 15
                            ? 'Direkt am Wasser (<15 m)'
                            : '${zone.distanceToWaterMeters.round()} m zum Gewässer',
                        detail: zone.distanceToWaterMeters <= 50
                            ? 'Unmittelbare Tränke- & Suhlennähe (starker Anziehungspunkt)'
                            : zone.distanceToWaterMeters <= 150
                                ? 'Gute Erreichbarkeit im Nahbereich'
                                : 'Größere Distanz, primär reiner Äsungsbereich',
                      ),
                      _buildFactorRow(
                        icon: Icons.forest_outlined,
                        iconColor: accentColor,
                        label: 'Deckung & Waldgrenze',
                        value:
                            '${zone.distanceToForestMeters.round()} m zum Saum (${zone.type.label})',
                        detail: zone.distanceToForestMeters <= 15
                            ? 'Idealer Waldsaum: Schnelle Deckung im dichten Bestand'
                            : 'Offeneres Feld mit längeren Fluchtwegen zum Bestand',
                      ),
                      if (slopeDetail != null)
                        _buildFactorRow(
                          icon: Icons.terrain_rounded,
                          iconColor: accentColor,
                          label: 'Topographie & Hang',
                          value: slopeDetail,
                          detail:
                              'Hangprofil und Neigung bestimmen Witterungsschutz und Sonneneinstrahlung',
                        ),
                      if (soilDetail != null)
                        _buildFactorRow(
                          icon: Icons.layers_rounded,
                          iconColor: accentColor,
                          label: 'Boden-Substrat & Vegetation',
                          value: soilDetail,
                          detail:
                              'Nährstoffreiches Substrat begünstigt schmackhafte Äsungspflanzen',
                          isLast: !zone.subtitle.contains('Hochsitz'),
                        ),
                      if (zone.subtitle.contains('Hochsitz'))
                        _buildFactorRow(
                          icon: Icons.gps_fixed_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          label: 'Praxis-Nachweis: Hochsitz / Jägerstand',
                          value: '+3.5 Punkte Bio-Bonus',
                          detail:
                              'Hochsitz in Beobachtungsdistanz (OSM amenity=hunting_stand) belegt einen feldbiologisch bewährten Wildwechsel.',
                          isLast: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Faktor 3: Mikroklima & Taktik (Luv/Lee, Sonne, Phänologie, Wege-Ruhe)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (tacticalAssessment.tacticalScoreAdjustment >= 0
                              ? WildlifeScoutTheme.emeraldBio
                              : WildlifeScoutTheme.amberGold)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: (tacticalAssessment.tacticalScoreAdjustment >= 0
                                      ? WildlifeScoutTheme.emeraldBio
                                      : WildlifeScoutTheme.amberGold)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              tacticalAssessment.tacticalScoreAdjustment >= 0
                                  ? Icons.air_rounded
                                  : Icons.warning_amber_rounded,
                              color: tacticalAssessment.tacticalScoreAdjustment >= 0
                                  ? WildlifeScoutTheme.emeraldBio
                                  : WildlifeScoutTheme.amberGold,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  '3. Mikroklima & Taktik: ${tacticalAssessment.tacticalScoreAdjustment >= 0 ? '+' : ''}${tacticalAssessment.tacticalScoreAdjustment.round()}%',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: tacticalAssessment.tacticalScoreAdjustment >= 0
                                        ? WildlifeScoutTheme.emeraldBio
                                        : WildlifeScoutTheme.amberGold,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Vor Ort',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: (tacticalAssessment.tacticalScoreAdjustment >=
                                                0
                                            ? WildlifeScoutTheme.emeraldBio
                                            : WildlifeScoutTheme.amberGold)
                                        .withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Konkrete Vor-Ort-Einflüsse an dieser Kante:',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (tacticalAssessment.badges.isNotEmpty)
                        ...tacticalAssessment.badges.map(
                          (b) => Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4.5),
                                  decoration: BoxDecoration(
                                    color: (b.isPositive
                                            ? WildlifeScoutTheme.emeraldBio
                                            : WildlifeScoutTheme.amberGold)
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    b.icon,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            b.title,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            b.deltaLabel,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                              color: b.isPositive
                                                  ? WildlifeScoutTheme
                                                      .emeraldBio
                                                  : WildlifeScoutTheme
                                                      .amberGold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 1.5),
                                      Text(
                                        b.description,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          height: 1.25,
                                          color: WildlifeScoutTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Neutrale Bedingungen: Keine extremen Windeinflüsse oder akuten Störungen an diesem Kantenabschnitt.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                        ),
                      _buildFactorRow(
                        icon: Icons.calendar_month_rounded,
                        iconColor: WildlifeScoutTheme.amberGold,
                        label: 'Jahreszeitliche Phänologie',
                        value:
                            '${tacticalAssessment.phenology.emoji} ${tacticalAssessment.phenology.phaseName}',
                        detail: tacticalAssessment.phenology.description,
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Erfolgs-Synthese
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: chanceColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: chanceColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.insights_rounded,
                        size: 15,
                        color: chanceColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Erfolgs-Synthese: Live-Wildaktivität ($activityScore%) & Vor-Ort-Biotop (${effectiveSuitability.round()}%) ergeben $finalChanceScore% Sichtungs-Chance.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: chanceColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Interaktiver Tipp zur Zeitleiste
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 15,
                        color: WildlifeScoutTheme.amberGold,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tipp: Verstelle unten den Zeitstrahl auf 06:00 oder 18:00 Uhr. Weil Wild in der Dämmerung aktiver ist, klettert auch die Chance an diesem Spot sofort nach oben!',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: WildlifeScoutTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (species != null) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onOpenSpeciesInspector?.call(species);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor.withValues(alpha: 0.18),
                        foregroundColor: accentColor,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: accentColor.withValues(alpha: 0.5),
                            width: 1.1,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.auto_stories_rounded, size: 18),
                      label: Text(
                        'Voller Steckbrief: ${species.name}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildFactorRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String detail,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 7.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4.5),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 12.5, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1.5),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11,
                    color: WildlifeScoutTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
