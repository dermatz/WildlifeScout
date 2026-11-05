import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../core/theme/wildlifescout_theme.dart';
import '../../data/services/compass_heading_service.dart';
import '../../domain/models/habitat_zone.dart';
import '../../domain/models/secret_spot.dart';
import '../../domain/models/species_profile.dart';
import '../../domain/models/weather_frame.dart';
import 'wind_compass/field_compass_painter.dart';
import 'wind_compass/target_bearing_row.dart';
import 'wind_compass/time_preset_button.dart';
import 'wind_compass/wind_compass_models.dart';

/// Modal-Sheet für den 360° Witterungs- & Wind-Kompass im Gelände.
/// Unterstützt:
/// 1. **Live-Blickrichtung (Head-Up)**: Die Kompassrose und die Nordnadel
///    drehen sich in Echtzeit anhand der tatsächlichen Haltung/Blickrichtung
///    des Smartphones im Gelände (via internem Magnetometer).
/// 2. **Genordeter Modus (North-Up)**: Klassische feste Nordausrichtung.
/// 3. Visualisierung von Wind-Einfallsrichtung, Witterungskegel und
///    sicherem Annäherungssektor (Gegenwind) relative zur Blickrichtung.
class WindScentCompassSheet extends StatefulWidget {
  final WeatherFrame weather;
  final SpeciesProfile primarySpecies;
  final LatLng hidePosition;
  final List<HabitatZone> habitatZones;
  final List<SecretSpot> savedSpots;
  final HabitatZone? selectedZone;
  final List<WeatherFrame>? hourlyForecast;
  final int selectedHourOfDay;
  final int selectedDayOffset;
  final ValueChanged<int>? onHourChanged;
  final ValueChanged<int>? onDayChanged;
  final double? initialHeading;

  const WindScentCompassSheet({
    super.key,
    required this.weather,
    required this.primarySpecies,
    required this.hidePosition,
    this.habitatZones = const [],
    this.savedSpots = const [],
    this.selectedZone,
    this.hourlyForecast,
    required this.selectedHourOfDay,
    this.selectedDayOffset = 0,
    this.onHourChanged,
    this.onDayChanged,
    this.initialHeading,
  });

  @override
  State<WindScentCompassSheet> createState() => _WindScentCompassSheetState();
}

class _WindScentCompassSheetState extends State<WindScentCompassSheet> {
  StreamSubscription<CompassHeadingData>? _headingSub;
  CompassHeadingData _headingData = const CompassHeadingData(
    heading: 0.0,
    continuousHeading: 0.0,
    hasSensor: false,
  );
  bool _useLiveHeading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialHeading != null) {
      _headingData = CompassHeadingData(
        heading: widget.initialHeading!,
        continuousHeading: widget.initialHeading!,
        hasSensor: true,
      );
    }

    _headingSub = CompassHeadingService.stream.listen((data) {
      if (!mounted) return;
      setState(() {
        // Falls kein initialer Override gesetzt war, den echten Stream nutzen
        if (widget.initialHeading == null) {
          _headingData = data;
        }
      });
    });
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bft = _calculateBeaufort(widget.weather.windSpeedKmh);
    final scentDir = widget.weather.scentBlowDirectionDegrees;
    final windDir = widget.weather.windDirectionDegrees;
    final coneAngle = widget.primarySpecies.behavior.scentConeAngleDegrees;
    final scentDist = widget.primarySpecies.behavior.scentSensitivityMeters;

    final targetBearings = _computeTargetBearings();

    final currentHeading = _headingData.heading;
    final continuousHeading = _headingData.continuousHeading;
    final hasSensor = _headingData.hasSensor;

    // Relative Wind-Anströmung zur Blickrichtung (0° = Wind von vorn)
    final effectiveHeading = _useLiveHeading ? currentHeading : 0.0;
    final relativeWind = (windDir - effectiveHeading + 360.0) % 360.0;

    return Container(
      decoration: BoxDecoration(
        color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildlifeScoutTheme.borderSubtle, width: 1.2),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 28,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Apple HIG Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Kopfzeile mit Icon, Titel & Schließen-Button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.explore_rounded,
                    color: WildlifeScoutTheme.cyanWater,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Witterungs- & Wind-Kompass',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: WildlifeScoutTheme.textPrimary,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '360° Windrose • Witterungskegel für ${widget.primarySpecies.name}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: WildlifeScoutTheme.textMuted,
                    size: 22,
                  ),
                  tooltip: 'Schließen',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 3. Modus-Wahl & Blickrichtungs-HUD (Head-Up vs. North-Up)
            _buildHeadingHUD(
              currentHeading: currentHeading,
              cardinal: _headingData.cardinalLabel,
              hasSensor: hasSensor,
            ),
            const SizedBox(height: 10),

            // 4. 360° Feld-Kompassrose (Dreht sich flüssig anhand der Blickrichtung)
            Center(
              child: SizedBox(
                width: 290,
                height: 300,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // A. Die drehende Kompassrose (dreht sich um -continuousHeading)
                    AnimatedRotation(
                      turns: _useLiveHeading
                          ? -continuousHeading / 360.0
                          : 0.0,
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      child: SizedBox(
                        width: 280,
                        height: 280,
                        child: CustomPaint(
                          painter: FieldCompassPainter(
                            windDirectionDeg: windDir,
                            windSpeedKmh: widget.weather.windSpeedKmh,
                            windCardinal: widget.weather.windCardinalLabel,
                            scentDirectionDeg: scentDir,
                            scentConeAngleDeg: coneAngle,
                            scentDistanceMeters: scentDist,
                            targetBearings: targetBearings,
                          ),
                        ),
                      ),
                    ),

                    // B. Feste Visier- / Peilmarke oben (12 Uhr = Smartphone-Blickrichtung)
                    Positioned(
                      top: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _useLiveHeading
                                  ? WildlifeScoutTheme.cyanWater
                                  : WildlifeScoutTheme.emeraldBio,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black87,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Text(
                              _useLiveHeading ? 'VISIER' : 'NORDEN',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 20,
                            color: _useLiveHeading
                                ? WildlifeScoutTheme.cyanWater
                                : WildlifeScoutTheme.emeraldBio,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 5. Relative Wind- & Witterungslage zur eigenen Blickrichtung
            _buildRelativeWindGuidance(
              relativeWind: relativeWind,
              windDir: windDir,
              scentDir: scentDir,
              bft: bft,
            ),
            const SizedBox(height: 10),

            // 6. Sektor-Legende & Status-Pills (Rot = Gefahrenbereich, Grün = Sicherer Annäherungsweg)
            _buildSectorLegend(
              windDir: windDir,
              scentDir: scentDir,
              coneAngle: coneAngle,
              scentDist: scentDist,
              bft: bft,
            ),
            const SizedBox(height: 10),

            // 7. Ansitz-Empfehlung & Annäherungs-Leitfaden
            _buildFieldApproachCard(
              windDir: windDir,
              scentDir: scentDir,
              coneAngle: coneAngle,
              bft: bft,
              targetBearings: targetBearings,
              relativeWind: relativeWind,
            ),
            const SizedBox(height: 12),

            // 8. Zeit-Scrubber (Windverlauf über den Tag testen)
            if (widget.hourlyForecast != null &&
                widget.hourlyForecast!.isNotEmpty) ...[
              _buildTimeScrubber(context),
              const SizedBox(height: 12),
            ],

            // 9. Zielpeilung zu Spots & Biotopen (falls vorhanden)
            if (targetBearings.isNotEmpty) ...[
              _buildTargetBearingsSection(targetBearings),
            ],
          ],
        ),
      ),
    );
  }

  /// Blickrichtungs-HUD & Umschalter zwischen Live-Sensor und fester Nordung.
  Widget _buildHeadingHUD({
    required double currentHeading,
    required String cardinal,
    required bool hasSensor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WildlifeScoutTheme.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Aktueller Kurs in Grad & Himmelsrichtung
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _useLiveHeading
                      ? (hasSensor
                          ? WildlifeScoutTheme.cyanWater
                          : WildlifeScoutTheme.amberGold)
                      : WildlifeScoutTheme.textMuted,
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (_useLiveHeading && hasSensor)
                      BoxShadow(
                        color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.7),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _useLiveHeading
                        ? '${currentHeading.round().toString().padLeft(3, '0')}° $cardinal'
                        : '000° N',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _useLiveHeading
                        ? (hasSensor
                            ? 'Blickrichtung im Gelände'
                            : 'Kein Sensor aktiv')
                        : 'Feste Nordung (Kartenmodus)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _useLiveHeading
                          ? WildlifeScoutTheme.cyanWater
                          : WildlifeScoutTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Umschalt-Pills (Live vs. Genordet)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _useLiveHeading = true);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _useLiveHeading
                        ? WildlifeScoutTheme.cyanWater.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _useLiveHeading
                          ? WildlifeScoutTheme.cyanWater
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.screen_rotation_rounded,
                        size: 13,
                        color: _useLiveHeading
                            ? Colors.white
                            : WildlifeScoutTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Live',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _useLiveHeading
                              ? Colors.white
                              : WildlifeScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _useLiveHeading = false);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: !_useLiveHeading
                        ? WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: !_useLiveHeading
                          ? WildlifeScoutTheme.emeraldBio
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.navigation_rounded,
                        size: 13,
                        color: !_useLiveHeading
                            ? Colors.white
                            : WildlifeScoutTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Nord',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: !_useLiveHeading
                              ? Colors.white
                              : WildlifeScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Zeigt an, wie der Wind bezogen auf die aktuelle Blickrichtung einfällt
  /// (z. B. Gegenwind von vorn, Rückenwind von hinten, Seitenwind).
  Widget _buildRelativeWindGuidance({
    required double relativeWind,
    required double windDir,
    required double scentDir,
    required int bft,
  }) {
    String label;
    String description;
    Color accentColor;
    IconData icon;

    if (relativeWind >= 315 || relativeWind <= 45) {
      label = 'GEGENWIND (VON VORN)';
      description =
          'Optimal: Der Wind weht dir ins Gesicht. Dein Eigengeruch zieht hinter dich ab. Perfekt für das Beobachten & Fotografieren in Blickrichtung!';
      accentColor = WildlifeScoutTheme.emeraldBio;
      icon = Icons.check_circle_outline;
    } else if (relativeWind >= 135 && relativeWind <= 225) {
      label = 'RÜCKENWIND (GEFAHR)';
      description =
          'Kritisch: Der Wind weht dir in den Rücken. Dein Geruch eilt dir in Blickrichtung voraus! Tiere vor dir können deinen Eigengeruch wahrnehmen und sich zurückziehen.';
      accentColor = WildlifeScoutTheme.crimsonScent;
      icon = Icons.warning_amber_rounded;
    } else if (relativeWind > 45 && relativeWind < 135) {
      label = 'SEITENWIND (VON RECHTS)';
      description =
          'Wind kommt von rechts. Dein Eigengeruch zieht nach links ab. Behalte den linken Geländesektor im Auge.';
      accentColor = WildlifeScoutTheme.amberGold;
      icon = Icons.arrow_back_rounded;
    } else {
      label = 'SEITENWIND (VON LINKS)';
      description =
          'Wind kommt von links. Dein Eigengeruch zieht nach rechts ab. Behalte den rechten Geländesektor im Auge.';
      accentColor = WildlifeScoutTheme.amberGold;
      icon = Icons.arrow_forward_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: accentColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _useLiveHeading ? label : 'WINDLAGE (KARTENMODUS)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _useLiveHeading
                      ? description
                      : 'Wind kommt aus ${widget.weather.windCardinalLabel} (${windDir.round()}°), Geruch zieht nach ${_cardinalFromDegrees(scentDir)} (${scentDir.round()}°).',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: WildlifeScoutTheme.textPrimary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Berechnet die Peilungen (Bearing, Distanz und Witterungsstatus)
  /// zu gespeicherten Spots und erkannten Habitaten.
  List<TargetBearingInfo> _computeTargetBearings() {
    final List<TargetBearingInfo> result = [];
    const distCalc = Distance();

    // 1. Ausgewählte Zone priorisieren
    if (widget.selectedZone != null) {
      final m = distCalc.as(
        LengthUnit.Meter,
        widget.hidePosition,
        widget.selectedZone!.center,
      );
      final rawBearing = distCalc.bearing(
        widget.hidePosition,
        widget.selectedZone!.center,
      );
      final bearing = (rawBearing + 360.0) % 360.0;
      final status = _evaluateScentStatus(bearing);
      result.add(
        TargetBearingInfo(
          title: widget.selectedZone!.title,
          category: 'Fokus-Biotop',
          bearingDeg: bearing,
          distanceMeters: m,
          status: status,
          isPrimary: true,
        ),
      );
    }

    // 2. Spots aus dem Tresor
    for (final spot in widget.savedSpots) {
      if (widget.selectedZone != null &&
          spot.title == widget.selectedZone!.title) {
        continue;
      }
      final m = distCalc.as(
        LengthUnit.Meter,
        widget.hidePosition,
        spot.coordinate,
      );
      if (m > 3000) continue; // Nur Spots im 3-km-Beobachtungsradius
      final rawBearing = distCalc.bearing(widget.hidePosition, spot.coordinate);
      final bearing = (rawBearing + 360.0) % 360.0;
      final status = _evaluateScentStatus(bearing);
      result.add(
        TargetBearingInfo(
          title: spot.title,
          category: 'Gespeicherter Spot',
          bearingDeg: bearing,
          distanceMeters: m,
          status: status,
          isPrimary: false,
        ),
      );
    }

    // Sortieren: Primärer Fokus zuerst, dann nach Distanz
    result.sort((a, b) {
      if (a.isPrimary) return -1;
      if (b.isPrimary) return 1;
      return a.distanceMeters.compareTo(b.distanceMeters);
    });

    return result.take(4).toList();
  }

  ScentStatus _evaluateScentStatus(double targetBearing) {
    final scentDir = widget.weather.scentBlowDirectionDegrees;
    final windDir = widget.weather.windDirectionDegrees;
    final halfCone = widget.primarySpecies.behavior.scentConeAngleDegrees / 2.0;

    final diffScent = _smallestAngleDiff(targetBearing, scentDir);
    if (diffScent <= halfCone) {
      return ScentStatus.scentContaminated;
    }

    final diffWind = _smallestAngleDiff(targetBearing, windDir);
    if (diffWind <= 45.0) {
      return ScentStatus.safeHeadwind;
    }

    return ScentStatus.crosswind;
  }

  static double _smallestAngleDiff(double a, double b) {
    final diff = (a - b).abs() % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  static int _calculateBeaufort(double kmh) {
    if (kmh < 1.0) return 0;
    if (kmh < 6.0) return 1;
    if (kmh < 12.0) return 2;
    if (kmh < 20.0) return 3;
    if (kmh < 29.0) return 4;
    if (kmh < 39.0) return 5;
    if (kmh < 50.0) return 6;
    if (kmh < 62.0) return 7;
    return 8;
  }

  Widget _buildSectorLegend({
    required double windDir,
    required double scentDir,
    required double coneAngle,
    required double scentDist,
    required int bft,
  }) {
    return Column(
      children: [
        Row(
          children: [
            // Roter Witterungskegel (Gefahrenbereich)
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 13,
                          color: WildlifeScoutTheme.crimsonScent,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'WITTERUNGSKEGEL',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: WildlifeScoutTheme.crimsonScent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${scentDir.round()}° (${_cardinalFromDegrees(scentDir)})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '±${(coneAngle / 2).round()}° • bis ${scentDist.round()} m',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFB4C0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Grüner Sicherer Annäherungssektor (Gegenwind)
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 13,
                          color: WildlifeScoutTheme.emeraldBio,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'SICHERE ANNÄHERUNG',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: WildlifeScoutTheme.emeraldBio,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${windDir.round()}° (${widget.weather.windCardinalLabel})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      'Gegenwind bläst nach hinten',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: WildlifeScoutTheme.emeraldBio,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Cyan Wind-Telemetrie Leiste
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WildlifeScoutTheme.borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.air_rounded,
                    size: 15,
                    color: WildlifeScoutTheme.cyanWater,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Wind aus ${widget.weather.windCardinalLabel} (${windDir.round()}°): ${widget.weather.windSpeedKmh.round()} km/h',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: WildlifeScoutTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              Text(
                'Böen ${widget.weather.windGustsKmh.round()} km/h • Bft $bft',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldApproachCard({
    required double windDir,
    required double scentDir,
    required double coneAngle,
    required int bft,
    required List<TargetBearingInfo> targetBearings,
    required double relativeWind,
  }) {
    final approachCardinal = widget.weather.windCardinalLabel;
    final isWindCalm = widget.weather.windSpeedKmh < 4.0;
    final hasHighGusts = widget.weather.windGustsKmh > 35.0;

    String advice;
    IconData icon;
    Color accentColor;

    if (isWindCalm) {
      icon = Icons.waves_rounded;
      accentColor = WildlifeScoutTheme.amberGold;
      advice =
          'Fast Windstille (${widget.weather.windSpeedKmh.round()} km/h): Geruch verharrt im Wald- & Vegetationsbereich. Achtung vor unberechenbarer Hang- und Kaltluftthermik am Waldrand!';
    } else if (hasHighGusts) {
      icon = Icons.air_rounded;
      accentColor = WildlifeScoutTheme.amberGold;
      advice =
          'Böiger Wind (${widget.weather.windGustsKmh.round()} km/h Böen): Starke Wirbelschleppen hinter Waldkanten. Halte mindestens ${(widget.primarySpecies.behavior.scentSensitivityMeters * 0.8).round()} m Sicherheitsabstand!';
    } else {
      icon = Icons.directions_walk_rounded;
      accentColor = WildlifeScoutTheme.emeraldBio;
      advice =
          'Konstanter Wind: Sichere Annäherung ausschließlich aus $approachCardinal (${windDir.round()}%). Niemals aus ${_cardinalFromDegrees(scentDir)} anlaufen!';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 17, color: accentColor),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Foto- & Annäherungs-Empfehlung',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  advice,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: WildlifeScoutTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeScrubber(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WildlifeScoutTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: WildlifeScoutTheme.textMuted,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'WIND-DREHUNG IM TAGESGANG',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: WildlifeScoutTheme.textMuted,
                    ),
                  ),
                ],
              ),
              Text(
                '${widget.selectedHourOfDay.toString().padLeft(2, '0')}:00 Uhr',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: WildlifeScoutTheme.emeraldBio,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TimePresetButton(
                label: '06:00 Früh',
                isSelected: widget.selectedHourOfDay == 6,
                onTap: () => widget.onHourChanged?.call(6),
              ),
              const SizedBox(width: 6),
              TimePresetButton(
                label: 'Jetzt',
                isSelected: widget.selectedHourOfDay == DateTime.now().hour &&
                    widget.selectedDayOffset == 0,
                onTap: () {
                  widget.onDayChanged?.call(0);
                  widget.onHourChanged?.call(DateTime.now().hour);
                },
              ),
              const SizedBox(width: 6),
              TimePresetButton(
                label: '18:00 Abend',
                isSelected: widget.selectedHourOfDay == 18,
                onTap: () => widget.onHourChanged?.call(18),
              ),
              const SizedBox(width: 6),
              TimePresetButton(
                label: '21:00 Dämmerung',
                isSelected: widget.selectedHourOfDay == 21,
                onTap: () => widget.onHourChanged?.call(21),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: WildlifeScoutTheme.cyanWater,
              thumbColor: WildlifeScoutTheme.cyanWater,
              overlayColor: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.2),
              trackHeight: 3.5,
            ),
            child: Slider(
              value: widget.selectedHourOfDay.toDouble(),
              min: 0,
              max: 23,
              divisions: 23,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                widget.onHourChanged?.call(val.round());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetBearingsSection(List<TargetBearingInfo> bearings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'PEILUNG ZU SPOTS & BIOTOPEN',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: WildlifeScoutTheme.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 6),
        ...bearings.map((b) => TargetBearingRow(info: b)),
      ],
    );
  }

  static String _cardinalFromDegrees(double deg) =>
      TargetBearingRow.cardinalFromDegrees(deg);
}
