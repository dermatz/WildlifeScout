import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import '../../../domain/models/severe_weather_alert.dart';
import '../../../domain/models/species_profile.dart';
import '../../../domain/models/weather_frame.dart';
import '../../../domain/services/activity_score_calculator.dart';
import '../../../domain/services/sun_moon_calculator.dart';
import '../tactical_windy_weather_sheet.dart';
import 'field_slider_track_shape.dart';
import 'modular_telemetry_card.dart';
import 'quick_time_button.dart';
import 'severe_weather_hud.dart';

class FieldBottomControlDeck extends StatelessWidget {
  final SpeciesProfile species;
  final WeatherFrame weather;
  final SunMoonPosition astro;
  final FieldAssessment assessment;
  final SevereWeatherAlert? severeWeatherAlert;
  final int selectedDayOffset;
  final int selectedHourOfDay;
  final List<WeatherFrame> hourlyForecast;
  final bool isDeckExpanded;
  final bool isSessionActive;
  final double latitude;
  final double longitude;
  final VoidCallback onToggleExpanded;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onDayOffsetChanged;
  final VoidCallback? onEndSevereWeatherSession;
  final VoidCallback onOpenWindCompass;
  final void Function(WindyOverlayMode mode)? onOpenTacticalWindy;
  final void Function({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<({String heading, String description, IconData icon})> points,
  }) onShowTelemetryExplainer;

  const FieldBottomControlDeck({
    super.key,
    required this.species,
    required this.weather,
    required this.astro,
    required this.assessment,
    this.severeWeatherAlert,
    required this.selectedDayOffset,
    required this.selectedHourOfDay,
    required this.hourlyForecast,
    required this.isDeckExpanded,
    required this.isSessionActive,
    required this.latitude,
    required this.longitude,
    required this.onToggleExpanded,
    required this.onHourChanged,
    required this.onDayOffsetChanged,
    this.onEndSevereWeatherSession,
    required this.onOpenWindCompass,
    this.onOpenTacticalWindy,
    required this.onShowTelemetryExplainer,
  });

  static Color colorForActivityScore(int score) {
    if (score >= 78) return WildlifeScoutTheme.emeraldBio;
    if (score >= 55) return WildlifeScoutTheme.amberGold;
    return WildlifeScoutTheme.textMuted;
  }

  static String dayLabelForOffset(int dayOffset) {
    final date = DateTime.now().add(Duration(days: dayOffset));
    if (dayOffset == 0) return 'Heute';
    if (dayOffset == 1) return 'Morgen';
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final wd = weekdays[(date.weekday - 1) % 7];
    return '$wd ${date.day}.${date.month}.';
  }

  (IconData icon, Color color, String val, String detail) _getBarometerTelemetry(
    WeatherFrame weather,
  ) {
    final delta = weather.pressureDelta6hHpa;
    final valStr = '${weather.surfacePressureHpa.round()} hPa';
    if (delta <= -2.0) {
      return (
        Icons.trending_down_rounded,
        WildlifeScoutTheme.amberGold,
        valStr,
        '⚡ Fällt (${delta.toStringAsFixed(1)}) • Fress-Schub',
      );
    } else if (delta <= -0.7) {
      return (
        Icons.trending_down_rounded,
        WildlifeScoutTheme.amberGold,
        valStr,
        'Fällt (${delta.toStringAsFixed(1)}) • Mehr Aktivität',
      );
    } else if (delta >= 1.5) {
      return (
        Icons.trending_up_rounded,
        WildlifeScoutTheme.cyanWater,
        valStr,
        'Steigt (+${delta.toStringAsFixed(1)}) • Ruhiges Wild',
      );
    } else {
      return (
        Icons.trending_flat_rounded,
        WildlifeScoutTheme.textMuted,
        valStr,
        'Stabil • Gewohnter Rhythmus',
      );
    }
  }

  (IconData icon, Color color, String val, String detail) _getAstroTelemetry(
    SunMoonPosition astro,
    WeatherFrame weather,
  ) {
    final isMorning = weather.time.hour < 12;

    int calculateAlpenglowProbability() {
      if (astro.sunElevationDegrees < -4.0 || astro.sunElevationDegrees > 5.0) {
        return 0;
      }
      if (weather.precipitationMm > 0.2 || weather.isFog) {
        return 0;
      }

      final elevDist = (astro.sunElevationDegrees - 0.5).abs();
      final elevFactor = (1.0 - (elevDist / 4.5)).clamp(0.0, 1.0);

      final cloud = weather.cloudCoverPercent;
      double cloudFactor = 0.0;
      if (weather.cloudCoverLowPercent >= 75) {
        cloudFactor = 0.0;
      } else if (weather.cloudCoverHighPercent >= 35 &&
          weather.cloudCoverLowPercent <= 30) {
        cloudFactor = 1.0;
      } else if (cloud >= 10 && cloud <= 80) {
        if (cloud >= 30 && cloud <= 60) {
          cloudFactor = 1.0;
        } else if (cloud < 30) {
          cloudFactor = (cloud - 10) / 20.0;
        } else {
          cloudFactor = 1.0 - ((cloud - 60) / 20.0);
        }
      }

      final prob = (elevFactor * cloudFactor * 100.0).round();
      return prob.clamp(0, 95);
    }

    final alpenglowProb = calculateAlpenglowProbability();

    if (alpenglowProb >= 25) {
      return (
        Icons.wb_twilight_rounded,
        const Color(0xFFFF6B6B),
        isMorning ? 'Morgenrot ($alpenglowProb%)' : 'Abendrot ($alpenglowProb%)',
        isMorning
            ? 'Ost • ${astro.sunElevationDegrees.toStringAsFixed(0)}° Horizont'
            : 'West • ${astro.sunElevationDegrees.toStringAsFixed(0)}° Horizont',
      );
    } else if (astro.isGoldenHour) {
      return (
        Icons.wb_twilight_rounded,
        WildlifeScoutTheme.amberGold,
        isMorning ? 'Morgen-Gold' : 'Abend-Gold',
        '${astro.sunElevationDegrees.toStringAsFixed(0)}° Streiflicht',
      );
    } else if (astro.isBlueHour) {
      return (
        Icons.wb_twilight_rounded,
        WildlifeScoutTheme.cyanWater,
        'Blaue Std.',
        isMorning ? 'Frühdämmerung' : 'Spätdämmerung',
      );
    } else if (astro.currentPeriod == ActivityPeriod.night) {
      final moonPct = (astro.moonIlluminationFraction * 100).round();
      return (
        Icons.nightlight_round,
        const Color(0xFFC7D2FE),
        '$moonPct% Mond',
        astro.moonPhaseName,
      );
    } else if (astro.sunElevationDegrees > 25) {
      return (
        Icons.wb_sunny_rounded,
        WildlifeScoutTheme.amberGold,
        'Sonne',
        '${astro.sunElevationDegrees.round()}°',
      );
    } else {
      return (
        Icons.wb_sunny_outlined,
        WildlifeScoutTheme.textMuted,
        'Weiches Licht',
        '${astro.sunElevationDegrees.round()}°',
      );
    }
  }

  (IconData icon, Color color, String val, String detail) _getSkyTelemetry(
    WeatherFrame weather,
    SunMoonPosition astro,
  ) {
    if (weather.precipitationMm > 0.1) {
      return (
        Icons.water_drop_rounded,
        WildlifeScoutTheme.cyanWater,
        '${weather.precipitationMm.toStringAsFixed(1)} mm',
        'Regen',
      );
    } else if (weather.isFog ||
        (weather.visibilityMeters != null && weather.visibilityMeters! < 1000)) {
      return (
        Icons.cloud_queue_rounded,
        const Color(0xFFCBD5E1),
        'Nebel',
        weather.visibilityMeters != null
            ? 'Sicht ${(weather.visibilityMeters! / 1000).toStringAsFixed(1)} km'
            : 'Sicht < 1 km',
      );
    } else if (weather.cloudCoverPercent >= 75) {
      final detailStr = weather.cloudCoverLowPercent >= 70
          ? 'Tiefe Decke'
          : weather.cloudCoverHighPercent >= 60
              ? 'Cirrenschleier'
              : 'Bedeckt';
      return (
        Icons.cloud_rounded,
        WildlifeScoutTheme.textMuted,
        '${weather.cloudCoverPercent}%',
        detailStr,
      );
    } else if (weather.cloudCoverPercent >= 25) {
      final detailStr = weather.cloudCoverMidPercent >= 35
          ? 'Softbox-Licht'
          : weather.cloudCoverHighPercent >= 30
              ? 'Streulicht'
              : 'Leicht bewölkt';
      return (
        Icons.cloud_queue_rounded,
        const Color(0xFFBAE6FD),
        '${weather.cloudCoverPercent}%',
        detailStr,
      );
    } else {
      return (
        astro.currentPeriod == ActivityPeriod.night
            ? Icons.nightlight_round
            : Icons.wb_sunny_rounded,
        astro.currentPeriod == ActivityPeriod.night
            ? const Color(0xFFC7D2FE)
            : WildlifeScoutTheme.amberGold,
        'Klar',
        astro.currentPeriod == ActivityPeriod.night
            ? 'Klarer Sternenhimmel'
            : 'Klares Sonnenlicht',
      );
    }
  }

  (IconData icon, Color color, String val, String detail) _getWindTelemetry(
    WeatherFrame weather,
  ) {
    final spd = weather.windSpeedKmh.round();
    final card = weather.windCardinalLabel;
    final valStr = '$spd km/h $card';
    if (weather.windSpeedKmh < 4.0) {
      return (
        Icons.air_rounded,
        WildlifeScoutTheme.amberGold,
        valStr,
        'Thermik-Risiko',
      );
    } else if (weather.windSpeedKmh > 25.0) {
      return (
        Icons.air_rounded,
        WildlifeScoutTheme.crimsonScent,
        valStr,
        'Böig',
      );
    } else {
      return (
        Icons.air_rounded,
        WildlifeScoutTheme.emeraldBio,
        valStr,
        'Stetig',
      );
    }
  }

  IconData _getWeatherIcon(WeatherFrame weather, SunMoonPosition astro) {
    if (weather.precipitationMm > 0.1) return Icons.water_drop_rounded;
    if (weather.cloudCoverPercent >= 75) return Icons.cloud_rounded;
    if (weather.cloudCoverPercent >= 25) {
      return astro.currentPeriod == ActivityPeriod.night
          ? Icons.nightlight_outlined
          : Icons.cloud_queue_rounded;
    }
    if (astro.currentPeriod == ActivityPeriod.night) {
      return Icons.nightlight_round;
    }
    return Icons.wb_sunny_rounded;
  }

  Color _getWeatherIconColor(WeatherFrame weather, SunMoonPosition astro) {
    if (weather.precipitationMm > 0.1) return WildlifeScoutTheme.cyanWater;
    if (weather.cloudCoverPercent >= 75) return WildlifeScoutTheme.textMuted;
    if (weather.cloudCoverPercent >= 25) {
      return astro.currentPeriod == ActivityPeriod.night
          ? const Color(0xFFC7D2FE)
          : const Color(0xFFBAE6FD);
    }
    if (astro.currentPeriod == ActivityPeriod.night) {
      return const Color(0xFFC7D2FE);
    }
    return WildlifeScoutTheme.amberGold;
  }

  Widget _buildWeatherTelemetryPill(
    WeatherFrame weather,
    SunMoonPosition astro, {
    bool isMobile = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.lightImpact();
          onOpenWindCompass();
        },
        child: Container(
          constraints: BoxConstraints(minHeight: isMobile ? 36 : 38),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 7 : 9,
            vertical: isMobile ? 5.5 : 6.5,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WildlifeScoutTheme.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getWeatherIcon(weather, astro),
                size: isMobile ? 14 : 16,
                color: _getWeatherIconColor(weather, astro),
              ),
              const SizedBox(width: 4),
              Text(
                '${weather.temperatureCelsius.toStringAsFixed(0)}°C',
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.w800,
                  color: WildlifeScoutTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 1,
                height: isMobile ? 11 : 14,
                color: WildlifeScoutTheme.borderSubtle,
              ),
              const SizedBox(width: 6),
              Transform.rotate(
                angle: weather.scentBlowDirectionDegrees * (math.pi / 180.0),
                child: Icon(
                  Icons.navigation_rounded,
                  size: isMobile ? 11 : 13,
                  color: WildlifeScoutTheme.emeraldBio,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                weather.windCardinalLabel,
                style: TextStyle(
                  fontSize: isMobile ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SliderThemeData _buildTimeSliderTheme(
    BuildContext context, {
    required double? nowFraction,
    required DateTime referenceDate,
    bool isMobile = true,
  }) {
    return SliderTheme.of(context).copyWith(
      trackHeight: isMobile ? 14.0 : 16.0,
      thumbColor: WildlifeScoutTheme.amberGold,
      overlayColor: WildlifeScoutTheme.amberGold.withValues(alpha: 0.18),
      thumbShape: RoundSliderThumbShape(
        enabledThumbRadius: isMobile ? 11.0 : 12.0,
        elevation: 3.0,
        pressedElevation: 6.0,
      ),
      overlayShape: RoundSliderOverlayShape(overlayRadius: isMobile ? 20.0 : 22.0),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1.2),
      activeTickMarkColor: Colors.white.withValues(alpha: 0.40),
      inactiveTickMarkColor: Colors.white.withValues(alpha: 0.30),
      trackShape: FieldSliderTrackShape(
        nowFraction: nowFraction,
        referenceDate: referenceDate,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  Widget _buildBriefingCard({
    required FieldAssessment assessment,
    required WeatherFrame weather,
    required Color scoreColor,
    required bool isMobile,
  }) {
    final hasCollision = assessment.hasScentCollision;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: hasCollision
            ? WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasCollision
              ? WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.55)
              : WildlifeScoutTheme.borderSubtle,
          width: hasCollision ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              onTap: () {
                HapticFeedback.lightImpact();
                onToggleExpanded();
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 10 : 14,
                  isMobile ? 8 : 10,
                  isMobile ? 8 : 12,
                  isMobile ? 7 : 9,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 7 : 9,
                        vertical: isMobile ? 2.5 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
                        border: Border.all(
                          color: scoreColor.withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: isMobile ? 6 : 7,
                            height: isMobile ? 6 : 7,
                            decoration: BoxDecoration(
                              color: scoreColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: isMobile ? 4.5 : 6),
                          Text(
                            '${assessment.activityScorePercent}%',
                            style: TextStyle(
                              fontSize: isMobile ? 13 : 14,
                              fontWeight: FontWeight.w900,
                              color: scoreColor,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
                    Expanded(
                      child: Text(
                        assessment.ratingLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 13.5 : 14.5,
                          fontWeight: FontWeight.w700,
                          color: WildlifeScoutTheme.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: BoxConstraints(minHeight: isMobile ? 28 : 36),
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 8 : 12,
                        vertical: isMobile ? 4 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
                        border: Border.all(
                          color: WildlifeScoutTheme.borderSubtle,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isDeckExpanded
                                ? 'Weniger'
                                : (isMobile ? 'Details' : 'Wetter & Details'),
                            style: TextStyle(
                              fontSize: isMobile ? 12 : 13,
                              fontWeight: FontWeight.w600,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: isDeckExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 250),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: isMobile ? 16 : 18,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(14)),
              onTap: () {
                HapticFeedback.lightImpact();
                onOpenWindCompass();
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 10 : 14,
                  isMobile ? 7 : 9,
                  isMobile ? 8 : 12,
                  isMobile ? 8 : 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      hasCollision
                          ? Icons.warning_amber_rounded
                          : (weather.windSpeedKmh < 4.0
                              ? Icons.air_rounded
                              : Icons.check_circle_outline_rounded),
                      size: isMobile ? 16 : 18,
                      color: hasCollision
                          ? WildlifeScoutTheme.crimsonScent
                          : WildlifeScoutTheme.emeraldBio,
                    ),
                    SizedBox(width: isMobile ? 7 : 10),
                    Expanded(
                      child: Text(
                        assessment.windAdvice,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 12.5 : 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: hasCollision
                              ? const Color(0xFFFFB4C0)
                              : WildlifeScoutTheme.textPrimary
                                  .withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: BoxConstraints(minHeight: isMobile ? 26 : 36),
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 7 : 12,
                        vertical: isMobile ? 3 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: hasCollision
                            ? WildlifeScoutTheme.crimsonScent
                                .withValues(alpha: 0.18)
                            : WildlifeScoutTheme.emeraldBio
                                .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(isMobile ? 6 : 10),
                        border: Border.all(
                          color: hasCollision
                              ? WildlifeScoutTheme.crimsonScent
                                  .withValues(alpha: 0.4)
                              : WildlifeScoutTheme.emeraldBio
                                  .withValues(alpha: 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.explore_rounded,
                            size: isMobile ? 13 : 16,
                            color: hasCollision
                                ? WildlifeScoutTheme.crimsonScent
                                : WildlifeScoutTheme.emeraldBio,
                          ),
                          SizedBox(width: isMobile ? 4 : 6),
                          Text(
                            'Kompass',
                            style: TextStyle(
                              fontSize: isMobile ? 11.5 : 12.5,
                              fontWeight: FontWeight.w700,
                              color: hasCollision
                                  ? const Color(0xFFFFB4C0)
                                  : WildlifeScoutTheme.emeraldBio,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final dayLabel = dayLabelForOffset(selectedDayOffset);
    final hourStr =
        '${selectedHourOfDay.toString().padLeft(2, '0')}:00 Uhr';
    final now = DateTime.now();
    final nowFraction = selectedDayOffset == 0 ? now.hour.toDouble() : null;

    final scoreColor =
        colorForActivityScore(assessment.activityScorePercent);

    final baroInfo = _getBarometerTelemetry(weather);
    final astroInfo = _getAstroTelemetry(astro, weather);
    final skyInfo = _getSkyTelemetry(weather, astro);
    final windInfo = _getWindTelemetry(weather);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 12 : 18,
            isMobile ? 10 : 12,
            isMobile ? 12 : 18,
            isMobile ? 12 : 14,
          ),
          decoration: WildlifeScoutTheme.glassDecoration(
            borderRadius: 24,
            borderColor: assessment.hasScentCollision
                ? WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.85)
                : WildlifeScoutTheme.borderSubtle,
            borderWidth: assessment.hasScentCollision ? 1.8 : 1.0,
            shadows: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onToggleExpanded();
                },
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),

              if (isSessionActive && severeWeatherAlert != null) ...[
                DeckSevereWeatherCard(
                  alert: severeWeatherAlert!,
                  onEndSession: onEndSevereWeatherSession,
                ),
                SizedBox(height: isMobile ? 8 : 10),
              ],

              _buildBriefingCard(
                assessment: assessment,
                weather: weather,
                scoreColor: scoreColor,
                isMobile: isMobile,
              ),

              SizedBox(height: isMobile ? 8 : 12),

              if (isMobile) ...[
                // Zeile 1: Schnellauswahl-Tasten & Wetter-Telemetrie-Pill (Überlaufssicher verpackt)
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            QuickTimeButton(
                              icon: Icons.wb_twilight_rounded,
                              label: '06:00',
                              isSelected: selectedHourOfDay == 6,
                              isMobile: true,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onHourChanged(6);
                              },
                            ),
                            if (selectedDayOffset == 0) ...[
                              const SizedBox(width: 4),
                              QuickTimeButton(
                                icon: Icons.schedule_rounded,
                                label: 'Jetzt',
                                isSelected:
                                    selectedHourOfDay == DateTime.now().hour,
                                isMobile: true,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onHourChanged(DateTime.now().hour);
                                },
                              ),
                            ],
                            const SizedBox(width: 4),
                            QuickTimeButton(
                              icon: Icons.nightlight_round,
                              label: '18:00',
                              isSelected: selectedHourOfDay == 18,
                              isMobile: true,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onHourChanged(18);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildWeatherTelemetryPill(weather, astro, isMobile: true),
                  ],
                ),
                const SizedBox(height: 4),

                // Zeile 2: Skalen-Header & Zeitanzeige
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '00:00 Morgenfrühe',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WildlifeScoutTheme.textMuted,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '23:00 Nacht',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WildlifeScoutTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  child: SliderTheme(
                    data: _buildTimeSliderTheme(
                      context,
                      nowFraction: nowFraction,
                      referenceDate: weather.time,
                      isMobile: true,
                    ),
                    child: Slider(
                      value: selectedHourOfDay.toDouble(),
                      min: 0,
                      max: 23,
                      divisions: 23,
                      label: '$dayLabel, $hourStr',
                      onChanged: (val) {
                        final newHour = val.round();
                        if (newHour != selectedHourOfDay) {
                          HapticFeedback.selectionClick();
                          onHourChanged(newHour);
                        }
                      },
                    ),
                  ),
                ),
              ] else ...[
                // Desktop / Tablet: Ergonomisch optimiertes Layout mit Apple HIG Touch-Targets und klarer Trennung
                // Zeile 1: Schnellauswahl-Tasten + Prominenter Live-Zeit Badge + Wetter-Telemetrie Pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Schnellauswahl-Tasten für markante Zeiten
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        QuickTimeButton(
                          icon: Icons.wb_twilight_rounded,
                          label: '06:00',
                          isSelected: selectedHourOfDay == 6,
                          isMobile: false,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onHourChanged(6);
                          },
                        ),
                        const SizedBox(width: 6),
                        if (selectedDayOffset == 0) ...[
                          QuickTimeButton(
                            icon: Icons.schedule_rounded,
                            label: 'Jetzt',
                            isSelected:
                                selectedHourOfDay == DateTime.now().hour,
                            isMobile: false,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onHourChanged(DateTime.now().hour);
                            },
                          ),
                          const SizedBox(width: 6),
                        ],
                        QuickTimeButton(
                          icon: Icons.nightlight_round,
                          label: '18:00',
                          isSelected: selectedHourOfDay == 18,
                          isMobile: false,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onHourChanged(18);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),

                    // Zentrierte Live-Zeitanzeige Badge für perfekte Ablesbarkeit auf dem Tablet
                    Flexible(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.45),
                            width: 1.1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_filled_rounded,
                              size: 14,
                              color: WildlifeScoutTheme.amberGold,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '$dayLabel • $hourStr',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: WildlifeScoutTheme.amberGold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Wetter-Telemetrie Pill
                    _buildWeatherTelemetryPill(weather, astro, isMobile: false),
                  ],
                ),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '00:00 Morgenfrühe',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      Text(
                        '12:00 Mittag',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      Text(
                        '23:00 Nacht',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: SliderTheme(
                      data: _buildTimeSliderTheme(
                        context,
                        nowFraction: nowFraction,
                        referenceDate: weather.time,
                        isMobile: false,
                      ),
                      child: Slider(
                        value: selectedHourOfDay.toDouble(),
                        min: 0,
                        max: 23,
                        divisions: 23,
                        label: '$dayLabel, $hourStr',
                        onChanged: (val) {
                          final newHour = val.round();
                          if (newHour != selectedHourOfDay) {
                            HapticFeedback.selectionClick();
                            onHourChanged(newHour);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],

              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                child: isDeckExpanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: 7,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (context, dayIdx) {
                                final isSelected = dayIdx == selectedDayOffset;
                                final forecastIdx = (dayIdx * 24 + 12).clamp(
                                  0,
                                  hourlyForecast.isEmpty
                                      ? 0
                                      : hourlyForecast.length - 1,
                                );
                                final dayWeather = hourlyForecast.isNotEmpty
                                    ? hourlyForecast[forecastIdx]
                                    : null;

                                IconData? dayIcon;
                                Color? dayIconColor;
                                if (dayWeather != null) {
                                  if (dayWeather.precipitationMm > 0.1) {
                                    dayIcon = Icons.water_drop_rounded;
                                    dayIconColor = WildlifeScoutTheme.cyanWater;
                                  } else if (dayWeather.cloudCoverPercent >= 75) {
                                    dayIcon = Icons.cloud_rounded;
                                    dayIconColor = WildlifeScoutTheme.textMuted;
                                  } else if (dayWeather.cloudCoverPercent >= 25) {
                                    dayIcon = Icons.cloud_queue_rounded;
                                    dayIconColor = const Color(0xFFBAE6FD);
                                  } else {
                                    dayIcon = Icons.wb_sunny_rounded;
                                    dayIconColor = WildlifeScoutTheme.amberGold;
                                  }
                                }

                                return InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    onDayOffsetChanged(dayIdx);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? WildlifeScoutTheme.emeraldBio
                                              .withValues(alpha: 0.22)
                                          : Colors.white.withValues(alpha: 0.05),
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
                                        Text(
                                          dayLabelForOffset(dayIdx),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: isSelected
                                                ? WildlifeScoutTheme.emeraldBio
                                                : WildlifeScoutTheme.textPrimary,
                                          ),
                                        ),
                                        if (dayWeather != null &&
                                            dayIcon != null) ...[
                                          const SizedBox(width: 5),
                                          Icon(
                                            dayIcon,
                                            size: 13,
                                            color: isSelected
                                                ? WildlifeScoutTheme.emeraldBio
                                                : dayIconColor,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${dayWeather.temperatureCelsius.round()}°',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isSelected
                                                ? WildlifeScoutTheme.emeraldBio
                                                : WildlifeScoutTheme.textMuted,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),

                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: ModularTelemetryCard(
                                      category: 'Luftdruck',
                                      icon: baroInfo.$1,
                                      iconColor: baroInfo.$2,
                                      value: baroInfo.$3,
                                      detail: baroInfo.$4,
                                      detailColor: baroInfo.$2,
                                      tooltipMessage:
                                          assessment.barometerInsight,
                                      onTap: () {
                                        onShowTelemetryExplainer(
                                          title: 'Luftdruck & Wildaktivität',
                                          subtitle: '${weather.surfacePressureHpa.round()} hPa • Trend: ${weather.pressureDelta6hHpa >= 0 ? "+" : ""}${weather.pressureDelta6hHpa.toStringAsFixed(1)} hPa in 6h',
                                          icon: Icons.compress_rounded,
                                          iconColor: WildlifeScoutTheme.amberGold,
                                          points: [
                                            (
                                              heading: 'Fress-Trigger bei Druckabfall',
                                              description: 'Fällt der Luftdruck vor einer Schlechtwetterfront rasch ab (Delta < -1.5 hPa), treten Rehe und Hirsche oft 1–2 Stunden früher auf Lichtungen aus, um vor dem Regen zu äsen.',
                                              icon: Icons.trending_down_rounded,
                                            ),
                                            (
                                              heading: 'Ruhiges Verhalten im Hochdruck',
                                              description: 'Bei beständigem Hochdruck (>1015 hPa) fühlt sich das Wild sicher, bleibt länger in der Deckung und zieht meist erst in der späten Dämmerung heraus.',
                                              icon: Icons.sunny,
                                            ),
                                            (
                                              heading: 'Optik & Frühnebel-Chancen',
                                              description: 'Klare Hochdrucknächte kühlen stark aus und erzeugen idealen Bodennebel in Tälern für atmosphärische Gegenlichtaufnahmen.',
                                              icon: Icons.foggy,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ModularTelemetryCard(
                                      category: 'Licht',
                                      icon: astroInfo.$1,
                                      iconColor: astroInfo.$2,
                                      value: astroInfo.$3,
                                      detail: astroInfo.$4,
                                      tooltipMessage:
                                          assessment.lightQualityAdvice,
                                      onTap: () {
                                        onShowTelemetryExplainer(
                                          title: 'Licht & Solunar-Phase',
                                          subtitle: '${astro.sunElevationDegrees.toStringAsFixed(1)}° Sonnenhöhe • ${astro.lightPhaseLabel}',
                                          icon: astroInfo.$1,
                                          iconColor: astroInfo.$2,
                                          points: [
                                            (
                                              heading: 'Morgenrot / Abendrot',
                                              description: 'Flaches Streulicht an Wolkenunterkanten (-4° bis +5° Elevation). Perfekt für farbintensive Silhouetten und weiche Reflexe.',
                                              icon: Icons.wb_twilight_rounded,
                                            ),
                                            (
                                              heading: 'Goldene & Blaue Stunde',
                                              description: 'Klassisches warmes Streiflicht oder kühles Dämmerungslicht mit minimierten Schlagschatten für plastische Fellstrukturen.',
                                              icon: Icons.auto_awesome_rounded,
                                            ),
                                            (
                                              heading: 'Mondphase: ${astro.moonPhaseName}',
                                              description: '${(astro.moonIlluminationFraction * 100).round()}% Illumination. Nach dunklen Neumondnächten zieht Wild morgens besonders hungrig und länger im Hellen heraus.',
                                              icon: Icons.nightlight_round,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ModularTelemetryCard(
                                      category: 'Himmel',
                                      icon: skyInfo.$1,
                                      iconColor: skyInfo.$2,
                                      value: skyInfo.$3,
                                      detail: skyInfo.$4,
                                      tooltipMessage: weather.precipitationMm > 0
                                          ? '${weather.precipitationMm.toStringAsFixed(1)} mm • Tippen für ECMWF-Film'
                                          : '${weather.cloudStratificationSummary} • Tippen für ECMWF-Film',
                                      onTap: () => onOpenTacticalWindy?.call(
                                        WindyOverlayMode.clouds,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ModularTelemetryCard(
                                      category: 'Wind',
                                      icon: windInfo.$1,
                                      iconColor: windInfo.$2,
                                      value: windInfo.$3,
                                      detail: '${windInfo.$4} • Kompass 360°',
                                      detailColor: windInfo.$2,
                                      tooltipMessage:
                                          '${assessment.windAdvice} (Tippen für 360° Witterungs-Kompass)',
                                      onTap: onOpenWindCompass,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
