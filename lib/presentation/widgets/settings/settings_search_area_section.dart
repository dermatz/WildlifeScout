import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import '../../../data/services/app_settings_service.dart';
import 'settings_accordion_section.dart';

/// Accordion-Sektion 1: Fotogebiet & Umkreissuche
class SettingsSearchAreaSection extends StatelessWidget {
  static const List<double> presetRadii = [25.0, 50.0, 75.0, 100.0, 150.0];

  final double radiusKm;
  final bool autoGps;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<bool> onAutoGpsChanged;

  const SettingsSearchAreaSection({
    super.key,
    required this.radiusKm,
    required this.autoGps,
    required this.isExpanded,
    required this.onToggle,
    required this.onRadiusChanged,
    required this.onAutoGpsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsAccordionSection(
      index: 0,
      icon: Icons.radar_rounded,
      iconColor: WildlifeScoutTheme.emeraldBio,
      title: 'Fotogebiet & Umkreissuche',
      subtitle: 'Suchbereich & Standorterfassung',
      summaryBadge: '${radiusKm.round()} km',
      isExpanded: isExpanded,
      onToggle: onToggle,
      children: [
        // Suchradius
        Row(
          children: [
            const Icon(
              Icons.adjust_rounded,
              size: 16,
              color: WildlifeScoutTheme.emeraldBio,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Suchradius Umkreissuche',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '${radiusKm.round()} km',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: WildlifeScoutTheme.emeraldBio,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Legt fest, bis zu welcher Entfernung Natur- & Waldgebiete bei der Ortssuche in deiner Nähe vorgeschlagen werden.',
          style: TextStyle(
            fontSize: 11,
            color: WildlifeScoutTheme.textMuted.withValues(alpha: 0.9),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),

        // Slider
        Row(
          children: [
            const Text(
              '10 km',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: WildlifeScoutTheme.textMuted,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: WildlifeScoutTheme.emeraldBio,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: WildlifeScoutTheme.amberGold,
                  overlayColor:
                      WildlifeScoutTheme.amberGold.withValues(alpha: 0.2),
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                ),
                child: Slider(
                  value: radiusKm,
                  min: AppSettings.minSearchRadiusKm,
                  max: AppSettings.maxSearchRadiusKm,
                  divisions: 38,
                  label: '${radiusKm.round()} km',
                  onChanged: onRadiusChanged,
                ),
              ),
            ),
            const Text(
              '200 km',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: WildlifeScoutTheme.textMuted,
              ),
            ),
          ],
        ),

        // Preset Chips
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: presetRadii.map((preset) {
            final isSelected = (radiusKm - preset).abs() < 1.0;
            final isDefault =
                (preset - AppSettings.defaultSearchRadiusKm).abs() < 1.0;

            return ChoiceChip(
              label: Text(
                isDefault
                    ? '${preset.round()} km (Standard)'
                    : '${preset.round()} km',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : WildlifeScoutTheme.textMuted,
                ),
              ),
              selected: isSelected,
              selectedColor:
                  WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.35),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              side: BorderSide(
                color: isSelected
                    ? WildlifeScoutTheme.emeraldBio
                    : WildlifeScoutTheme.borderSubtle,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onSelected: (_) => onRadiusChanged(preset),
            );
          }).toList(),
        ),

        const SizedBox(height: 10),
        const Divider(
          height: 1,
          color: WildlifeScoutTheme.borderSubtle,
        ),
        const SizedBox(height: 4),

        // GPS-Startzentrierung
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.my_location_rounded,
              size: 16,
              color: WildlifeScoutTheme.emeraldBio,
            ),
          ),
          title: const Text(
            'GPS beim Start zentrieren',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Bestimmt automatisch deine Position bei App-Öffnung.',
            style: TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          value: autoGps,
          activeTrackColor: WildlifeScoutTheme.emeraldBio,
          onChanged: onAutoGpsChanged,
        ),
      ],
    );
  }
}
