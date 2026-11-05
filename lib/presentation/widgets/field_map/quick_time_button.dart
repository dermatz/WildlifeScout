import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';

class QuickTimeButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isMobile;

  const QuickTimeButton({
    super.key,
    this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isMobile = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: isMobile ? 36 : 38),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 7.5 : 9.5,
          vertical: isMobile ? 6 : 6.5,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? WildlifeScoutTheme.emeraldBio
                : WildlifeScoutTheme.borderSubtle,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: isMobile ? 13 : 15,
                color: isSelected
                    ? WildlifeScoutTheme.emeraldBio
                    : WildlifeScoutTheme.textMuted,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: isMobile ? 11.5 : 12.5,
                fontWeight: FontWeight.w800,
                color: isSelected
                    ? WildlifeScoutTheme.emeraldBio
                    : WildlifeScoutTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
