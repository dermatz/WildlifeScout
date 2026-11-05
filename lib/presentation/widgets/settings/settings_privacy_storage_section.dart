import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import 'settings_accordion_section.dart';

/// Accordion-Sektion 5: Datenschutz & Speicher
class SettingsPrivacyStorageSection extends StatelessWidget {
  final int savedSpotsCount;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onResetDefaults;

  const SettingsPrivacyStorageSection({
    super.key,
    required this.savedSpotsCount,
    required this.isExpanded,
    required this.onToggle,
    required this.onResetDefaults,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsAccordionSection(
          index: 4,
          icon: Icons.security_rounded,
          iconColor: WildlifeScoutTheme.cyanWater,
          title: 'Datenschutz & Speicher',
          subtitle: 'Zero-Track Garantie & Spot-Tresor',
          summaryBadge: 'Zero-Track',
          isExpanded: isExpanded,
          onToggle: onToggle,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    size: 16,
                    color: WildlifeScoutTheme.cyanWater,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DSGVO & Zero-Track Garantie',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Deine Suchanfragen und Fotospots bleiben lokal. Der CoordinateGuard rundet Wetter-Abfragen auf 2 km ab.',
                        style: TextStyle(
                          fontSize: 11,
                          color: WildlifeScoutTheme.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(
              height: 1,
              color: WildlifeScoutTheme.borderSubtle,
            ),
            const SizedBox(height: 8),

            // Lokaler Spot-Tresor Status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Spot-Tresor (SpotVault)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$savedSpotsCount Fotospots sicher auf diesem Gerät gespeichert',
                        style: const TextStyle(
                          fontSize: 11,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'OFFLINE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: WildlifeScoutTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Reset-Button auf Standardwerte
        Center(
          child: TextButton.icon(
            onPressed: onResetDefaults,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text(
              'Auf Standardwerte zurücksetzen (50 km)',
              style: TextStyle(fontSize: 12),
            ),
            style: TextButton.styleFrom(
              foregroundColor: WildlifeScoutTheme.textMuted,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
