import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/wildscout_theme.dart';
import '../../domain/models/severe_weather_alert.dart';

/// Interaktives Apple-HIG BottomSheet mit detaillierter Unwetter-Warnung
/// und Sicherheitsanweisungen für die aktive Fotosession im Naturgebiet.
class SevereWeatherAlertSheet extends StatelessWidget {
  final SevereWeatherAlert alert;
  final bool isPreviewTest;
  final VoidCallback? onEndSession;
  VoidCallback? get onEndAnsitz => onEndSession;

  const SevereWeatherAlertSheet({
    super.key,
    required this.alert,
    this.isPreviewTest = false,
    VoidCallback? onEndSession,
    VoidCallback? onEndAnsitz,
  }) : onEndSession = onEndSession ?? onEndAnsitz;

  static Future<void> show(
    BuildContext context, {
    required SevereWeatherAlert alert,
    bool isPreviewTest = false,
    VoidCallback? onEndSession,
    VoidCallback? onEndAnsitz,
  }) {
    HapticFeedback.heavyImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SevereWeatherAlertSheet(
        alert: alert,
        isPreviewTest: isPreviewTest,
        onEndSession: onEndSession ?? onEndAnsitz,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final screenHeight = mediaQuery.size.height;
    final isDanger = alert.isDanger;
    final themeColor = alert.accentColor;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.90),
          decoration: BoxDecoration(
            color: WildScoutTheme.bgObsidian.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: themeColor.withValues(alpha: 0.75),
                width: 2.0,
              ),
            ),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: bottomPadding + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
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
              const SizedBox(height: 14),

              // Header: Unwetter-Abzeichen + Titel
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: themeColor.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      alert.icon,
                      color: themeColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: themeColor.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: themeColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                isPreviewTest
                                    ? 'PROBE-ALARM'
                                    : (isDanger
                                        ? 'AKUTE LEBENSGEFAHR'
                                        : 'UNWETTER-WARNUNG'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: themeColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              alert.timeLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                color: WildScoutTheme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          alert.headline,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: WildScoutTheme.textMuted,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Schließen',
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Telemetrie-Karten (Wind, Regen, Typ)
                      Row(
                        children: [
                          Expanded(
                            child: _buildTelemetryMetric(
                              title: 'Spitzenböen',
                              value: '${alert.peakGustKmh.round()} km/h',
                              subtext: _beaufortLabel(alert.peakGustKmh),
                              icon: Icons.air_rounded,
                              color: alert.peakGustKmh >= 60.0
                                  ? WildScoutTheme.crimsonScent
                                  : WildScoutTheme.amberGold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTelemetryMetric(
                              title: 'Niederschlag',
                              value:
                                  '${alert.precipitationMm.toStringAsFixed(1)} mm/h',
                              subtext: alert.precipitationMm >= 8.0
                                  ? 'Starkregen'
                                  : 'Mäßig/Trocken',
                              icon: Icons.water_drop_rounded,
                              color: alert.precipitationMm >= 8.0
                                  ? WildScoutTheme.cyanWater
                                  : WildScoutTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTelemetryMetric(
                              title: 'Gefahr',
                              value: alert.type == SevereWeatherType.thunderstorm
                                  ? 'Gewitter'
                                  : (alert.type == SevereWeatherType.stormGusts
                                      ? 'Sturmböen'
                                      : 'Frontlinie'),
                              subtext: isDanger ? 'Stufe Rot' : 'Stufe Gelb',
                              icon: Icons.warning_amber_rounded,
                              color: themeColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Detaillierte Gefahrenbeschreibung
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: WildScoutTheme.surfaceCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: WildScoutTheme.borderSubtle,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: themeColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Lage am aktuellen Fotospot',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              alert.description,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: WildScoutTheme.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Taktische Handlungsanweisung / Wald-Sicherheit
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: themeColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  size: 18,
                                  color: themeColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Sicherheits-Protokoll Wald & Fotospot',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: themeColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              alert.safetyRecommendation,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: WildScoutTheme.textPrimary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Divider(
                              height: 1,
                              color: Colors.white12,
                            ),
                            const SizedBox(height: 8),
                            const _SafetyCheckItem(
                              icon: Icons.check_circle_outline_rounded,
                              text:
                                  'Freistehende Hochstände und Plattformen sind exponierte Blitzziele und sturmanfällig.',
                            ),
                            const SizedBox(height: 4),
                            const _SafetyCheckItem(
                              icon: Icons.check_circle_outline_rounded,
                              text:
                                  'Alte Buchen und Eichen werfen bei Böen ab 60 km/h Starkäste ab.',
                            ),
                            const SizedBox(height: 4),
                            const _SafetyCheckItem(
                              icon: Icons.check_circle_outline_rounded,
                              text:
                                  'Metallische Stative und Fernrohre leiten Blitzströme.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Aktionsbuttons
                      Row(
                        children: [
                          if (onEndSession != null && !isPreviewTest) ...[
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  Navigator.of(context).pop();
                                  onEndSession?.call();
                                },
                                icon: const Icon(
                                  Icons.stop_circle_outlined,
                                  size: 18,
                                ),
                                label: const Text('Fotosession beenden'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: WildScoutTheme.crimsonScent,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: WildScoutTheme.textPrimary,
                                side: const BorderSide(
                                  color: WildScoutTheme.borderSubtle,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                isPreviewTest
                                    ? 'Probe-Alarm schließen'
                                    : 'Warnung verstanden',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryMetric({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: WildScoutTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WildScoutTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: WildScoutTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9.5,
              color: WildScoutTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  static String _beaufortLabel(double gustKmh) {
    if (gustKmh >= 103) return 'Orkan (Bft 11+)';
    if (gustKmh >= 89) return 'Schw. Sturm (Bft 10)';
    if (gustKmh >= 75) return 'Sturm (Bft 9)';
    if (gustKmh >= 62) return 'Stürm. Wind (Bft 8)';
    if (gustKmh >= 50) return 'Starker Wind (Bft 7)';
    return 'Mäßig (Bft < 7)';
  }
}

class _SafetyCheckItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SafetyCheckItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: WildScoutTheme.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: WildScoutTheme.textMuted,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
