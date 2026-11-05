import 'package:latlong2/latlong.dart';

/// Klassifizierung von OpenStreetMap-Wegen und Polygonen für die Habitat- und Störungsanalyse.
enum OsmKind {
  largeForest, // Zusammenhängender Hochwald (>= 2.5 ha)
  smallWoodlot, // Kleines Feldgehölz / Baumgruppe (< 2.5 ha)
  forestEdgeBay, // Ruhiger Waldrand-Saum am Hochwald
  meadow, // Wiese / Grünland
  farmland, // Ackerfläche
  scrub, // Dickung / Hecke / Verjüngung
  treeRow, // Lineare Baumreihe / Windschutzstreifen (kein Einstand für Schalenwild)
  wetland, // Suhle / Feuchtgebiet / Moor
  waterStream, // Bachlauf / Teich
  trailHigh, // Wanderpfad / Fußweg / Radweg (hohe Störung)
  trailTrack, // Forst- / Wirtschaftsweg
  roadSettlement, // Straße / Siedlungsrand
}

/// Parsed OSM Way/Polygon mit vorberechneten Bounding-Boxes, Zentroid und Fläche.
class ParsedOsmWay {
  final String osmId;
  final String primaryTag;
  final String? name;
  final OsmKind kind;
  final List<LatLng> points;
  final LatLng centroid;
  final bool isClosedPolygon;
  final double areaHectares;
  final double maxSpanMeters;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final double? facingBearingDegrees;

  const ParsedOsmWay._({
    required this.osmId,
    required this.primaryTag,
    this.name,
    required this.kind,
    required this.points,
    required this.centroid,
    required this.isClosedPolygon,
    required this.areaHectares,
    required this.maxSpanMeters,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    this.facingBearingDegrees,
  });

  factory ParsedOsmWay({
    required String osmId,
    required String primaryTag,
    String? name,
    required OsmKind kind,
    required List<LatLng> points,
    required LatLng centroid,
    required bool isClosedPolygon,
    required double areaHectares,
    required double maxSpanMeters,
    double? facingBearingDegrees,
  }) {
    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    return ParsedOsmWay._(
      osmId: osmId,
      primaryTag: primaryTag,
      name: name,
      kind: kind,
      points: points,
      centroid: centroid,
      isClosedPolygon: isClosedPolygon,
      areaHectares: areaHectares,
      maxSpanMeters: maxSpanMeters,
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      facingBearingDegrees: facingBearingDegrees,
    );
  }

  factory ParsedOsmWay.withBounds({
    required String osmId,
    required String primaryTag,
    String? name,
    required OsmKind kind,
    required List<LatLng> points,
    required LatLng centroid,
    required bool isClosedPolygon,
    required double areaHectares,
    required double maxSpanMeters,
    double? facingBearingDegrees,
  }) = ParsedOsmWay;
}
