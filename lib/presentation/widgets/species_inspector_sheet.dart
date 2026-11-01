import 'package:flutter/material.dart';
import '../../core/theme/wildscout_theme.dart';
import '../../data/services/photo_gear_service.dart';
import '../../domain/models/photo_gear_profile.dart';
import '../../domain/models/soil_substrate_profile.dart';
import '../../domain/models/species_profile.dart';
import '../../domain/services/wildlife_photo_calculator.dart';
import 'photo_gear_sheet.dart';
import 'species_photo_avatar.dart';

class SpeciesInspectorSheet extends StatelessWidget {
  final SpeciesProfile species;
  final double obfuscatedLat;
  final double obfuscatedLon;
  final SoilSubstrateProfile? soilProfile;

  const SpeciesInspectorSheet({
    super.key,
    required this.species,
    required this.obfuscatedLat,
    required this.obfuscatedLon,
    this.soilProfile,
  });

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.88;
    final activePeriodsText = species.behavior.primaryActivityPeriods
        .map((p) => p.label)
        .join(' • ');

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: WildScoutTheme.bgObsidian.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildScoutTheme.borderSubtle, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 1. Großes lizenzfreies Unsplash-Tierfoto (Hero-Card)
            Stack(
              children: [
                SpeciesPhotoAvatar(
                  species: species,
                  width: double.infinity,
                  height: 195,
                  borderRadius: 20,
                  borderWidth: 1.5,
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.25),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.88),
                        ],
                        stops: const [0.0, 0.38, 1.0],
                      ),
                    ),
                  ),
                ),
                // Lizenzfrei-Badge oben rechts
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: WildScoutTheme.emeraldBio.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_outlined,
                          size: 13,
                          color: WildScoutTheme.emeraldBio,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Unsplash • Lizenzfrei (${species.imageAuthor})',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Kategorie-Badge oben links
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: species.accentColor.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Text(
                      species.category.label,
                      style: TextStyle(
                        color: species.accentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                // Artname & Wissenschaftlicher Name unten im Hero-Bild
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        species.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${species.scientificName} • ${species.openData.taxonomy}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              species.shortDescription,
              style: const TextStyle(
                fontSize: 13.5,
                color: WildScoutTheme.textPrimary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),

            // 2. Taktische Sensor-Metriken
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: 'Witterungs-Radius',
                    value: species.behavior.scentSensitivityMeters > 0
                        ? '${species.behavior.scentSensitivityMeters.round()} m'
                        : 'Kein Geruchssinn',
                    icon: Icons.air,
                    color: WildScoutTheme.crimsonScent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: 'Fluchtdistanz',
                    value: '${species.behavior.flightDistanceMeters.round()} m',
                    icon: Icons.radar,
                    color: WildScoutTheme.amberGold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: 'Max. Windstärke',
                    value:
                        '${species.behavior.maxToleratedWindSpeedKmh.round()} km/h',
                    icon: Icons.wind_power,
                    color: WildScoutTheme.emeraldBio,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3. Offene Daten zu dem Tier (Wildbiologie & Ökologie Steckbrief)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: WildScoutTheme.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: WildScoutTheme.cyanWater.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.biotech_outlined,
                        size: 18,
                        color: WildScoutTheme.cyanWater,
                      ),
                      SizedBox(width: 7),
                      Text(
                        'Offene Wildbiologie- & Ökologie-Daten',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: WildScoutTheme.cyanWater,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _FactItem(
                    icon: Icons.shield_outlined,
                    label: 'Schutz- & Bestandsstatus',
                    value: species.openData.conservationStatus,
                  ),
                  _FactItem(
                    icon: Icons.schedule_outlined,
                    label: 'Hauptaktivitätsphasen',
                    value: activePeriodsText,
                  ),
                  _FactItem(
                    icon: Icons.monitor_weight_outlined,
                    label: 'Körpergewicht & Maße',
                    value:
                        '${species.openData.bodyWeight} • ${species.openData.bodySize}',
                  ),
                  _FactItem(
                    icon: Icons.map_outlined,
                    label: 'Streifgebiet / Reviergröße',
                    value: species.openData.homeRange,
                  ),
                  _FactItem(
                    icon: Icons.event_available_outlined,
                    label: 'Jahreszeitliche Hochphase',
                    value: species.openData.peakSeason,
                  ),
                  _FactItem(
                    icon: Icons.eco_outlined,
                    label: 'Nahrungsspektrum',
                    value: species.openData.diet,
                  ),
                  _FactItem(
                    icon: Icons.pets_outlined,
                    label: 'Fährte, Losung & Feldzeichen',
                    value: species.openData.tracksAndSigns,
                  ),
                  _FactItem(
                    icon: Icons.record_voice_over_outlined,
                    label: 'Lautäußerungen',
                    value: species.openData.vocalizations,
                  ),
                  _FactItem(
                    icon: Icons.visibility_outlined,
                    label: 'Sinnesleistungen',
                    value: species.openData.sensoryStrengths,
                  ),
                  _FactItem(
                    icon: Icons.camera_alt_outlined,
                    label: 'Empfohlenes Foto-Setup',
                    value: species.openData.recommendedLens,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. Typische Verhaltensweisen
            if (species.behaviorTraits.isNotEmpty) ...[
              const Text(
                'Charakteristische Verhaltensweisen im Revier',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: WildScoutTheme.emeraldBio,
                ),
              ),
              const SizedBox(height: 8),
              ...species.behaviorTraits.map(
                (trait) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: WildScoutTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: species.accentColor.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: species.accentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              trait.tag,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: species.accentColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              trait.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: WildScoutTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        trait.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WildScoutTheme.textMuted,
                          height: 1.38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // 5. Foto-Praxis: Fluchtdistanz vs. Fotodistanz & Verschlusszeiten
            ValueListenableBuilder<PhotoGearProfile>(
              valueListenable: PhotoGearService.gearNotifier,
              builder: (context, gear, _) {
                final analysis = WildlifePhotoCalculator.calculateFramingAnalysis(
                  species: species,
                  gear: gear,
                );
                final shutter = WildlifePhotoCalculator.calculateShutterGuide(
                  species: species,
                  gear: gear,
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: WildScoutTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: WildScoutTheme.emeraldBio.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.camera_alt_outlined,
                            size: 18,
                            color: WildScoutTheme.emeraldBio,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Foto-Praxis: Fluchtdistanz vs. Fotodistanz',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: WildScoutTheme.emeraldBio,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => PhotoGearSheet.show(context),
                            icon: const Icon(Icons.tune, size: 14, color: WildScoutTheme.emeraldBio),
                            label: const Text(
                              'Optik anpassen',
                              style: TextStyle(
                                fontSize: 11,
                                color: WildScoutTheme.emeraldBio,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Distanz-Übersicht: Fluchtdistanz, Ganzkörper, Porträt
                      Row(
                        children: [
                          Expanded(
                            child: _PhotoMetricTile(
                              title: 'Fluchtdistanz',
                              value: '${species.behavior.flightDistanceMeters.round()} m',
                              icon: Icons.directions_run_outlined,
                              color: WildScoutTheme.crimsonScent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _PhotoMetricTile(
                              title: 'Ganzkörper-Foto',
                              value: '${analysis.fullBodyDistanceMeters.round()} m',
                              icon: Icons.photo_size_select_large_outlined,
                              color: analysis.fullBodyStatus == FlightDistanceStatus.safe
                                  ? WildScoutTheme.emeraldBio
                                  : WildScoutTheme.amberGold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _PhotoMetricTile(
                              title: 'Nahporträt',
                              value: '${analysis.portraitDistanceMeters.round()} m',
                              icon: Icons.face_retouching_natural,
                              color: WildScoutTheme.amberGold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Praxis-Empfehlung
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: WildScoutTheme.borderSubtle),
                        ),
                        child: Text(
                          analysis.practicalRecommendation,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WildScoutTheme.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Empfohlene Verschlusszeiten
                      const Text(
                        'Empfohlene Verschlusszeiten für diese Art',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: WildScoutTheme.amberGold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _ShutterChip(
                              label: 'Ruhend / Äsend',
                              speed: shutter.restingShutter,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ShutterChip(
                              label: 'In Bewegung / Ziehend',
                              speed: shutter.movingShutter,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            // 6. Wertvolle Praxis-Tipps für den Ansitz
            const Text(
              'Wertvolle Praxis- & Fotografie-Tipps für den Ansitz',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: WildScoutTheme.amberGold,
              ),
            ),
            const SizedBox(height: 8),
            ...species.fieldTips.map(
              (tip) => Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: WildScoutTheme.amberGold.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: WildScoutTheme.amberGold.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.tips_and_updates_outlined,
                        size: 15,
                        color: WildScoutTheme.amberGold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tip,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: WildScoutTheme.textPrimary,
                          height: 1.36,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 6. Bodenuntergrund im Sektor
            if (soilProfile != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WildScoutTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: WildScoutTheme.amberGold.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.terrain_outlined,
                          size: 17,
                          color: WildScoutTheme.amberGold,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Bodenuntergrund im Sektor (${soilProfile!.dataSource})',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: WildScoutTheme.amberGold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${soilProfile!.shortLabel} • ${soilProfile!.diggability.label}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: WildScoutTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      soilProfile!.fullGeologicalDescription,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: WildScoutTheme.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 7. Aktive Geodaten- & Habitat-Regeln
            const Text(
              'Aktive Geodaten- & Habitat-Regeln (JSON Profile Engine)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: WildScoutTheme.emeraldBio,
              ),
            ),
            const SizedBox(height: 8),
            ...species.habitatRules.landuseWeights.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.add_circle_outline,
                      size: 16,
                      color: WildScoutTheme.emeraldBio,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${w.label} (${w.osmTag})',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Text(
                      '+${w.score.toStringAsFixed(1)} Pkt.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: WildScoutTheme.emeraldBio,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...species.habitatRules.disturbancePenalties.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.remove_circle_outline,
                      size: 16,
                      color: WildScoutTheme.crimsonScent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${p.label} • Puffer ${p.radiusMeters.round()}m (${p.osmTag})',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Text(
                      '${p.penaltyScore.toStringAsFixed(1)} Pkt.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: WildScoutTheme.crimsonScent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WildScoutTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 17,
                        color: WildScoutTheme.emeraldBio,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'DSGVO Coordinate-Guard aktiv: Wetter-Abfragen senden nur das gerundete 2km-Raster ($obfuscatedLat, $obfuscatedLon).',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: WildScoutTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.photo_camera_back_outlined,
                        size: 17,
                        color: WildScoutTheme.cyanWater,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bildnachweis: Foto von ${species.imageAuthor} (${species.imageLicense}) • Quelle: ${species.imageSourceUrl}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: WildScoutTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FactItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14.5, color: WildScoutTheme.textMuted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  color: WildScoutTheme.textPrimary,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: WildScoutTheme.textMuted,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: WildScoutTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              color: WildScoutTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoMetricTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _PhotoMetricTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9.5,
              color: WildScoutTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterChip extends StatelessWidget {
  final String label;
  final String speed;

  const _ShutterChip({
    required this.label,
    required this.speed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WildScoutTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: WildScoutTheme.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            speed,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: WildScoutTheme.emeraldBio,
            ),
          ),
        ],
      ),
    );
  }
}
