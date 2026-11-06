import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/wildlifescout_theme.dart';
import '../../../domain/models/severe_weather_alert.dart';
import '../../../domain/models/species_profile.dart';
import '../severe_weather_alert_sheet.dart';

class FieldTopBar extends StatelessWidget {
  final SpeciesProfile primarySpecies;
  final int selectedSpeciesCount;
  final String currentRegionTitle;
  final int habitatZoneCount;
  final String osmDataSourceStatus;
  final bool isLoadingOsm;
  final bool isLocatingUser;
  final Animation<double> radarAnimation;
  final SevereWeatherAlert? severeWeatherAlert;
  final VoidCallback onSpeciesSelectTap;
  final VoidCallback onSettingsTap;
  final VoidCallback? onEndSevereWeatherSession;

  const FieldTopBar({
    super.key,
    required this.primarySpecies,
    required this.selectedSpeciesCount,
    required this.currentRegionTitle,
    required this.habitatZoneCount,
    required this.osmDataSourceStatus,
    required this.isLoadingOsm,
    required this.isLocatingUser,
    required this.radarAnimation,
    this.severeWeatherAlert,
    required this.onSpeciesSelectTap,
    required this.onSettingsTap,
    this.onEndSevereWeatherSession,
  });

  @override
  Widget build(BuildContext context) {
    final extraCount = selectedSpeciesCount - 1;
    final speciesName = primarySpecies.displayShortName;
    final speciesSemanticLabel = extraCount > 0
        ? 'Wildart: ${primarySpecies.name} und $extraCount weitere. Auswahl öffnen'
        : 'Wildart: ${primarySpecies.name}. Auswahl öffnen';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: WildlifeScoutTheme.glassDecoration(
            borderRadius: 20,
            shadows: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, rowConstraints) {
              // Fixe Breiten: Logo 36 + 10 Abstand + 8 + 8 Abstände + Settings 44.
              const fixedWidth = 36.0 + 10 + 8 + 8 + 44;
              final speciesMaxWidth =
                  ((rowConstraints.maxWidth - fixedWidth) * 5 / 9).clamp(
                    80.0,
                    double.infinity,
                  );
              return Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          WildlifeScoutTheme.emeraldBio,
                          Color(0xFF059669),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: RotationTransition(
                      turns: (isLoadingOsm || isLocatingUser)
                          ? radarAnimation
                          : const AlwaysStoppedAnimation(0.0),
                      child: const Icon(
                        Icons.radar,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Tooltip(
                      message: osmDataSourceStatus,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Zeile 1: Titel WILDLIFESCOUT
                          const Text(
                            'WILDLIFESCOUT',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15.0,
                              letterSpacing: 0.6,
                              color: WildlifeScoutTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Zeile 2: Habitate
                          Text(
                            isLoadingOsm
                                ? 'Scanne Habitate...'
                                : '$habitatZoneCount Habitate',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w600,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          if (severeWeatherAlert != null) ...[
                            const SizedBox(height: 3),
                            InkWell(
                              onTap: () {
                                SevereWeatherAlertSheet.show(
                                  context,
                                  alert: severeWeatherAlert!,
                                  onEndSession: onEndSevereWeatherSession,
                                );
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: severeWeatherAlert!.accentColor
                                      .withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: severeWeatherAlert!.accentColor
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      severeWeatherAlert!.icon,
                                      size: 11,
                                      color: severeWeatherAlert!.accentColor,
                                    ),
                                    const SizedBox(width: 3.5),
                                    Text(
                                      severeWeatherAlert!.isDanger
                                          ? 'ALARM'
                                          : 'UNWETTER',
                                      style: TextStyle(
                                        fontSize: 10.0,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.4,
                                        color: severeWeatherAlert!.accentColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Kompakter Tier-Auswahl Button mit Bild als Background
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: speciesMaxWidth),
                    child: Semantics(
                      button: true,
                      label: speciesSemanticLabel,
                      excludeSemantics: true,
                      child: Tooltip(
                        message: 'Wildarten & Biologie-Steckbrief öffnen',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              onSpeciesSelectTap();
                            },
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 44),
                              foregroundDecoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: primarySpecies.accentColor.withValues(
                                    alpha: 0.85,
                                  ),
                                  width: 1.5,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: WildlifeScoutTheme.surfaceCard,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  const BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                  BoxShadow(
                                    color: primarySpecies.accentColor
                                        .withValues(alpha: 0.20),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned.fill(
                                    child: _buildSpeciesBackground(
                                      primarySpecies,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.black.withValues(
                                              alpha: 0.65,
                                            ),
                                            Colors.black.withValues(
                                              alpha: 0.52,
                                            ),
                                          ],
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            speciesName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                              shadows: [
                                                Shadow(
                                                  blurRadius: 4,
                                                  color: Colors.black,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (extraCount > 0) ...[
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: primarySpecies.accentColor
                                                  .withValues(alpha: 0.9),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '+$extraCount',
                                              maxLines: 1,
                                              softWrap: false,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // App-Einstellungen & Suchradius im Header direkt rechts neben der Tierauswahl
                  Tooltip(
                    message: 'App-Einstellungen & Suchradius',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onSettingsTap();
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: WildlifeScoutTheme.surfaceCard.withValues(
                              alpha: 0.85,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                              width: 1.2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.tune_rounded,
                              size: 19,
                              color: WildlifeScoutTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSpeciesBackground(SpeciesProfile species) {
    if (species.imageAssetPath.isNotEmpty) {
      return Image.asset(
        species.imageAssetPath,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          if (species.imageUrl.isNotEmpty) {
            return Image.network(
              species.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(color: species.accentColor.withValues(alpha: 0.3)),
            );
          }
          return Container(color: species.accentColor.withValues(alpha: 0.3));
        },
      );
    }
    if (species.imageUrl.isNotEmpty) {
      return Image.network(
        species.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Container(color: species.accentColor.withValues(alpha: 0.3)),
      );
    }
    return Container(color: species.accentColor.withValues(alpha: 0.3));
  }
}
