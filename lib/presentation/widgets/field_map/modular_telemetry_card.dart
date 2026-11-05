import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/wildlifescout_theme.dart';

class ModularTelemetryCard extends StatelessWidget {
  final String category;
  final IconData icon;
  final Color iconColor;
  final String value;
  final String detail;
  final Color? detailColor;
  final String? tooltipMessage;
  final VoidCallback? onTap;

  const ModularTelemetryCard({
    super.key,
    required this.category,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.detail,
    this.detailColor,
    this.tooltipMessage,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: detailColor != null && detailColor != WildlifeScoutTheme.textMuted
              ? detailColor!.withValues(alpha: 0.35)
              : WildlifeScoutTheme.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 5),
              Text(
                category.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: WildlifeScoutTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: detailColor ?? WildlifeScoutTheme.textMuted,
              height: 1.25,
            ),
          ),
        ],
      ),
    );

    Widget content = card;
    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap!();
          },
          child: card,
        ),
      );
    }

    if (tooltipMessage != null && tooltipMessage!.isNotEmpty) {
      return Tooltip(
        message: tooltipMessage!,
        child: content,
      );
    }
    return content;
  }
}
