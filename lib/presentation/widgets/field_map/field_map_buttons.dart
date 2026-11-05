import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';

/// Reusable 40x40 Liquid Glass Button für die ergonomische Daumenzone (Apple HIG)
class FieldFloatingButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isLoading;
  final Color? iconColor;
  final Color? badgeColor;
  final bool isActive;
  final Color? activeBorderColor;
  final Color? activeBgColor;

  const FieldFloatingButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isLoading = false,
    this.iconColor,
    this.badgeColor,
    this.isActive = false,
    this.activeBorderColor,
    this.activeBgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isActive
                      ? (activeBgColor ??
                          WildlifeScoutTheme.surfaceCard.withValues(alpha: 0.85))
                      : WildlifeScoutTheme.surfaceCard.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: isActive
                        ? (activeBorderColor ?? WildlifeScoutTheme.emeraldBio)
                        : Colors.white.withValues(alpha: 0.14),
                    width: isActive ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isActive && activeBorderColor != null
                          ? activeBorderColor!.withValues(alpha: 0.35)
                          : Colors.black45,
                      blurRadius: isActive ? 8 : 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: WildlifeScoutTheme.emeraldBio,
                        ),
                      )
                    else
                      Icon(
                        icon,
                        size: 19,
                        color: iconColor ?? WildlifeScoutTheme.textPrimary,
                      ),
                    if (badgeColor != null)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 6.5,
                          height: 6.5,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: badgeColor!.withValues(alpha: 0.65),
                                blurRadius: 3.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BestChanceFloatingButton extends StatelessWidget {
  final bool hasZones;
  final VoidCallback onTap;

  const BestChanceFloatingButton({
    super.key,
    required this.hasZones,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Beste Chance: Wählt automatisch Top-Tag, Uhrzeit & Fotospot',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      WildlifeScoutTheme.amberGold.withValues(alpha: 0.32),
                      WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.90),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.75),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.stars_rounded,
                    color: WildlifeScoutTheme.amberGold,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
