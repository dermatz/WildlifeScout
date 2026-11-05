import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import '../../../domain/models/habitat_zone.dart';
import '../../../domain/models/species_profile.dart';
import '../../../domain/services/activity_score_calculator.dart';
import '../../../domain/services/wildlife_tactical_engine.dart';
import '../species_photo_avatar.dart';

class HabitatMarkerWidget extends StatelessWidget {
  final HabitatZone zone;
  final FieldAssessment zoneAssessment;
  final ZoneTacticalAssessment tactical;
  final SpeciesProfile? species;
  final Color accentColor;
  final int chanceScore;
  final Color chanceColor;
  final String chanceRating;
  final bool isSelected;
  final bool isBestChance;
  final bool openDownward;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final VoidCallback onShowExplanation;
  final void Function(SpeciesProfile species)? onOpenSpeciesInspector;

  const HabitatMarkerWidget({
    super.key,
    required this.zone,
    required this.zoneAssessment,
    required this.tactical,
    required this.species,
    required this.accentColor,
    required this.chanceScore,
    required this.chanceColor,
    required this.chanceRating,
    required this.isSelected,
    required this.isBestChance,
    required this.openDownward,
    required this.onSelect,
    required this.onClose,
    required this.onShowExplanation,
    this.onOpenSpeciesInspector,
  });

  @override
  Widget build(BuildContext context) {
    final activityScore = zoneAssessment.activityScorePercent;
    final activityColor = _colorForActivityScore(activityScore);

    if (isSelected) {
      return SizedBox(
        width: 304,
        height: 196,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Text-Callout über oder unter dem Pin
            Positioned(
              top: openDownward ? 50 : 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onShowExplanation();
                },
                child: Container(
                  width: 300,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isBestChance
                          ? WildlifeScoutTheme.amberGold
                          : Colors.white.withValues(alpha: 0.85),
                      width: 1.6,
                    ),
                    boxShadow: [
                      const BoxShadow(
                        color: Colors.black87,
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                      BoxShadow(
                        color: (isBestChance
                                ? WildlifeScoutTheme.amberGold
                                : chanceColor)
                            .withValues(alpha: 0.38),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Tier-Foto + Titel + Spezies-Badge + Schließen-Button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (species != null)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                onOpenSpeciesInspector?.call(species!);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: isBestChance
                                        ? WildlifeScoutTheme.amberGold
                                        : accentColor.withValues(alpha: 0.6),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accentColor.withValues(alpha: 0.25),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SpeciesPhotoAvatar(
                                    species: species!,
                                    width: 48,
                                    height: 48,
                                    borderRadius: 10,
                                    borderWidth: 0,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Oberste Zeile: Tag / Badge & Close
                                Row(
                                  children: [
                                    if (isBestChance) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: WildlifeScoutTheme.amberGold
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                            color: WildlifeScoutTheme.amberGold,
                                            width: 0.9,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.auto_awesome,
                                              size: 9.5,
                                              color:
                                                  WildlifeScoutTheme.amberGold,
                                            ),
                                            SizedBox(width: 2.5),
                                            Text(
                                              'BESTE CHANCE',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                color: WildlifeScoutTheme
                                                    .amberGold,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else if (species != null) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accentColor
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                            color: accentColor
                                                .withValues(alpha: 0.4),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          species!.name,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: accentColor,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        onClose();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(2.5),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),

                                // Spot-Titel
                                Text(
                                  zone.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                const SizedBox(height: 1),

                                // Chance & Rating Zeile
                                Row(
                                  children: [
                                    Icon(
                                      isBestChance
                                          ? Icons.auto_awesome
                                          : Icons.track_changes_rounded,
                                      size: 11.5,
                                      color: isBestChance
                                          ? WildlifeScoutTheme.amberGold
                                          : chanceColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$chanceScore% Chance',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: isBestChance
                                            ? WildlifeScoutTheme.amberGold
                                            : chanceColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '•  $chanceRating',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: WildlifeScoutTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),

                      // Wichtige Kern-Faktoren (Tieraktivität & Biotop-Güte)
                      Row(
                        children: [
                          // Faktor 1: Live-Aktivität
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: activityColor.withValues(alpha: 0.25),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 14,
                                    color: activityColor,
                                  ),
                                  const SizedBox(width: 3.5),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$activityScore% Aktivität',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: activityColor,
                                          ),
                                        ),
                                        const Text(
                                          'Zeit & Wetter',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w500,
                                            color: WildlifeScoutTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),

                          // Faktor 2: Biotop-Eignung
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: accentColor.withValues(alpha: 0.25),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    zone.type == HabitatZoneType.waterSuhle
                                        ? Icons.water_drop_rounded
                                        : Icons.park_rounded,
                                    size: 14,
                                    color: accentColor,
                                  ),
                                  const SizedBox(width: 3.5),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${zone.suitabilityScore.round()}% Biotop',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: accentColor,
                                          ),
                                        ),
                                        const Text(
                                          'Gelände & Äsung',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w500,
                                            color: WildlifeScoutTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Interaktiver Detail-Aufruf
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4.5,
                        ),
                        decoration: BoxDecoration(
                          color: chanceColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: chanceColor.withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.insights_rounded,
                              size: 13,
                              color: chanceColor,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                tactical.badges.isNotEmpty
                                    ? '${tactical.badges.first.icon} ${tactical.badges.first.title}'
                                    : 'Vor-Ort-Faktoren & Taktik',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: chanceColor,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            Text(
                              'Details anzeigen',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: chanceColor.withValues(alpha: 0.95),
                              ),
                            ),
                            const SizedBox(width: 1),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 13,
                              color: chanceColor.withValues(alpha: 0.85),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. Kleiner Verbindungszeiger (oben oder unten)
            Positioned(
              top: openDownward ? 40 : 146,
              child: Container(
                width: 2,
                height: 10,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),

            // 3. Highlighted Pin (exakt zentriert auf der Koordinate)
            Positioned(
              top: openDownward ? 8 : 156,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onShowExplanation();
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: WildlifeScoutTheme.bgObsidian,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isBestChance
                              ? WildlifeScoutTheme.amberGold
                              : Colors.white,
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isBestChance
                                    ? WildlifeScoutTheme.amberGold
                                    : chanceColor)
                                .withValues(alpha: 0.85),
                            blurRadius: 14,
                            spreadRadius: 2,
                          ),
                          const BoxShadow(
                            color: Colors.black87,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isBestChance
                                ? Icons.auto_awesome
                                : Icons.track_changes_rounded,
                            size: 13,
                            color: isBestChance
                                ? WildlifeScoutTheme.amberGold
                                : chanceColor,
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            '$chanceScore%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: isBestChance
                                  ? WildlifeScoutTheme.amberGold
                                  : chanceColor,
                            ),
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            'Chance',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isBestChance)
                      Positioned(
                        top: -8.5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: WildlifeScoutTheme.bgObsidian,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: WildlifeScoutTheme.amberGold,
                              width: 1.1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: WildlifeScoutTheme.amberGold
                                    .withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 9,
                                color: WildlifeScoutTheme.amberGold,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'BESTE CHANCE',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: WildlifeScoutTheme.amberGold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final badgeColor =
        isBestChance ? WildlifeScoutTheme.amberGold : chanceColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onSelect();
      },
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Haupt-Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
              decoration: BoxDecoration(
                color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: badgeColor,
                  width: isBestChance ? 2.2 : 1.8,
                ),
                boxShadow: [
                  const BoxShadow(
                    color: Colors.black87,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                  BoxShadow(
                    color: badgeColor.withValues(
                      alpha: isBestChance ? 0.55 : 0.28,
                    ),
                    blurRadius: isBestChance ? 10 : 7,
                    spreadRadius: isBestChance ? 1 : 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isBestChance
                        ? Icons.auto_awesome
                        : Icons.track_changes_rounded,
                    size: 13,
                    color: badgeColor,
                  ),
                  const SizedBox(width: 3.5),
                  Text(
                    '$chanceScore%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: badgeColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 3.5),
                  Text(
                    'Chance',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),

            // Tiername bzw. "Beste Chance" vertikal mittig auf der oberen Border positioniert
            Positioned(
              top: -8.0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.bgObsidian,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.8),
                    width: 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBestChance) ...[
                      const Icon(
                        Icons.auto_awesome,
                        size: 9,
                        color: WildlifeScoutTheme.amberGold,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      isBestChance
                          ? 'BESTE CHANCE'
                          : zone.speciesName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: badgeColor,
                        letterSpacing: 0.5,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _colorForActivityScore(int score) {
    if (score >= 78) return WildlifeScoutTheme.emeraldBio;
    if (score >= 55) return WildlifeScoutTheme.amberGold;
    return WildlifeScoutTheme.textMuted;
  }
}
