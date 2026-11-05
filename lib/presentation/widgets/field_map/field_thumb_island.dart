import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import '../../../domain/models/weather_frame.dart';
import 'field_map_buttons.dart';

enum ThumbCluster {
  none,
  navigation,
  tools,
}

/// Schwebende Funktions-Insel in der ergonomischen Daumenzone (Rechts)
class FieldThumbIsland extends StatelessWidget {
  final ThumbCluster activeCluster;
  final ValueChanged<ThumbCluster> onClusterChanged;
  final bool hasHabitatZones;
  final int savedSpotCount;
  final bool isLocatingUser;
  final bool isNightVisionRedMode;
  final bool showRainRadarLayer;
  final bool useSatelliteLayer;
  final WeatherFrame currentWeather;
  final double effectiveFocalLengthMm;
  final double mapRotation;
  final VoidCallback onResetNorth;
  final VoidCallback onApplyBestChance;
  final VoidCallback onOpenLayers;
  final VoidCallback onOpenSpotVault;
  final VoidCallback onOpenLocationSearch;
  final VoidCallback onLocateUser;
  final VoidCallback onOpenWindCompass;
  final VoidCallback onOpenPhotoGear;

  const FieldThumbIsland({
    super.key,
    required this.activeCluster,
    required this.onClusterChanged,
    required this.hasHabitatZones,
    required this.savedSpotCount,
    required this.isLocatingUser,
    required this.isNightVisionRedMode,
    required this.showRainRadarLayer,
    required this.useSatelliteLayer,
    required this.currentWeather,
    required this.effectiveFocalLengthMm,
    this.mapRotation = 0.0,
    required this.onResetNorth,
    required this.onApplyBestChance,
    required this.onOpenLayers,
    required this.onOpenSpotVault,
    required this.onOpenLocationSearch,
    required this.onLocateUser,
    required this.onOpenWindCompass,
    required this.onOpenPhotoGear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 1. Navigation & Orte (Standort, Suche, Gemerkte Punkte) – Ganz oben
        _buildNavigationCluster(),
        const SizedBox(height: 6),

        // 2. Quick Action: "Beste Chance" (Top-Tag, Uhrzeit & Fotospot) – Position 2
        BestChanceFloatingButton(
          hasZones: hasHabitatZones,
          onTap: () {
            if (activeCluster != ThumbCluster.none) {
              onClusterChanged(ThumbCluster.none);
            }
            onApplyBestChance();
          },
        ),
        const SizedBox(height: 6),

        // 3. Karten-Ebenen & Nachtmodus (1-Tap Direktzugriff)
        FieldFloatingButton(
          icon: Icons.layers_rounded,
          tooltip: 'Karten-Ebenen & Nachtsicht',
          badgeColor: isNightVisionRedMode
              ? WildlifeScoutTheme.crimsonScent
              : (showRainRadarLayer
                  ? WildlifeScoutTheme.cyanWater
                  : (!useSatelliteLayer ? WildlifeScoutTheme.cyanWater : null)),
          onTap: () {
            HapticFeedback.lightImpact();
            if (activeCluster != ThumbCluster.none) {
              onClusterChanged(ThumbCluster.none);
            }
            onOpenLayers();
          },
        ),
        const SizedBox(height: 6),

        // 4. Ansitz- & Feld-Tools (Witterungs-Kompass & Sensor-Optik)
        _buildToolsCluster(),
      ],
    );
  }

  Widget _buildNavigationCluster() {
    final isExpanded = activeCluster == ThumbCluster.navigation;
    final isRotated = (mapRotation % 360).abs() > 1.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerRight,
          child: isExpanded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nordausrichtung (nur sichtbar wenn gedreht)
                    if (isRotated) ...[
                      FieldFloatingButton(
                        icon: Icons.navigation_rounded,
                        tooltip: 'Karte nach Norden ausrichten & zentrieren',
                        iconColor: WildlifeScoutTheme.crimsonScent,
                        badgeColor: WildlifeScoutTheme.crimsonScent,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          onResetNorth();
                        },
                      ),
                      const SizedBox(width: 6),
                    ],

                    // Gemerkte Punkte (Spot-Tresor)
                    FieldFloatingButton(
                      icon: Icons.bookmark_rounded,
                      tooltip: 'Geheimer Spot-Tresor ($savedSpotCount)',
                      badgeColor: savedSpotCount > 0
                          ? WildlifeScoutTheme.amberGold
                          : null,
                      iconColor: WildlifeScoutTheme.amberGold,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onClusterChanged(ThumbCluster.none);
                        onOpenSpotVault();
                      },
                    ),
                    const SizedBox(width: 6),

                    // Ort / Waldgebiet suchen
                    FieldFloatingButton(
                      icon: Icons.search_rounded,
                      tooltip: 'Ort, Waldgebiet oder Koordinaten suchen',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onClusterChanged(ThumbCluster.none);
                        onOpenLocationSearch();
                      },
                    ),
                    const SizedBox(width: 6),

                    // GPS / Standort zentrieren
                    FieldFloatingButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'Zum aktuellen Standort springen',
                      isLoading: isLocatingUser,
                      iconColor: WildlifeScoutTheme.emeraldBio,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onClusterChanged(ThumbCluster.none);
                        onLocateUser();
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        // Trigger Button für Navigation
        FieldFloatingButton(
          icon: isExpanded ? Icons.close_rounded : Icons.near_me_rounded,
          tooltip: isExpanded
              ? 'Navigation schließen'
              : 'Navigation & Orte (Standort, Suche, Spots)',
          isActive: isExpanded,
          activeBorderColor: WildlifeScoutTheme.emeraldBio,
          activeBgColor: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.22),
          iconColor: isExpanded
              ? WildlifeScoutTheme.emeraldBio
              : WildlifeScoutTheme.textPrimary,
          badgeColor: (!isExpanded && savedSpotCount > 0)
              ? WildlifeScoutTheme.amberGold
              : null,
          onTap: () {
            HapticFeedback.lightImpact();
            onClusterChanged(
              isExpanded ? ThumbCluster.none : ThumbCluster.navigation,
            );
          },
        ),
      ],
    );
  }

  Widget _buildToolsCluster() {
    final isExpanded = activeCluster == ThumbCluster.tools;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerRight,
          child: isExpanded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Witterungs- & Wind-Kompass (mit offiziellem Kompass-Symbol)
                    FieldFloatingButton(
                      icon: Icons.explore_rounded,
                      tooltip:
                          '360° Witterungs- & Wind-Kompass (${currentWeather.windCardinalLabel}, ${currentWeather.windSpeedKmh.round()} km/h)',
                      badgeColor: WildlifeScoutTheme.cyanWater,
                      iconColor: WildlifeScoutTheme.cyanWater,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onClusterChanged(ThumbCluster.none);
                        onOpenWindCompass();
                      },
                    ),
                    const SizedBox(width: 6),

                    // 2. Foto-Ausrüstung & Wildlife-Optik (Optik/Fokus-Symbol statt Kamera)
                    FieldFloatingButton(
                      icon: Icons.center_focus_strong_rounded,
                      tooltip:
                          'Optik- & Sensor-Setup (${effectiveFocalLengthMm.round()} mm KB)',
                      badgeColor: WildlifeScoutTheme.cyanWater,
                      iconColor: WildlifeScoutTheme.cyanWater,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onClusterChanged(ThumbCluster.none);
                        onOpenPhotoGear();
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        // Trigger Button für Ansitz- & Feld-Tools (Sensorik & Optik)
        FieldFloatingButton(
          icon: isExpanded ? Icons.close_rounded : Icons.sensors_rounded,
          tooltip: isExpanded
              ? 'Tools schließen'
              : 'Ansitz-Tools (Witterungs-Kompass & Sensor-Optik)',
          isActive: isExpanded,
          activeBorderColor: WildlifeScoutTheme.cyanWater,
          activeBgColor: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.22),
          iconColor: isExpanded
              ? WildlifeScoutTheme.cyanWater
              : WildlifeScoutTheme.textPrimary,
          onTap: () {
            HapticFeedback.lightImpact();
            onClusterChanged(
              isExpanded ? ThumbCluster.none : ThumbCluster.tools,
            );
          },
        ),
      ],
    );
  }
}
