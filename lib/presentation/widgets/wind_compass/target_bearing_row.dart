import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import 'wind_compass_models.dart';

class TargetBearingRow extends StatelessWidget {
  final TargetBearingInfo info;

  const TargetBearingRow({
    super.key,
    required this.info,
  });

  static String cardinalFromDegrees(double deg) {
    const directions = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
    final idx = ((deg + 22.5) % 360 / 45).floor();
    return directions[idx % 8];
  }

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    switch (info.status) {
      case ScentStatus.scentContaminated:
        badgeColor = WildlifeScoutTheme.crimsonScent;
        badgeText = 'WITTERUNGS-GEFAHR';
        badgeIcon = Icons.warning_amber_rounded;
        break;
      case ScentStatus.safeHeadwind:
        badgeColor = WildlifeScoutTheme.emeraldBio;
        badgeText = 'SICHER (GEGENWIND)';
        badgeIcon = Icons.check_circle_outline;
        break;
      case ScentStatus.crosswind:
        badgeColor = WildlifeScoutTheme.amberGold;
        badgeText = 'SEITENWIND';
        badgeIcon = Icons.swap_horiz_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: info.isPrimary
              ? badgeColor.withValues(alpha: 0.45)
              : WildlifeScoutTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(badgeIcon, size: 14, color: badgeColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        info.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (info.isPrimary) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color:
                              WildlifeScoutTheme.amberGold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'FOKUS',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: WildlifeScoutTheme.amberGold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  'Peilung ${info.bearingDeg.round()}° (${cardinalFromDegrees(info.bearingDeg)}) • ${info.distanceMeters.round()} m',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: WildlifeScoutTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: badgeColor,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
