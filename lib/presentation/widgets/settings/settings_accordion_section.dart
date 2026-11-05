import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';

/// Ein animierter, klappbarer Accordion-Karten-Listenpunkt nach Apple HIG.
class SettingsAccordionSection extends StatelessWidget {
  final int index;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String summaryBadge;
  final Color? badgeColor;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const SettingsAccordionSection({
    super.key,
    required this.index,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.summaryBadge,
    this.badgeColor,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WildlifeScoutTheme.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded
                ? iconColor.withValues(alpha: 0.4)
                : WildlifeScoutTheme.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Klickbare Accordion-Kopfzeile
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        size: 17,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Kompakte Statusanzeige auch im zugeklappten Zustand
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (badgeColor ?? iconColor).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (badgeColor ?? iconColor)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        summaryBadge,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: badgeColor ?? iconColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: WildlifeScoutTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Ausklappbarer Rumpf (Progressive Disclosure)
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: isExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(
                            height: 1,
                            color: WildlifeScoutTheme.borderSubtle,
                          ),
                          const SizedBox(height: 12),
                          ...children,
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segment-Chip für Einheiten und Optionen nach Apple HIG.
class SettingsSegmentChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelect;

  const SettingsSegmentChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? Colors.white : WildlifeScoutTheme.textMuted,
        ),
      ),
      selected: isSelected,
      selectedColor: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.35),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      side: BorderSide(
        color: isSelected
            ? WildlifeScoutTheme.emeraldBio
            : WildlifeScoutTheme.borderSubtle,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onSelected: (_) => onSelect(),
    );
  }
}
