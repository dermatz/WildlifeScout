import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import '../../../data/services/app_settings_service.dart';
import 'settings_accordion_section.dart';

/// Accordion-Sektion 2: Unwetter-Warnung am Fotospot
class SettingsSevereWeatherSection extends StatelessWidget {
  static const List<double> presetGustThresholds = [50.0, 60.0, 75.0];

  final bool warnSevereWeather;
  final double gustThresholdKmh;
  final bool severeWeatherHaptics;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<bool> onWarnSevereWeatherChanged;
  final ValueChanged<double> onGustThresholdChanged;
  final ValueChanged<bool> onSevereWeatherHapticsChanged;
  final VoidCallback onTriggerTestAlert;

  const SettingsSevereWeatherSection({
    super.key,
    required this.warnSevereWeather,
    required this.gustThresholdKmh,
    required this.severeWeatherHaptics,
    required this.isExpanded,
    required this.onToggle,
    required this.onWarnSevereWeatherChanged,
    required this.onGustThresholdChanged,
    required this.onSevereWeatherHapticsChanged,
    required this.onTriggerTestAlert,
  });

  static String gustThresholdLabel(double gust) {
    if (gust >= 75) return 'Bft 9 • Sturm';
    if (gust >= 62) return 'Bft 8 • Sturmböen';
    if (gust >= 50) return 'Bft 7 • Starker Wind';
    return 'Bft 6 • Kräftig';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsAccordionSection(
      index: 1,
      icon: Icons.warning_amber_rounded,
      iconColor: WildlifeScoutTheme.amberGold,
      title: 'Unwetter-Warnung am Fotospot',
      subtitle: 'Sturmwarnung & Probe-Alarm',
      summaryBadge: warnSevereWeather ? '${gustThresholdKmh.round()} km/h' : 'Aus',
      badgeColor: warnSevereWeather
          ? WildlifeScoutTheme.amberGold
          : WildlifeScoutTheme.textMuted,
      isExpanded: isExpanded,
      onToggle: onToggle,
      children: [
        // Unwetterwarnung Toggle
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Vor Unwetter bei aktiver Fotosession warnen',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Überwacht das Wetter live am Fotospot und warnt vor Gefahren.',
            style: TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          value: warnSevereWeather,
          activeTrackColor: WildlifeScoutTheme.amberGold,
          onChanged: onWarnSevereWeatherChanged,
        ),

        if (warnSevereWeather) ...[
          const Divider(
            height: 1,
            color: WildlifeScoutTheme.borderSubtle,
          ),
          const SizedBox(height: 10),

          // Böenschwelle
          Row(
            children: [
              const Icon(
                Icons.air_rounded,
                size: 16,
                color: WildlifeScoutTheme.amberGold,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Böenschwelle für Sturmwarnung',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${gustThresholdKmh.round()} km/h',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: WildlifeScoutTheme.amberGold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ab dieser Windstärke wird Astbruch-Alarm geschlagen (${gustThresholdLabel(gustThresholdKmh)}).',
            style: const TextStyle(
              fontSize: 11,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),

          // Slider
          Row(
            children: [
              const Text(
                '45 km/h',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: WildlifeScoutTheme.amberGold,
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
                    value: gustThresholdKmh,
                    min: AppSettings.minWindGustThresholdKmh,
                    max: AppSettings.maxWindGustThresholdKmh,
                    divisions: 9,
                    label: '${gustThresholdKmh.round()} km/h',
                    onChanged: onGustThresholdChanged,
                  ),
                ),
              ),
              const Text(
                '90 km/h',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
            ],
          ),

          // Schnellwahl-Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: presetGustThresholds.map((preset) {
              final isSelected = (gustThresholdKmh - preset).abs() < 1.0;
              final isDefault =
                  (preset - AppSettings.defaultWindGustThresholdKmh).abs() <
                      1.0;

              return ChoiceChip(
                label: Text(
                  isDefault
                      ? '${preset.round()} km/h (Standard • Bft 8)'
                      : (preset >= 75
                          ? '${preset.round()} km/h (Bft 9 Sturm)'
                          : '${preset.round()} km/h (Bft 7)'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : WildlifeScoutTheme.textMuted,
                  ),
                ),
                selected: isSelected,
                selectedColor:
                    WildlifeScoutTheme.amberGold.withValues(alpha: 0.35),
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(
                  color: isSelected
                      ? WildlifeScoutTheme.amberGold
                      : WildlifeScoutTheme.borderSubtle,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onSelected: (_) => onGustThresholdChanged(preset),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),
          const Divider(
            height: 1,
            color: WildlifeScoutTheme.borderSubtle,
          ),

          // Haptik & Signal
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.vibration_rounded,
                size: 16,
                color: WildlifeScoutTheme.amberGold,
              ),
            ),
            title: const Text(
              'Vibrations- & Signal-Alarm',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Löst bei akuter Lebensgefahr durch Sturm oder Gewitter spürbare Haptik aus.',
              style: TextStyle(
                fontSize: 11,
                color: WildlifeScoutTheme.textMuted,
              ),
            ),
            value: severeWeatherHaptics,
            activeTrackColor: WildlifeScoutTheme.amberGold,
            onChanged: onSevereWeatherHapticsChanged,
          ),

          const SizedBox(height: 6),

          // Wald-Sicherheitshinweis
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.25),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 15,
                  color: WildlifeScoutTheme.amberGold,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Wald-Sicherheit: Ab 60 km/h (Bft 8) brechen größere Äste ab. Auf erhöhten Plattformen besteht Lebensgefahr. Bei Gewitter offenes Gelände umgehend verlassen.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: WildlifeScoutTheme.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Probe-Alarm testen Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onTriggerTestAlert,
              icon: const Icon(
                Icons.play_circle_outline_rounded,
                size: 16,
                color: WildlifeScoutTheme.amberGold,
              ),
              label: const Text(
                'Probe-Alarm testen',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WildlifeScoutTheme.amberGold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.5),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 9,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
