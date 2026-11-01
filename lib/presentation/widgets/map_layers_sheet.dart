import 'package:flutter/material.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../domain/models/species_profile.dart';

class MapLayersSheet extends StatelessWidget {
  final SpeciesProfile primarySpecies;
  final int habitatCount;
  final int trailCount;
  final bool useSatelliteLayer;
  final bool showHabitatLayer;
  final bool showDisturbanceLayer;
  final bool showScentCone;
  final bool isNightVisionRedMode;
  final ValueChanged<bool> onChangedSatellite;
  final ValueChanged<bool> onChangedHabitat;
  final ValueChanged<bool> onChangedDisturbance;
  final ValueChanged<bool> onChangedScentCone;
  final ValueChanged<bool> onChangedNightVision;
  final VoidCallback onScanCurrentMapCenter;

  const MapLayersSheet({
    super.key,
    required this.primarySpecies,
    required this.habitatCount,
    required this.trailCount,
    required this.useSatelliteLayer,
    required this.showHabitatLayer,
    required this.showDisturbanceLayer,
    required this.showScentCone,
    required this.isNightVisionRedMode,
    required this.onChangedSatellite,
    required this.onChangedHabitat,
    required this.onChangedDisturbance,
    required this.onChangedScentCone,
    required this.onChangedNightVision,
    required this.onScanCurrentMapCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildlifeScoutTheme.borderSubtle, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.layers_outlined,
                  color: WildlifeScoutTheme.cyanWater,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Karten-Elemente & Analyse-Ebenen',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Blende Overlays, Basiskarte & Sensoren nach Bedarf ein oder aus',
                      style: TextStyle(
                        fontSize: 12,
                        color: WildlifeScoutTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Basiskarte Auswahl (Satellit vs. Topografie/OSM)
          Row(
            children: [
              Expanded(
                child: _BaseMapOptionCard(
                  title: 'Satellitenbild',
                  subtitle: 'Esri Luftbild (Wald/Wiese)',
                  icon: Icons.satellite_alt,
                  isSelected: useSatelliteLayer,
                  accentColor: WildlifeScoutTheme.cyanWater,
                  onTap: () => onChangedSatellite(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BaseMapOptionCard(
                  title: 'Topo / OSM',
                  subtitle: 'Forstwege & Höhenlinien',
                  icon: Icons.map_outlined,
                  isSelected: !useSatelliteLayer,
                  accentColor: WildlifeScoutTheme.emeraldBio,
                  onTap: () => onChangedSatellite(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Schalter-Liste für Karten-Elemente
          _LayerToggleRow(
            icon: Icons.forest_outlined,
            title: 'OSM Habitate & Äsungssäume ($habitatCount)',
            subtitle:
                'Berechnete Waldrand-Buchten, Wiesen & Ruhezonen aus OpenStreetMap',
            value: showHabitatLayer,
            activeColor: WildlifeScoutTheme.emeraldBio,
            onChanged: onChangedHabitat,
          ),
          const SizedBox(height: 8),
          _LayerToggleRow(
            icon: Icons.directions_bike,
            title: 'OSM Störwege & Pufferzonen ($trailCount)',
            subtitle:
                'Wanderpfade, Radwege, Forst- & Wirtschaftswege inkl. Störradius',
            value: showDisturbanceLayer,
            activeColor: WildlifeScoutTheme.crimsonScent,
            onChanged: onChangedDisturbance,
          ),
          if (primarySpecies.behavior.scentSensitivityMeters > 0) ...[
            const SizedBox(height: 8),
            _LayerToggleRow(
              icon: Icons.air,
              title:
                  'Witterungs- & Windkegel (${primarySpecies.behavior.scentSensitivityMeters.round()}m)',
              subtitle:
                  'Live-Windfahne & Fluchtdistanz-Ring (${primarySpecies.behavior.flightDistanceMeters.round()}m) am Ansitz-Pin',
              value: showScentCone,
              activeColor: WildlifeScoutTheme.amberGold,
              onChanged: onChangedScentCone,
            ),
          ],
          const SizedBox(height: 8),
          _LayerToggleRow(
            icon: Icons.nightlight_round,
            title: 'Tarnzelt-Rotlichtmodus (Nachtsicht)',
            subtitle:
                'Monochromes Rotlicht-Farbfilter für den Ansitz in der Dunkelheit',
            value: isNightVisionRedMode,
            activeColor: WildlifeScoutTheme.crimsonScent,
            onChanged: onChangedNightVision,
          ),
          const SizedBox(height: 16),

          // Quick-Action: Aktuelle Kartenmitte neu scannen
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: WildlifeScoutTheme.emeraldBio.withValues(
                  alpha: 0.18,
                ),
                foregroundColor: WildlifeScoutTheme.emeraldBio,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.6),
                  ),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                onScanCurrentMapCenter();
              },
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text(
                'Aktuelle Kartenmitte jetzt neu scannen',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BaseMapOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  const _BaseMapOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.16)
              : WildlifeScoutTheme.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? accentColor.withValues(alpha: 0.75)
                : WildlifeScoutTheme.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? accentColor : WildlifeScoutTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? WildlifeScoutTheme.textPrimary
                          : WildlifeScoutTheme.textMuted,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: WildlifeScoutTheme.textMuted,
                    ),
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

class _LayerToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _LayerToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: WildlifeScoutTheme.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value
                ? activeColor.withValues(alpha: 0.5)
                : WildlifeScoutTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: value ? activeColor : WildlifeScoutTheme.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: WildlifeScoutTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: activeColor,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
