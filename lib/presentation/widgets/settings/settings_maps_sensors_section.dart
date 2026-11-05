import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import 'settings_accordion_section.dart';

/// Accordion-Sektion 3: Karten & Sensoren
class SettingsMapsSensorsSection extends StatelessWidget {
  final bool showPlaceNames;
  final bool showRainRadar;
  final bool showCompassBeam;
  final bool showHudCompassTape;
  final bool showWindScentCone;
  final bool showDisturbanceLayer;
  final bool showLensFieldOfView;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<bool> onShowPlaceNamesChanged;
  final ValueChanged<bool> onShowRainRadarChanged;
  final ValueChanged<bool> onShowCompassBeamChanged;
  final ValueChanged<bool> onShowHudCompassTapeChanged;
  final ValueChanged<bool> onShowWindScentConeChanged;
  final ValueChanged<bool> onShowDisturbanceLayerChanged;
  final ValueChanged<bool> onShowLensFieldOfViewChanged;

  const SettingsMapsSensorsSection({
    super.key,
    required this.showPlaceNames,
    required this.showRainRadar,
    required this.showCompassBeam,
    required this.showHudCompassTape,
    required this.showWindScentCone,
    required this.showDisturbanceLayer,
    required this.showLensFieldOfView,
    required this.isExpanded,
    required this.onToggle,
    required this.onShowPlaceNamesChanged,
    required this.onShowRainRadarChanged,
    required this.onShowCompassBeamChanged,
    required this.onShowHudCompassTapeChanged,
    required this.onShowWindScentConeChanged,
    required this.onShowDisturbanceLayerChanged,
    required this.onShowLensFieldOfViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsAccordionSection(
      index: 2,
      icon: Icons.layers_outlined,
      iconColor: WildlifeScoutTheme.cyanWater,
      title: 'Karten & Sensoren',
      subtitle: 'Satellit, Radar, Peilstrahl & Witterung',
      summaryBadge: 'Ebenen',
      isExpanded: isExpanded,
      onToggle: onToggle,
      children: [
        // Orts- & Wegenamen
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.label_outline_rounded,
              size: 16,
              color: WildlifeScoutTheme.emeraldBio,
            ),
          ),
          title: const Text(
            'Orts- & Wegenamen auf Satellit',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Blendet Geländenamen über dem Satellitenlayer ein.',
            style: TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          value: showPlaceNames,
          activeTrackColor: WildlifeScoutTheme.emeraldBio,
          onChanged: onShowPlaceNamesChanged,
        ),
        const Divider(
          height: 1,
          color: WildlifeScoutTheme.borderSubtle,
        ),

        // DWD Niederschlagsradar
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.thunderstorm_outlined,
              size: 16,
              color: WildlifeScoutTheme.cyanWater,
            ),
          ),
          title: const Text(
            'DWD Niederschlags- & Gewitterradar',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Live-Radarfilm des DWD (Open Data / GeoNutzV).',
            style: TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          value: showRainRadar,
          activeTrackColor: WildlifeScoutTheme.cyanWater,
          onChanged: onShowRainRadarChanged,
        ),
        const Divider(
          height: 1,
          color: WildlifeScoutTheme.borderSubtle,
        ),

        // Blickrichtungs-Peilstrahl
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.explore_rounded,
              size: 16,
              color: WildlifeScoutTheme.cyanWater,
            ),
          ),
          title: const Text(
            'Blickrichtung & Peilstrahl',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Zeigt die Handy-Ausrichtung live als Lichtkegel auf der Karte.',
            style: TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          value: showCompassBeam,
          activeTrackColor: WildlifeScoutTheme.cyanWater,
          onChanged: onShowCompassBeamChanged,
        ),
        const Divider(
          height: 1,
          color: WildlifeScoutTheme.borderSubtle,
        ),

        // Minimalistisches HUD-Kompassband (Mobile)
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.linear_scale_rounded,
              size: 16,
              color: WildlifeScoutTheme.amberGold,
            ),
          ),
          title: const Text(
            'HUD-Kompassband (Mobile)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Horizontales 360°-Kompassband mit 5°-Schritten direkt auf dem unteren HUD.',
            style: TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          value: showHudCompassTape,
          activeTrackColor: WildlifeScoutTheme.amberGold,
          onChanged: onShowHudCompassTapeChanged,
        ),
        const Divider(
          height: 1,
          color: WildlifeScoutTheme.borderSubtle,
        ),

        // Witterungs- & Windkegel
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.air_rounded,
              size: 16,
              color: WildlifeScoutTheme.crimsonScent,
            ),
          ),
          title: const Text(
            'Witterungs- & Windkegel',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Visualisiert die menschliche Geruchsausbreitung vor Ort.',
            style: TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          value: showWindScentCone,
          activeTrackColor: WildlifeScoutTheme.crimsonScent,
          onChanged: onShowWindScentConeChanged,
        ),
        const Divider(
          height: 1,
          color: WildlifeScoutTheme.borderSubtle,
        ),

        // Rot markierte Störwege (OSM)
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.directions_bike,
              size: 16,
              color: WildlifeScoutTheme.crimsonScent,
            ),
          ),
          title: const Text(
            'Rot markierte Störwege (OSM)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Wanderpfade, Forstwege und Störradien rot auf der Karte hervorheben.',
            style: TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          value: showDisturbanceLayer,
          activeTrackColor: WildlifeScoutTheme.crimsonScent,
          onChanged: onShowDisturbanceLayerChanged,
        ),
        const Divider(
          height: 1,
          color: WildlifeScoutTheme.borderSubtle,
        ),

        // Objektiv-Blickwinkel (FOV-Modus)
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.camera_alt_rounded,
              size: 16,
              color: WildlifeScoutTheme.amberGold,
            ),
          ),
          title: const Text(
            'Objektiv-Bildwinkel (FOV)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Passt den Peilstrahl exakt an den optischen Bildwinkel deines Teleobjektivs an.',
            style: TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          value: showLensFieldOfView,
          activeTrackColor: WildlifeScoutTheme.amberGold,
          onChanged: onShowLensFieldOfViewChanged,
        ),
      ],
    );
  }
}
