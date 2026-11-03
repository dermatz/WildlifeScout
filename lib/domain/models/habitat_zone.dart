import 'package:latlong2/latlong.dart';

enum HabitatZoneType {
  optimalEdge('Wald-Wiesen-Saum / Äsung'),
  coreRefuge('Ruhe-Einstand / Dickung'),
  waterSuhle('Suhle / Gewässerzone'),
  disturbanceBuffer('Störungszone (Rad-/Fußweg)');

  final String label;
  const HabitatZoneType(this.label);
}

class HabitatZone {
  final String id;
  final String osmId;
  final String osmTag;
  final String speciesId;
  final String speciesName;
  final String title;
  final String subtitle;
  final HabitatZoneType type;
  final double suitabilityScore; // 0.0 bis 100.0
  final double distanceToNearestTrailMeters;
  final double distanceToWaterMeters;
  final double distanceToForestMeters;
  final List<LatLng> polygonPoints;
  final LatLng center;
  final double? facingBearingDegrees; // Ausrichtung der Kante/Bucht ins Freie (0..360°)

  const HabitatZone({
    required this.id,
    required this.osmId,
    required this.osmTag,
    this.speciesId = 'roe_deer',
    this.speciesName = 'Rehwild',
    required this.title,
    required this.subtitle,
    required this.type,
    required this.suitabilityScore,
    required this.distanceToNearestTrailMeters,
    required this.distanceToWaterMeters,
    required this.distanceToForestMeters,
    required this.polygonPoints,
    required this.center,
    this.facingBearingDegrees,
  });

  bool get isDisturbance => type == HabitatZoneType.disturbanceBuffer;

  HabitatZone copyWith({
    String? id,
    String? osmId,
    String? osmTag,
    String? speciesId,
    String? speciesName,
    String? title,
    String? subtitle,
    HabitatZoneType? type,
    double? suitabilityScore,
    double? distanceToNearestTrailMeters,
    double? distanceToWaterMeters,
    double? distanceToForestMeters,
    List<LatLng>? polygonPoints,
    LatLng? center,
    double? facingBearingDegrees,
  }) {
    return HabitatZone(
      id: id ?? this.id,
      osmId: osmId ?? this.osmId,
      osmTag: osmTag ?? this.osmTag,
      speciesId: speciesId ?? this.speciesId,
      speciesName: speciesName ?? this.speciesName,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      type: type ?? this.type,
      suitabilityScore: suitabilityScore ?? this.suitabilityScore,
      distanceToNearestTrailMeters:
          distanceToNearestTrailMeters ?? this.distanceToNearestTrailMeters,
      distanceToWaterMeters: distanceToWaterMeters ?? this.distanceToWaterMeters,
      distanceToForestMeters:
          distanceToForestMeters ?? this.distanceToForestMeters,
      polygonPoints: polygonPoints ?? this.polygonPoints,
      center: center ?? this.center,
      facingBearingDegrees: facingBearingDegrees ?? this.facingBearingDegrees,
    );
  }
}

class DisturbanceTrail {
  final String id;
  final String osmId;
  final String name;
  final String trailType; // highway=path, cycleway, track, footway
  final double bufferRadiusMeters;
  final List<LatLng> pathPoints;

  const DisturbanceTrail({
    required this.id,
    required this.osmId,
    required this.name,
    required this.trailType,
    required this.bufferRadiusMeters,
    required this.pathPoints,
  });
}
