import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import 'settings_accordion_section.dart';

/// Accordion-Sektion 4: Einheiten & Mess-Format
class SettingsUnitsSection extends StatelessWidget {
  final String windSpeedUnit;
  final String distanceUnit;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onWindSpeedUnitChanged;
  final ValueChanged<String> onDistanceUnitChanged;

  const SettingsUnitsSection({
    super.key,
    required this.windSpeedUnit,
    required this.distanceUnit,
    required this.isExpanded,
    required this.onToggle,
    required this.onWindSpeedUnitChanged,
    required this.onDistanceUnitChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsAccordionSection(
      index: 3,
      icon: Icons.tune_rounded,
      iconColor: Colors.deepPurpleAccent,
      title: 'Einheiten & Mess-Format',
      subtitle: 'Windgeschwindigkeit & Distanzen',
      summaryBadge:
          '${windSpeedUnit.toUpperCase()} • ${distanceUnit == "metric" ? "km" : "mi"}',
      isExpanded: isExpanded,
      onToggle: onToggle,
      children: [
        // Wind-Einheit
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.speed_rounded,
                size: 16,
                color: Colors.deepPurpleAccent,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wind-Geschwindigkeitseinheit',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Darstellung auf Witterungs-Kompass & Wetterkarte',
                    style: TextStyle(
                      fontSize: 11,
                      color: WildlifeScoutTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SettingsSegmentChip(
              label: 'km/h',
              isSelected: windSpeedUnit == 'kmh',
              onSelect: () => onWindSpeedUnitChanged('kmh'),
            ),
            SettingsSegmentChip(
              label: 'Beaufort (Bft)',
              isSelected: windSpeedUnit == 'bft',
              onSelect: () => onWindSpeedUnitChanged('bft'),
            ),
            SettingsSegmentChip(
              label: 'm/s',
              isSelected: windSpeedUnit == 'ms',
              onSelect: () => onWindSpeedUnitChanged('ms'),
            ),
            SettingsSegmentChip(
              label: 'Knoten (kn)',
              isSelected: windSpeedUnit == 'kn',
              onSelect: () => onWindSpeedUnitChanged('kn'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(
          height: 1,
          color: WildlifeScoutTheme.borderSubtle,
        ),
        const SizedBox(height: 8),

        // Distanz-Einheit
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.straighten_rounded,
                size: 16,
                color: Colors.deepPurpleAccent,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Distanzen & Entfernungen',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Format für Distanzen & Geländepunkte',
                    style: TextStyle(
                      fontSize: 11,
                      color: WildlifeScoutTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SettingsSegmentChip(
              label: 'Metrisch (km / m)',
              isSelected: distanceUnit == 'metric',
              onSelect: () => onDistanceUnitChanged('metric'),
            ),
            SettingsSegmentChip(
              label: 'Imperial (mi / yd)',
              isSelected: distanceUnit == 'imperial',
              onSelect: () => onDistanceUnitChanged('imperial'),
            ),
          ],
        ),
      ],
    );
  }
}
