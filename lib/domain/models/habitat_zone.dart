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
  });

  bool get isDisturbance => type == HabitatZoneType.disturbanceBuffer;
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
