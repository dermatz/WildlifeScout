import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../domain/models/habitat_zone.dart';
import '../../domain/models/species_profile.dart';
import '../../domain/models/weather_frame.dart';
import '../../domain/services/sun_moon_calculator.dart';

/// Erzeugt maßstabsgetreue geografische Polygone und Vektoren (in echten Metern!)
/// für die Feldkarte:
/// 1. Habitat-Eignungszonen (Äsungskanten, Ruhe-Einstände, Suhlen)
/// 2. Akustische & optische Störungspuffer um Rad- und Fußwege
/// 3. Mehrstufiger Witterungs-Geruchskegel (z.B. 450m für Rotwild, 250m für Rehwild)
/// 4. Fluchtdistanz-Radius um das Tarnzelt
/// 5. Sonnen-/Lichteinfalls-Vektor
class FieldOverlayBuilder {
  static const Distance _distance = Distance();

  /// Baut alle Polygon-Ebenen für Habitat-Hotspots und den Witterungskegel.
  static List<Polygon> buildMapPolygons({
    required LatLng hidePosition,
    required SpeciesProfile species,
    required WeatherFrame weather,
    required List<HabitatZone> habitatZones,
    required bool showHabitatZones,
    required bool showScentCone,
    required bool hasScentCollision,
  }) {
    final polygons = <Polygon>[];

    // 1. Habitat-Zonen (Grün = Äsungskante, Gold/Smaragd = Ruhe-Einstand, Cyan = Suhle)
    if (showHabitatZones) {
      for (final zone in habitatZones) {
        final Color baseColor;
        switch (zone.type) {
          case HabitatZoneType.optimalEdge:
            baseColor = WildlifeScoutTheme.emeraldBio;
          case HabitatZoneType.coreRefuge:
            baseColor = species.accentColor;
          case HabitatZoneType.waterSuhle:
            baseColor = WildlifeScoutTheme.cyanWater;
          case HabitatZoneType.disturbanceBuffer:
            baseColor = WildlifeScoutTheme.crimsonScent;
        }

        polygons.add(
          Polygon(
            points: zone.polygonPoints,
            color: baseColor.withValues(alpha: 0.24),
            borderColor: baseColor.withValues(alpha: 0.85),
            borderStrokeWidth: 2.0,
          ),
        );
      }
    }

    // 2. Fluchtdistanz-Kreis (in echten Metern um den Ansitz)
    if (species.behavior.flightDistanceMeters > 0) {
      final flightCircle = _buildCirclePoints(
        hidePosition,
        species.behavior.flightDistanceMeters,
      );
      polygons.add(
        Polygon(
          points: flightCircle,
          color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.05),
          borderColor: WildlifeScoutTheme.amberGold.withValues(alpha: 0.45),
          borderStrokeWidth: 1.5,
        ),
      );
    }

    // 3. Witterungs-Geruchskegel (Downwind Scent Cone in echten Metern)
    if (showScentCone && species.behavior.scentSensitivityMeters > 0) {
      final maxRange = species.behavior.scentSensitivityMeters;
      final scentDirection = weather.scentBlowDirectionDegrees;
      final coneAngle = species.behavior.scentConeAngleDegrees;

      final baseRed = hasScentCollision
          ? const Color(0xFFFF1E42)
          : WildlifeScoutTheme.crimsonScent;

      // 3 konzentrische Abstufungen für realistischen Diffusions-Verlauf
      for (final fraction in [1.0, 0.68, 0.38]) {
        final sectorPoints = _buildSectorPoints(
          origin: hidePosition,
          radiusMeters: maxRange * fraction,
          centerBearingDeg: scentDirection,
          spreadAngleDeg: coneAngle * (0.85 + (1.0 - fraction) * 0.25),
        );

        polygons.add(
          Polygon(
            points: sectorPoints,
            color: baseRed.withValues(
              alpha: fraction == 1.0
                  ? 0.16
                  : (fraction == 0.68 ? 0.22 : 0.30),
            ),
            borderColor: fraction == 1.0
                ? baseRed.withValues(alpha: 0.85)
                : Colors.transparent,
            borderStrokeWidth: fraction == 1.0 ? 2.0 : 0.0,
          ),
        );
      }
    }

    return polygons;
  }

  /// Baut alle Linien-Overlays (Störungspuffer um Rad-/Fußwege + Sonnenstrahl).
  static List<Polyline> buildMapPolylines({
    required LatLng hidePosition,
    required SpeciesProfile species,
    required WeatherFrame weather,
    required SunMoonPosition astro,
    required List<DisturbanceTrail> trails,
    required bool showDisturbanceTrails,
    List<LatLng>? huntingStands,
    bool showHuntingStands = true,
  }) {
    final lines = <Polyline>[];

    // 0. Zarte gepunktete Verbindungslinie zum nächsten Hochsitz (falls in der Nähe)
    if (showHuntingStands && huntingStands != null && huntingStands.isNotEmpty) {
      LatLng? nearestStand;
      double minStandDist = double.infinity;
      for (final stand in huntingStands) {
        final d = _distance.as(LengthUnit.Meter, hidePosition, stand);
        if (d < minStandDist) {
          minStandDist = d;
          nearestStand = stand;
        }
      }

      // Linie einblenden, wenn im Jagd-Areal (bis zu 350 m)
      if (nearestStand != null && minStandDist <= 350.0) {
        final isDangerClose = minStandDist <= 200.0;
        lines.add(
          Polyline(
            points: [hidePosition, nearestStand],
            color: isDangerClose
                ? const Color(0xFFEF4444).withValues(alpha: 0.85)
                : const Color(0xFFCBD5E1).withValues(alpha: 0.55),
            strokeWidth: isDangerClose ? 2.0 : 1.4,
            pattern: const StrokePattern.dotted(spacingFactor: 2.2),
          ),
        );
      }
    }

    // 1. Störungs-Korridore um Rad- und Fußwege
    if (showDisturbanceTrails) {
      for (final trail in trails) {
        // Äußerer akustischer/optischer Störungs-Puffer
        lines.add(
          Polyline(
            points: trail.pathPoints,
            color: WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.22),
            strokeWidth: (trail.bufferRadiusMeters / 5.5).clamp(18.0, 46.0),
          ),
        );
        // Kernlinie des Weges
        lines.add(
          Polyline(
            points: trail.pathPoints,
            color: const Color(0xFFFB7185).withValues(alpha: 0.85),
            strokeWidth: 2.5,
          ),
        );
      }
    }

    // 2. Sonnen- / Lichteinfalls-Vektor (zeigt woher das Licht auf den Ansitz fällt)
    if (astro.sunElevationDegrees > -6.0) {
      final sunOriginPoint = _distance.offset(
        hidePosition,
        240.0,
        astro.sunAzimuthDegrees % 360.0,
      );
      lines.add(
        Polyline(
          points: [sunOriginPoint, hidePosition],
          color: astro.isGoldenHour
              ? WildlifeScoutTheme.amberGold.withValues(alpha: 0.92)
              : const Color(0xFFFDE047).withValues(alpha: 0.65),
          strokeWidth: 3.0,
        ),
      );
    }

    // 3. Bei Vögeln (scent = 0): Aerodynamischer Lande-Vektor (Vögel landen gegen den Wind!)
    if (species.behavior.scentSensitivityMeters <= 0) {
      final windFromPoint = _distance.offset(
        hidePosition,
        140.0,
        weather.windDirectionDegrees % 360.0,
      );
      lines.add(
        Polyline(
          points: [hidePosition, windFromPoint],
          color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.9),
          strokeWidth: 3.0,
        ),
      );
    }

    return lines;
  }

  static List<LatLng> _buildSectorPoints({
    required LatLng origin,
    required double radiusMeters,
    required double centerBearingDeg,
    required double spreadAngleDeg,
  }) {
    final points = <LatLng>[origin];
    const int steps = 18;
    final startAngle = centerBearingDeg - (spreadAngleDeg / 2.0);
    final stepSize = spreadAngleDeg / steps;

    for (int i = 0; i <= steps; i++) {
      final bearing = (startAngle + i * stepSize + 360.0) % 360.0;
      points.add(_distance.offset(origin, radiusMeters, bearing));
    }
    points.add(origin);
    return points;
  }

  static List<LatLng> _buildCirclePoints(LatLng center, double radiusMeters) {
    const int steps = 36;
    final points = <LatLng>[];
    for (int i = 0; i < steps; i++) {
      final bearing = (i * 360.0 / steps) % 360.0;
      points.add(_distance.offset(center, radiusMeters, bearing));
    }
    return points;
  }
}

/// Rückwärtskompatibler Alias
typedef TacticalOverlayBuilder = FieldOverlayBuilder;
