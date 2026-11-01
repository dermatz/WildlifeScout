import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/privacy/coordinate_guard.dart';
import '../../data/api/soil_and_terrain_client.dart';
import '../models/habitat_zone.dart';
import '../models/soil_substrate_profile.dart';
import '../models/species_profile.dart';

class HabitatAnalysisResult {
  final List<HabitatZone> habitatZones;
  final List<DisturbanceTrail> disturbanceTrails;
  final int totalOsmElementsEvaluated;
  final String dataSourceLabel;
  final SoilSubstrateProfile? soilProfile;

  const HabitatAnalysisResult({
    required this.habitatZones,
    required this.disturbanceTrails,
    required this.totalOsmElementsEvaluated,
    required this.dataSourceLabel,
    this.soilProfile,
  });
}

enum _OsmKind {
  largeForest, // Zusammenhängender Hochwald (>= 2.5 ha)
  smallWoodlot, // Kleines Feldgehölz / Baumgruppe (< 2.5 ha)
  forestEdgeBay, // Ruhiger Waldrand-Saum am Hochwald
  meadow, // Wiese / Grünland
  farmland, // Ackerfläche
  scrub, // Dickung / Hecke / Verjüngung
  wetland, // Suhle / Feuchtgebiet / Moor
  waterStream, // Bachlauf / Teich
  trailHigh, // Wanderpfad / Fußweg / Radweg (hohe Störung)
  trailTrack, // Forst- / Wirtschaftsweg
  roadSettlement, // Straße / Siedlungsrand
}

class _ParsedOsmWay {
  final String osmId;
  final String primaryTag;
  final String? name;
  final _OsmKind kind;
  final List<LatLng> points;
  final LatLng centroid;
  final bool isClosedPolygon;
  final double areaHectares;
  final double maxSpanMeters;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  const _ParsedOsmWay._({
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
  });

  factory _ParsedOsmWay({
    required String osmId,
    required String primaryTag,
    String? name,
    required _OsmKind kind,
    required List<LatLng> points,
    required LatLng centroid,
    required bool isClosedPolygon,
    required double areaHectares,
    required double maxSpanMeters,
  }) {
    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    return _ParsedOsmWay._(
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
    );
  }

  factory _ParsedOsmWay.withBounds({
    required String osmId,
    required String primaryTag,
    String? name,
    required _OsmKind kind,
    required List<LatLng> points,
    required LatLng centroid,
    required bool isClosedPolygon,
    required double areaHectares,
    required double maxSpanMeters,
  }) = _ParsedOsmWay;
}

/// Wildbiologisch validierte 100%-Echtdaten-Geodaten-Engine.
///
/// Berechnet für jedes reale OpenStreetMap-Polygon:
/// 1. Echte Flächengröße in Hektar (Sphärische Shoelace-Formel):
///    Verhindert, dass winzige Baumreihen oder Feldgehölze (< 2.5 ha) mitten
///    im Feld als „Rotwild-Einstand“ fehlklassifiziert werden!
/// 2. Exakten Punkt-zu-Liniensegment-Abstand (Lotfußpunkt) zu ALLEN Wegen
///    (inkl. gerader Feld-/Wirtschaftswege `highway=track` mit wenigen Knoten).
/// 3. Wegedichte-Index (Umzingelungs-Prüfung im 180m-Radius):
///    Flächen, die im Karomuster von Feldwegen umzingelt sind, erhalten einen
///    realistischen Unruhe-Abzug.
/// 4. Tiefen-Einstand-Suche in großen Wäldern (> 5 ha):
///    Findet automatisch die ruhigsten Rückzugszonen im Inneren großer Wälder
///    sowie die ruhigsten Waldrand-Austrittskanten zur Wiese.
class HabitatSuitabilityEngine {
  static const Distance _distance = Distance();

  static final Map<String, List<dynamic>> _sectorOsmCache = {};
  static final Map<String, Future<List<Map<String, dynamic>>>>
  _inFlightSectorFetches = {};

  static HabitatAnalysisResult analyzeFromCachedRealOsm({
    required LatLng origin,
    required SpeciesProfile species,
    List<SpeciesProfile>? selectedSpeciesList,
  }) {
    final sectorKey = _sectorKeyFor(origin);
    final cached = _sectorOsmCache[sectorKey];

    if (cached != null && cached.isNotEmpty) {
      return evaluateRealOsmElements(
        rawElements: cached,
        origin: origin,
        species: species,
        selectedSpeciesList: selectedSpeciesList,
        sourceLabel: 'OpenStreetMap Live (${cached.length} OSM-Objekte)',
      );
    }

    return const HabitatAnalysisResult(
      habitatZones: [],
      disturbanceTrails: [],
      totalOsmElementsEvaluated: 0,
      dataSourceLabel: 'Scanne echte OpenStreetMap-Wege & Waldkanten...',
    );
  }

  static Future<HabitatAnalysisResult> fetchAndAnalyzeLiveOsm({
    required LatLng origin,
    required SpeciesProfile species,
    List<SpeciesProfile>? selectedSpeciesList,
  }) async {
    final sectorKey = _sectorKeyFor(origin);
    final soilFuture = SoilAndTerrainClient.fetchSoilSubstrateForSector(
      origin.latitude,
      origin.longitude,
    );

    if (_sectorOsmCache.containsKey(sectorKey) &&
        _sectorOsmCache[sectorKey]!.isNotEmpty) {
      final elems = _sectorOsmCache[sectorKey]!;
      final soilProfile = await soilFuture;
      final baseResult = evaluateRealOsmElements(
        rawElements: elems,
        origin: origin,
        species: species,
        selectedSpeciesList: selectedSpeciesList,
        sourceLabel: 'OpenStreetMap Live (${elems.length} OSM-Objekte)',
        soilProfile: soilProfile,
      );
      return _enrichWithLiveTerrainSlopes(baseResult, soilProfile);
    }

    // Parallele identische Sektor-Abfragen bündeln (verhindert Rate-Limiting
    // bei gleichzeitigem App-Start + GPS-Fix + Karten-Tipp)
    final Future<List<Map<String, dynamic>>> fetchFuture =
        _inFlightSectorFetches.putIfAbsent(
          sectorKey,
          () => _fetchSectorElementsFromOsm(origin),
        );

    List<Map<String, dynamic>> fetchedElements = const [];
    try {
      fetchedElements = await fetchFuture;
    } finally {
      _inFlightSectorFetches.remove(sectorKey);
    }

    final soilProfile = await soilFuture;

    if (fetchedElements.isNotEmpty) {
      _sectorOsmCache[sectorKey] = fetchedElements;
      final baseResult = evaluateRealOsmElements(
        rawElements: fetchedElements,
        origin: origin,
        species: species,
        selectedSpeciesList: selectedSpeciesList,
        sourceLabel: 'OpenStreetMap Live (${fetchedElements.length} OSM-Ways)',
        soilProfile: soilProfile,
      );
      return _enrichWithLiveTerrainSlopes(baseResult, soilProfile);
    }

    // Falls der Sektor-Download fehlschlug, prüfe ob ein Nachbar-Sektor im Cache liegt
    if (_sectorOsmCache.isNotEmpty) {
      final mergedNearby = <dynamic>[];
      for (final list in _sectorOsmCache.values) {
        mergedNearby.addAll(list);
      }
      if (mergedNearby.isNotEmpty) {
        final baseResult = evaluateRealOsmElements(
          rawElements: mergedNearby,
          origin: origin,
          species: species,
          selectedSpeciesList: selectedSpeciesList,
          sourceLabel: 'OpenStreetMap Cache (${mergedNearby.length} OSM-Ways)',
          soilProfile: soilProfile,
        );
        return _enrichWithLiveTerrainSlopes(baseResult, soilProfile);
      }
    }

    return HabitatAnalysisResult(
      habitatZones: const [],
      disturbanceTrails: const [],
      totalOsmElementsEvaluated: 0,
      dataSourceLabel: 'Keine OSM-Daten im Sektor empfangen (erneut tippen)',
      soilProfile: soilProfile,
    );
  }

  /// Fragt in einem einzigen gebündelten Höhenmodell-Batch (Copernicus DEM) die
  /// reale Hangneigung & Exposition für die gefundenen Habitat-Zonen ab und
  /// verrechnet den Hangbau-Bonus (v. a. für Dachsbauten an Hängen!).
  static Future<HabitatAnalysisResult> _enrichWithLiveTerrainSlopes(
    HabitatAnalysisResult base,
    SoilSubstrateProfile soilProfile,
  ) async {
    if (base.habitatZones.isEmpty) return base;

    final centers = base.habitatZones.map((z) => z.center).toList();
    final slopesByIdx = await SoilAndTerrainClient.fetchBatchTerrainSlopes(
      centers,
    );
    if (slopesByIdx.isEmpty) return base;

    final updatedZones = <HabitatZone>[];
    for (int i = 0; i < base.habitatZones.length; i++) {
      final z = base.habitatZones[i];
      final slopeSample = slopesByIdx[i];
      if (slopeSample == null) {
        updatedZones.add(z);
        continue;
      }

      double adjustedScore = z.suitabilityScore;
      // Spezifischer Hangbau-Bonus für den Dachs (und moderat für den Fuchs) bei Bau-Habitaten
      if ((z.speciesId == 'badger' || z.speciesId == 'red_fox') &&
          z.type == HabitatZoneType.coreRefuge) {
        final deg = slopeSample.slopeDegrees;
        if (deg >= 4.0 && deg <= 28.0) {
          // Ideale Hangneigung für horizontales Graben, Wasserabfluss & Etagenbau
          final isWarmAspect = const {'SO', 'S', 'SW', 'O'}.contains(
            slopeSample.aspectCardinal,
          );
          final slopeBoost =
              (z.speciesId == 'badger' ? 5.0 : 2.5) +
              (isWarmAspect ? 1.5 : 0.0);
          adjustedScore = (adjustedScore + slopeBoost).clamp(35.0, 95.0);
        } else if (deg < 1.5 && z.speciesId == 'badger') {
          // Komplett flaches Gelände erfordert vertikalen Grabaufwand & hat schlechtere Drainage
          adjustedScore = (adjustedScore - 2.0).clamp(35.0, 95.0);
        }
      }

      final updatedSubtitle =
          '${z.subtitle} • ${slopeSample.compactLabel}';

      updatedZones.add(
        HabitatZone(
          id: z.id,
          osmId: z.osmId,
          osmTag: z.osmTag,
          speciesId: z.speciesId,
          speciesName: z.speciesName,
          title: z.title,
          subtitle: updatedSubtitle,
          type: z.type,
          suitabilityScore: adjustedScore,
          distanceToNearestTrailMeters: z.distanceToNearestTrailMeters,
          distanceToWaterMeters: z.distanceToWaterMeters,
          distanceToForestMeters: z.distanceToForestMeters,
          polygonPoints: z.polygonPoints,
          center: z.center,
        ),
      );
    }

    updatedZones.sort(
      (a, b) => b.suitabilityScore.compareTo(a.suitabilityScore),
    );

    return HabitatAnalysisResult(
      habitatZones: updatedZones,
      disturbanceTrails: base.disturbanceTrails,
      totalOsmElementsEvaluated: base.totalOsmElementsEvaluated,
      dataSourceLabel:
          '${base.dataSourceLabel} • Boden: ${soilProfile.shortLabel}',
      soilProfile: soilProfile,
    );
  }

  static Future<List<Map<String, dynamic>>> _fetchSectorElementsFromOsm(
    LatLng origin,
  ) async {
    // Kompakter, schneller Beobachtungs-Sektor (~1,6 km Durchmesser, <50.000 Nodes selbst am Stadtrand)
    final bbox = CoordinateGuard.buildPrivacyBoundingBoxForOsm(
      origin.latitude,
      origin.longitude,
      latHalfSpan: 0.0070,
      lonHalfSpan: 0.0100,
    );

    // 1. Primärer Abruf: Offizielle OpenStreetMap API v0.6 (JSON)
    try {
      final osmApiUri = Uri.https('api.openstreetmap.org', '/api/0.6/map.json', {
        'bbox': '${bbox.west},${bbox.south},${bbox.east},${bbox.north}',
      });

      final response = await http
          .get(osmApiUri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final elements = await _decodeAndCompactAsync([response.body]);
        if (elements.isNotEmpty) {
          return elements;
        }
      }
    } catch (_) {}

    // 2. Fallback (falls dichtes Stadtgebiet >50.000 Nodes hatte):
    //    2x2 Teil-Quadranten schonend in 2 Paaren abrufen
    try {
      final midLat = double.parse(
        ((bbox.south + bbox.north) / 2.0).toStringAsFixed(4),
      );
      final midLon = double.parse(
        ((bbox.west + bbox.east) / 2.0).toStringAsFixed(4),
      );
      final quadrants = [
        (w: bbox.west, s: bbox.south, e: midLon, n: midLat),
        (w: midLon, s: bbox.south, e: bbox.east, n: midLat),
        (w: bbox.west, s: midLat, e: midLon, n: bbox.north),
        (w: midLon, s: midLat, e: bbox.east, n: bbox.north),
      ];

      final rawBodies = <String>[];
      for (int i = 0; i < quadrants.length; i += 2) {
        final batch = quadrants.sublist(i, math.min(i + 2, quadrants.length));
        final batchResults = await Future.wait(
          batch.map((q) async {
            try {
              final uri = Uri.https(
                'api.openstreetmap.org',
                '/api/0.6/map.json',
                {'bbox': '${q.w},${q.s},${q.e},${q.n}'},
              );
              final res = await http
                  .get(uri)
                  .timeout(const Duration(seconds: 8));
              if (res.statusCode == 200) return res.body;
            } catch (_) {}
            return '';
          }),
        );
        for (final b in batchResults) {
          if (b.isNotEmpty) rawBodies.add(b);
        }
      }

      if (rawBodies.isNotEmpty) {
        final compacted = await _decodeAndCompactAsync(rawBodies);
        if (compacted.isNotEmpty) {
          return compacted;
        }
      }
    } catch (_) {}

    // 3. Fallback: Noch kompakterer 900m-Kern-Radius um den Ansitz
    try {
      final microBbox = CoordinateGuard.buildPrivacyBoundingBoxForOsm(
        origin.latitude,
        origin.longitude,
        latHalfSpan: 0.0040,
        lonHalfSpan: 0.0060,
      );
      final uri = Uri.https('api.openstreetmap.org', '/api/0.6/map.json', {
        'bbox':
            '${microBbox.west},${microBbox.south},${microBbox.east},${microBbox.north}',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final elements = await _decodeAndCompactAsync([res.body]);
        if (elements.isNotEmpty) {
          return elements;
        }
      }
    } catch (_) {}

    return const [];
  }

  /// Web-sicherer Decoder: Nutzt auf nativen Plattformen (iOS/Android/macOS)
  /// ein Hintergrund-Isolate und fällt im Web (`kIsWeb`, wo `Isolate.run`
  /// eine `UnsupportedError` wirft) sauber auf asynchrone Event-Loop-Ausführung zurück.
  static Future<List<Map<String, dynamic>>> _decodeAndCompactAsync(
    List<String> rawJsonBodies,
  ) async {
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      return _decodeAndCompactOsmBodies(rawJsonBodies);
    }
    try {
      return await Isolate.run(
        () => _decodeAndCompactOsmBodies(rawJsonBodies),
      );
    } catch (_) {
      return _decodeAndCompactOsmBodies(rawJsonBodies);
    }
  }

  /// Läuft im Hintergrund-Isolate: Parst große JSON-Antworten, löst Node-Koordinaten
  /// direkt in `geometry` auf und verwirft alle irrelevanten Häuser/Nodes (reduziert
  /// 50.000+ Roh-Objekte auf ~350–600 wildbiologisch relevante Ways/Relationen).
  static List<Map<String, dynamic>> _decodeAndCompactOsmBodies(
    List<String> rawJsonBodies,
  ) {
    final nodes = <int, Map<String, double>>{};
    final waysById = <int, Map<String, dynamic>>{};
    final relations = <Map<String, dynamic>>[];
    final seenRelIds = <dynamic>{};

    for (final body in rawJsonBodies) {
      if (body.isEmpty) continue;
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) continue;
      final elements = decoded['elements'] as List<dynamic>? ?? const [];

      for (final item in elements) {
        if (item is! Map<String, dynamic>) continue;
        final type = item['type']?.toString();
        if (type == 'node') {
          final id = (item['id'] as num?)?.toInt();
          final lat = (item['lat'] as num?)?.toDouble();
          final lon = (item['lon'] as num?)?.toDouble();
          if (id != null && lat != null && lon != null) {
            nodes[id] = {'lat': lat, 'lon': lon};
          }
        } else if (type == 'way') {
          final id = (item['id'] as num?)?.toInt();
          if (id != null) {
            waysById[id] = item;
          }
        } else if (type == 'relation') {
          final id = item['id'];
          if (seenRelIds.add(id)) {
            relations.add(item);
          }
        }
      }
    }

    final relevantWayIdsFromRelations = <int>{};
    final compactedRelations = <Map<String, dynamic>>[];

    for (final rel in relations) {
      final tags = rel['tags'] as Map<String, dynamic>? ?? const {};
      final landuse = tags['landuse']?.toString();
      final natural = tags['natural']?.toString();
      final isRelevantRel =
          landuse == 'forest' ||
          natural == 'wood' ||
          landuse == 'meadow' ||
          landuse == 'grass' ||
          natural == 'grassland' ||
          natural == 'heath' ||
          natural == 'wetland' ||
          natural == 'water';
      if (!isRelevantRel) continue;

      final members = rel['members'] as List<dynamic>? ?? const [];
      for (final m in members) {
        if (m is Map<String, dynamic> && m['type']?.toString() == 'way') {
          final refId = (m['ref'] as num?)?.toInt();
          if (refId != null) {
            relevantWayIdsFromRelations.add(refId);
          }
        }
      }
      compactedRelations.add(rel);
    }

    final compactedWays = <Map<String, dynamic>>[];
    for (final entry in waysById.entries) {
      final wayId = entry.key;
      final way = entry.value;
      final tags = way['tags'] as Map<String, dynamic>? ?? const {};

      final hasRelevantTag =
          tags.containsKey('highway') ||
          tags.containsKey('landuse') ||
          tags.containsKey('natural') ||
          tags.containsKey('waterway') ||
          tags['man_made'] == 'embankment' ||
          tags['embankment'] == 'yes' ||
          tags['cutting'] == 'yes';
      if (!hasRelevantTag && !relevantWayIdsFromRelations.contains(wayId)) {
        continue;
      }

      List<dynamic>? geom = way['geometry'] as List<dynamic>?;
      if (geom == null || geom.isEmpty) {
        final nodeRefs = way['nodes'] as List<dynamic>?;
        if (nodeRefs != null) {
          final resolved = <Map<String, double>>[];
          for (final ref in nodeRefs) {
            final pt = nodes[(ref as num).toInt()];
            if (pt != null) resolved.add(pt);
          }
          geom = resolved;
        }
      }

      if (geom != null && geom.length >= 2) {
        compactedWays.add({
          'type': 'way',
          'id': wayId,
          'tags': tags,
          'geometry': geom,
        });
      }
    }

    return [...compactedWays, ...compactedRelations];
  }

  /// Wildbiologische & räumliche Bewertung aller realen OSM-Elemente.
  static HabitatAnalysisResult evaluateRealOsmElements({
    required List<dynamic> rawElements,
    required LatLng origin,
    required SpeciesProfile species,
    List<SpeciesProfile>? selectedSpeciesList,
    required String sourceLabel,
    SoilSubstrateProfile? soilProfile,
  }) {
    final nodeById = <int, LatLng>{};
    final wayPointsById = <int, List<LatLng>>{};
    final wayTagsById = <int, Map<String, dynamic>>{};

    for (final item in rawElements) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type']?.toString() == 'node') {
        final id = (item['id'] as num?)?.toInt();
        final lat = (item['lat'] as num?)?.toDouble();
        final lon = (item['lon'] as num?)?.toDouble();
        if (id != null && lat != null && lon != null) {
          nodeById[id] = LatLng(lat, lon);
        }
      }
    }

    for (final item in rawElements) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type']?.toString() != 'way') continue;

      final wayId = (item['id'] as num?)?.toInt();
      final tags = item['tags'] as Map<String, dynamic>? ?? {};
      final pts = <LatLng>[];

      final geom = item['geometry'] as List<dynamic>?;
      if (geom != null && geom.isNotEmpty) {
        for (final g in geom) {
          if (g is Map<String, dynamic> &&
              g['lat'] != null &&
              g['lon'] != null) {
            pts.add(
              LatLng(
                (g['lat'] as num).toDouble(),
                (g['lon'] as num).toDouble(),
              ),
            );
          }
        }
      } else {
        final nodeRefs = item['nodes'] as List<dynamic>?;
        if (nodeRefs != null) {
          for (final ref in nodeRefs) {
            final pt = nodeById[(ref as num).toInt()];
            if (pt != null) pts.add(pt);
          }
        }
      }

      if (pts.length >= 2 && wayId != null) {
        wayPointsById[wayId] = pts;
        wayTagsById[wayId] = tags;
      }
    }

    // Multipolygon-Relationen (große Staats-/Gemeindewälder & Wiesen) auflösen
    final relationDerivedWays = <({
      String id,
      String tag,
      String? name,
      _OsmKind kind,
      List<LatLng> points,
      double minAreaBoostHa,
    })>[];

    for (final item in rawElements) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type']?.toString() != 'relation') continue;

      final relId = item['id']?.toString() ?? 'rel';
      final tags = item['tags'] as Map<String, dynamic>? ?? {};
      final landuse = tags['landuse']?.toString();
      final natural = tags['natural']?.toString();
      final name = tags['name']?.toString();

      final isForestRel = landuse == 'forest' || natural == 'wood';
      final isMeadowRel =
          landuse == 'meadow' ||
          landuse == 'grass' ||
          natural == 'grassland' ||
          natural == 'heath';
      final isWetlandRel = natural == 'wetland' || natural == 'water';

      if (!isForestRel && !isMeadowRel && !isWetlandRel) continue;

      final members = item['members'] as List<dynamic>? ?? [];
      for (final m in members) {
        if (m is! Map<String, dynamic>) continue;
        if (m['type']?.toString() != 'way') continue;
        final refId = (m['ref'] as num?)?.toInt();
        final role = m['role']?.toString() ?? 'outer';
        if (refId == null) continue;

        List<LatLng>? pts = wayPointsById[refId];
        if (pts == null || pts.length < 3) {
          final mGeom = m['geometry'] as List<dynamic>?;
          if (mGeom != null && mGeom.isNotEmpty) {
            final extracted = <LatLng>[];
            for (final g in mGeom) {
              if (g is Map<String, dynamic> &&
                  g['lat'] != null &&
                  g['lon'] != null) {
                extracted.add(
                  LatLng(
                    (g['lat'] as num).toDouble(),
                    (g['lon'] as num).toDouble(),
                  ),
                );
              }
            }
            if (extracted.length >= 3) {
              pts = extracted;
            }
          }
        }
        if (pts == null || pts.length < 3) continue;
        final memberOwnTags = wayTagsById[refId] ?? {};

        if (isForestRel && role == 'inner') {
          if (!memberOwnTags.containsKey('building') &&
              memberOwnTags['landuse'] != 'residential') {
            relationDerivedWays.add((
              id: '${refId}_clearing',
              tag: 'Waldlichtung (inner forest ring)',
              name: name,
              kind: _OsmKind.meadow,
              points: pts,
              minAreaBoostHa: 1.5,
            ));
          }
        } else if (isForestRel) {
          // Ein `outer`-Ring einer großen Wald-Relation gehört zu einem Großwald!
          relationDerivedWays.add((
            id: '${relId}_$refId',
            tag: landuse == 'forest' ? 'landuse=forest' : 'natural=wood',
            name: name,
            kind: _OsmKind.largeForest,
            points: pts,
            minAreaBoostHa: 35.0,
          ));
        } else if (isMeadowRel) {
          relationDerivedWays.add((
            id: '${relId}_$refId',
            tag: 'landuse=meadow',
            name: name,
            kind: _OsmKind.meadow,
            points: pts,
            minAreaBoostHa: 2.0,
          ));
        } else if (isWetlandRel) {
          relationDerivedWays.add((
            id: '${relId}_$refId',
            tag: natural == 'water' ? 'natural=water' : 'natural=wetland',
            name: name,
            kind: natural == 'water' ? _OsmKind.waterStream : _OsmKind.wetland,
            points: pts,
            minAreaBoostHa: 1.0,
          ));
        }
      }
    }

    final largeForests = <_ParsedOsmWay>[];
    final smallWoodlots = <_ParsedOsmWay>[];
    final meadows = <_ParsedOsmWay>[];
    final farmlands = <_ParsedOsmWay>[];
    final scrubs = <_ParsedOsmWay>[];
    final wetlands = <_ParsedOsmWay>[];
    final waterStreams = <_ParsedOsmWay>[];
    final trailsHigh = <_ParsedOsmWay>[];
    final trailsTrack = <_ParsedOsmWay>[];
    final roadsAndSettlements = <_ParsedOsmWay>[];

    void registerCategorizedWay({
      required String idStr,
      required String primaryTag,
      required String? name,
      required _OsmKind rawKind,
      required List<LatLng> pts,
      double minAreaOverrideHa = 0.0,
    }) {
      final center = _computeCentroid(pts);
      final span = _computeMaxSpanMeters(pts);
      final isClosed =
          pts.length >= 4 &&
          _distance.as(LengthUnit.Meter, pts.first, pts.last) < 40.0;
      final computedHa = isClosed
          ? _computePolygonAreaHectares(pts)
          : (span > 350.0 ? 25.0 : 0.4);
      final effectiveHa = math.max(computedHa, minAreaOverrideHa);

      // WICHTIGE WILDBIOLOGISCHE TRENNUNG:
      // Ein Wald-Polygon unter 2.5 Hektar (und < 260m Ausdehnung) mitten in der
      // Feldflur ist KEIN Hochwald, sondern ein kleines Feldgehölz (`smallWoodlot`)!
      _OsmKind finalKind = rawKind;
      if (rawKind == _OsmKind.largeForest) {
        if (effectiveHa < 2.5 && span < 260.0) {
          finalKind = _OsmKind.smallWoodlot;
        }
      }

      final parsed = _ParsedOsmWay.withBounds(
        osmId: idStr,
        primaryTag: primaryTag,
        name: name,
        kind: finalKind,
        points: pts,
        centroid: center,
        isClosedPolygon: isClosed,
        areaHectares: effectiveHa,
        maxSpanMeters: span,
      );

      switch (finalKind) {
        case _OsmKind.largeForest:
          largeForests.add(parsed);
        case _OsmKind.smallWoodlot:
          smallWoodlots.add(parsed);
        case _OsmKind.forestEdgeBay:
        case _OsmKind.meadow:
          meadows.add(parsed);
        case _OsmKind.farmland:
          farmlands.add(parsed);
        case _OsmKind.scrub:
          scrubs.add(parsed);
        case _OsmKind.wetland:
          wetlands.add(parsed);
        case _OsmKind.waterStream:
          waterStreams.add(parsed);
        case _OsmKind.trailHigh:
          trailsHigh.add(parsed);
        case _OsmKind.trailTrack:
          trailsTrack.add(parsed);
        case _OsmKind.roadSettlement:
          roadsAndSettlements.add(parsed);
      }
    }

    for (final entry in wayPointsById.entries) {
      final idStr = entry.key.toString();
      final pts = entry.value;
      final tags = wayTagsById[entry.key] ?? {};
      final name = tags['name']?.toString();

      final highway = tags['highway']?.toString();
      final landuse = tags['landuse']?.toString();
      final natural = tags['natural']?.toString();
      final waterway = tags['waterway']?.toString();

      if (highway != null) {
        if (const {
          'path',
          'footway',
          'cycleway',
          'bridleway',
          'steps',
          'pedestrian',
        }.contains(highway)) {
          registerCategorizedWay(
            idStr: idStr,
            primaryTag: 'highway=$highway',
            name: name,
            rawKind: _OsmKind.trailHigh,
            pts: pts,
          );
        } else if (highway == 'track' || highway == 'service') {
          registerCategorizedWay(
            idStr: idStr,
            primaryTag: 'highway=$highway',
            name: name,
            rawKind: _OsmKind.trailTrack,
            pts: pts,
          );
        } else if (const {
          'residential',
          'secondary',
          'primary',
          'tertiary',
          'unclassified',
          'living_street',
        }.contains(highway)) {
          registerCategorizedWay(
            idStr: idStr,
            primaryTag: 'highway=$highway',
            name: name,
            rawKind: _OsmKind.roadSettlement,
            pts: pts,
          );
        }
      }

      if (landuse == 'forest' || natural == 'wood') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: landuse == 'forest' ? 'landuse=forest' : 'natural=wood',
          name: name,
          rawKind: _OsmKind.largeForest,
          pts: pts,
        );
      } else if (landuse == 'meadow' ||
          landuse == 'grass' ||
          natural == 'grassland' ||
          natural == 'heath') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag:
              landuse != null ? 'landuse=$landuse' : 'natural=$natural',
          name: name,
          rawKind: _OsmKind.meadow,
          pts: pts,
        );
      } else if (landuse == 'farmland' || landuse == 'orchard') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'landuse=$landuse',
          name: name,
          rawKind: _OsmKind.farmland,
          pts: pts,
        );
      } else if (natural == 'scrub' ||
          natural == 'tree_row' ||
          natural == 'earth_bank' ||
          natural == 'cliff' ||
          tags['man_made'] == 'embankment' ||
          tags['embankment'] == 'yes' ||
          tags['cutting'] == 'yes') {
        final isEmbankmentOrSlope =
            natural == 'earth_bank' ||
            natural == 'cliff' ||
            tags['man_made'] == 'embankment' ||
            tags['embankment'] == 'yes' ||
            tags['cutting'] == 'yes';
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: isEmbankmentOrSlope
              ? 'man_made=embankment'
              : 'natural=$natural',
          name: name,
          rawKind: _OsmKind.scrub,
          pts: pts,
          minAreaOverrideHa: isEmbankmentOrSlope ? 0.35 : 0.0,
        );
      } else if (natural == 'wetland') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'natural=wetland',
          name: name,
          rawKind: _OsmKind.wetland,
          pts: pts,
        );
      } else if (natural == 'water' ||
          (waterway != null &&
              const {'stream', 'river', 'ditch', 'canal', 'drain'}.contains(
                waterway,
              ))) {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag:
              natural == 'water' ? 'natural=water' : 'waterway=$waterway',
          name: name,
          rawKind: _OsmKind.waterStream,
          pts: pts,
        );
      }
    }

    for (final relWay in relationDerivedWays) {
      registerCategorizedWay(
        idStr: relWay.id,
        primaryTag: relWay.tag,
        name: relWay.name,
        rawKind: relWay.kind,
        pts: relWay.points,
        minAreaOverrideHa: relWay.minAreaBoostHa,
      );
    }

    // 1. Störungswege aufbauen (auf kreisförmigen 1.750m-Radius begrenzt & geglättet
    //    für flüssige 60-FPS-Kartendarstellung ohne tausende Stadtstraßen-Polylines)
    final pathPenaltyRadius = _penaltyRadiusForTag(
      species,
      'highway=path',
      fallback: 90.0,
    );
    final cyclePenaltyRadius = _penaltyRadiusForTag(
      species,
      'highway=cycleway',
      fallback: 120.0,
    );
    final trackPenaltyRadius = _penaltyRadiusForTag(
      species,
      'highway=track',
      fallback: 60.0,
    );

    final candidateTrailWays = <({double dist, _ParsedOsmWay way})>[];
    for (final w in [...trailsHigh, ...trailsTrack, ...roadsAndSettlements]) {
      if (w.primaryTag == 'highway=service' ||
          w.primaryTag == 'highway=living_street' ||
          w.primaryTag == 'highway=steps') {
        continue;
      }
      final distFromOrigin = _distance.as(LengthUnit.Meter, origin, w.centroid);
      if (distFromOrigin <= 2350.0) {
        candidateTrailWays.add((dist: distFromOrigin, way: w));
      }
    }
    candidateTrailWays.sort((a, b) => a.dist.compareTo(b.dist));

    final disturbanceTrails = <DisturbanceTrail>[];
    for (final entry in candidateTrailWays.take(280)) {
      final w = entry.way;
      final isCycle = w.primaryTag.contains('cycleway');
      final isRoad = w.kind == _OsmKind.roadSettlement;
      final isTrack = w.kind == _OsmKind.trailTrack;

      final double radius;
      if (isRoad) {
        radius = cyclePenaltyRadius * 1.15;
      } else if (isCycle) {
        radius = cyclePenaltyRadius;
      } else if (isTrack) {
        radius = trackPenaltyRadius;
      } else {
        radius = pathPenaltyRadius;
      }

      disturbanceTrails.add(
        DisturbanceTrail(
          id: 'trail_${w.osmId}',
          osmId: w.osmId,
          name: w.name ?? 'OSM ${_germanLabelForTag(w.primaryTag)}',
          trailType: w.primaryTag,
          bufferRadiusMeters: radius,
          pathPoints: _simplifyPolylinePoints(w.points, maxVertices: 24),
        ),
      );
    }

    final allDisturbanceWays = [
      ...trailsHigh,
      ...trailsTrack,
      ...roadsAndSettlements,
    ];
    final primaryDisturbanceWays = [
      ...trailsHigh,
      ...roadsAndSettlements,
    ];
    final allWaterWays = [...wetlands, ...waterStreams];
    final allForestsAndWoodlots = [...largeForests, ...smallWoodlots];

    // 2. Echte Waldrand-Austrittskanten UND Tiefen-Ruhezonen an Wäldern extrahieren!
    final forestEdgeAndDeepZones = <_ParsedOsmWay>[];
    int edgeIdx = 0;

    for (final forest in [
      ...largeForests,
      ...smallWoodlots.where((w) => w.areaHectares >= 0.75),
    ]) {
      if (forest.points.length < 4) continue;

      // A) Waldrand-Segmente entlang des Waldes mit räumlichem Mindestabstand (85m)
      //    abtasten, um redundante Kandidaten-Explosion bei großen Wäldern zu vermeiden!
      const int chunkSize = 4;
      final int stepSize = math.max(3, forest.points.length ~/ 32);
      LatLng? lastAddedEdgeCenter;

      for (int i = 0; i < forest.points.length - 1; i += stepSize) {
        final end = math.min(i + chunkSize, forest.points.length);
        final segment = forest.points.sublist(i, end);
        if (segment.length < 2) continue;

        final segCenter = _computeCentroid(segment);
        if (_distance.as(LengthUnit.Meter, origin, segCenter) > 2400) continue;
        if (lastAddedEdgeCenter != null &&
            _distance.as(LengthUnit.Meter, lastAddedEdgeCenter, segCenter) <
                85.0) {
          continue;
        }

        final corridor = _buildCorridorPolygonAlongLine(
          segment,
          widthMeters: 28.0,
        );
        if (corridor.length >= 4) {
          lastAddedEdgeCenter = segCenter;
          forestEdgeAndDeepZones.add(
            _ParsedOsmWay.withBounds(
              osmId: '${forest.osmId}_edge_${edgeIdx++}',
              primaryTag: 'Hochwald-Austrittskante',
              name: forest.name,
              kind: _OsmKind.forestEdgeBay,
              points: corridor,
              centroid: segCenter,
              isClosedPolygon: true,
              areaHectares: forest.areaHectares,
              maxSpanMeters: forest.maxSpanMeters,
            ),
          );
        }
      }

      // B) Falls das Wald-Polygon geschlossen ist: Suche nach ruhigen
      //    Einständen im Waldinneren (ab 2.0 ha)
      if (forest.isClosedPolygon && forest.areaHectares >= 2.0) {
        final interiorCandidates = _sampleInteriorQuietPockets(
          forest,
          origin: origin,
          highDisturbanceWays: primaryDisturbanceWays,
          allDisturbanceWays: allDisturbanceWays,
        );
        forestEdgeAndDeepZones.addAll(interiorCandidates);
      }
    }

    // 3. Alle Kandidaten bewerten (mit AABB-Bounding-Box-Vorfilter & Lazy-Distanzberechnung)
    final activeSpeciesList =
        (selectedSpeciesList != null && selectedSpeciesList.isNotEmpty)
            ? selectedSpeciesList
            : <SpeciesProfile>[species];

    final scoredZones = <({HabitatZone zone, _ParsedOsmWay rawCand})>[];
    final candidates = <_ParsedOsmWay>[
      ...forestEdgeAndDeepZones,
      ...largeForests,
      ...meadows,
      ...wetlands,
      ...scrubs,
      ...smallWoodlots,
      ...farmlands,
      ...waterStreams,
    ];

    for (final cand in candidates) {
      if (_distance.as(LengthUnit.Meter, origin, cand.centroid) > 2500) {
        continue;
      }

      // Differenzierter Punkt-zu-Segment-Abstand getrennt nach Hauptwegen, Forstwegen & Straßen
      final trailStats = _computeExactTrailMetrics(
        cand.centroid,
        cand.points,
        trailsHigh,
        trailsTrack,
        roadsAndSettlements,
      );

      final distToWater = cand.kind == _OsmKind.wetland ||
              cand.kind == _OsmKind.waterStream
          ? 0.0
          : _minSegmentDistanceToWaysMeters(
              cand.centroid,
              allWaterWays,
              maxSearchMeters: 260.0,
            );

      // Abstand zum nächsten großen Hochwald (>= 2.5 ha)
      final distToLargeForest = cand.kind == _OsmKind.largeForest ||
              (cand.kind == _OsmKind.forestEdgeBay && cand.areaHectares >= 2.5)
          ? 0.0
          : _minSegmentDistanceToWaysMeters(
              cand.centroid,
              largeForests,
              maxSearchMeters: 220.0,
            );

      // Abstand zum nächsten Wald oder Feldgehölz (wichtig für Rehwild)
      final distToAnyForest = cand.kind == _OsmKind.largeForest ||
              cand.kind == _OsmKind.smallWoodlot ||
              cand.kind == _OsmKind.forestEdgeBay
          ? 0.0
          : _minSegmentDistanceToWaysMeters(
              cand.centroid,
              allForestsAndWoodlots,
              maxSearchMeters: 220.0,
            );

      // Lazy-Berechnung für Wiesen-/Acker-Abstand (nur für Waldrand-Buchten benötigt!)
      final distToMeadow = cand.kind == _OsmKind.meadow
          ? 0.0
          : (cand.kind == _OsmKind.forestEdgeBay
                ? _minSegmentDistanceToWaysMeters(
                    cand.centroid,
                    meadows,
                    maxSearchMeters: 95.0,
                  )
                : 500.0);
      final distToFarmland = cand.kind == _OsmKind.farmland
          ? 0.0
          : (cand.kind == _OsmKind.forestEdgeBay
                ? _minSegmentDistanceToWaysMeters(
                    cand.centroid,
                    farmlands,
                    maxSearchMeters: 85.0,
                  )
                : 500.0);

      for (final sp in activeSpeciesList) {
        final evaluation = _scoreCandidateBiologically(
          candidate: cand,
          species: sp,
          distToNearestTrailMeters: trailStats.minDistanceToAnyTrail,
          distToHighTrailMeters: trailStats.minDistanceToHighTrail,
          distToTrackMeters: trailStats.minDistanceToTrack,
          distToNearestRoadMeters: trailStats.minDistanceToRoad,
          surroundingHighTrailQuadrants:
              trailStats.surroundingHighTrailQuadrants,
          distToWaterMeters: distToWater,
          distToLargeForestMeters: distToLargeForest,
          distToAnyForestMeters: distToAnyForest,
          distToMeadowMeters: distToMeadow,
          distToFarmlandMeters: distToFarmland,
          soilProfile: soilProfile,
        );

        if (evaluation == null) continue;

        final prefix = activeSpeciesList.length > 1 ? '${sp.name}: ' : '';
        scoredZones.add((
          rawCand: cand,
          zone: HabitatZone(
            id: 'zone_${sp.id}_${cand.osmId}',
            osmId: cand.osmId,
            osmTag: cand.primaryTag,
            speciesId: sp.id,
            speciesName: sp.name,
            title: '$prefix${evaluation.title}',
            subtitle: evaluation.subtitle,
            type: evaluation.zoneType,
            suitabilityScore: evaluation.score,
            distanceToNearestTrailMeters: trailStats.minDistanceToAnyTrail,
            distanceToWaterMeters: distToWater,
            distanceToForestMeters: distToAnyForest,
            polygonPoints: cand.points,
            center: cand.centroid,
          ),
        ));
      }
    }

    scoredZones.sort(
      (a, b) => b.zone.suitabilityScore.compareTo(a.zone.suitabilityScore),
    );
    final deduplicatedZones = <HabitatZone>[];
    for (final entry in scoredZones) {
      final z = entry.zone;
      final tooClose = deduplicatedZones.any(
        (existing) =>
            existing.speciesId == z.speciesId &&
            _distance.as(LengthUnit.Meter, existing.center, z.center) < 165.0,
      );
      if (tooClose) continue;

      // Polygon-Zuschnitt NUR für die wenigen finalen Gewinner-Habitate berechnen!
      final cand = entry.rawCand;
      final polygonPts = cand.points.length >= 3 && cand.isClosedPolygon
          ? _clipLargePolygonAroundEdge(
              cand.points,
              allForestsAndWoodlots,
              origin: origin,
              maxSpanMeters: 340,
            )
          : _buildCorridorPolygonAlongLine(cand.points, widthMeters: 26.0);

      if (polygonPts.length < 3) continue;

      deduplicatedZones.add(
        HabitatZone(
          id: z.id,
          osmId: z.osmId,
          osmTag: z.osmTag,
          speciesId: z.speciesId,
          speciesName: z.speciesName,
          title: z.title,
          subtitle: z.subtitle,
          type: z.type,
          suitabilityScore: z.suitabilityScore,
          distanceToNearestTrailMeters: z.distanceToNearestTrailMeters,
          distanceToWaterMeters: z.distanceToWaterMeters,
          distanceToForestMeters: z.distanceToForestMeters,
          polygonPoints: polygonPts,
          center: _computeCentroid(polygonPts),
        ),
      );
      if (deduplicatedZones.length >= 14) break;
    }

    return HabitatAnalysisResult(
      habitatZones: deduplicatedZones,
      disturbanceTrails: disturbanceTrails,
      totalOsmElementsEvaluated: rawElements.length,
      dataSourceLabel:
          '${disturbanceTrails.length} Wege • ${deduplicatedZones.length} Habitate',
      soilProfile: soilProfile,
    );
  }

  /// Wildbiologische Bewertung mit differenzierter Wege-Gewichtung:
  /// - Fokus-Art Rehwild (`roe_deer`): Als klassischer Kulturfolger mit kleinen
  ///   Streifgebieten (10–30 ha) nutzt Rehwild Waldränder, Wiesen, Hecken und
  ///   Waldeinstände AUCH dann, wenn Forst-/Feldwege (`highway=track`) oder
  ///   Spazierwege in der Nähe verlaufen. Wege führen beim Rehwild zu einer
  ///   sanften Qualitäts-Abstufung statt zum Komplett-Ausschluss!
  /// - Rotwild (`red_deer`) bleibt streng störungsempfindlich und benötigt
  ///   großen Hochwald und weiten Abstand zu Wegen.
  static ({
    double score,
    HabitatZoneType zoneType,
    String title,
    String subtitle,
  })? _scoreCandidateBiologically({
    required _ParsedOsmWay candidate,
    required SpeciesProfile species,
    required double distToNearestTrailMeters,
    required double distToHighTrailMeters,
    required double distToTrackMeters,
    required double distToNearestRoadMeters,
    required int surroundingHighTrailQuadrants,
    required double distToWaterMeters,
    required double distToLargeForestMeters,
    required double distToAnyForestMeters,
    required double distToMeadowMeters,
    required double distToFarmlandMeters,
    SoilSubstrateProfile? soilProfile,
  }) {
    final id = species.id;
    double score = 0.0;
    HabitatZoneType zoneType = HabitatZoneType.optimalEdge;
    String title = '';

    // 1. Ausschluss von unmittelbaren Asphalt-Straßenrändern (Wildunfall-Gefahr!)
    final minRoadDist =
        id == 'roe_deer' || id == 'red_fox' || id == 'badger' ? 45.0 : 80.0;
    if (id != 'kingfisher' && distToNearestRoadMeters < minRoadDist) {
      return null;
    }

    if (id == 'roe_deer') {
      // FOKUS-ART REHWILD (Capreolus capreolus):
      // - Klassischer Konzentratselektierer & Kulturfolger der Wald-Feld-Kanten!
      // - Forst- und Feldwege (`highway=track`) an Waldkanten oder Wiesen sind
      //   KEIN Ausschlussgrund, sondern typische Äsungsstreifen & Pirschwege!
      // - Selbst Wander-/Fußwege (`trailHigh`) löschen ein Rehwild-Habitat nicht
      //   pauschal aus, sondern reduzieren den Score nur moderat je nach Nähe,
      //   damit auch in wegereichen Revieren verlässlich Einstände und
      //   Austrittskanten gefunden werden.

      // Sanfter Ruhe-/Störungsfaktor für Rehwild:
      // - Hauptwege (Fuß-/Radwege): bis +9 Punkte Bonus bei Ruhe, max -6 Punkte nah am Weg
      // - Forst-/Feldwege (track): fast neutral (+2 Punkte bei Ruhe, max -1.5 Punkte direkt am Weg)
      final highTrailFactor = distToHighTrailMeters >= 35.0
          ? (distToHighTrailMeters.clamp(35.0, 220.0) - 35.0) * 0.048
          : -((35.0 - distToHighTrailMeters) / 35.0) * 6.0;
      final trackFactor = distToTrackMeters >= 20.0
          ? (distToTrackMeters.clamp(20.0, 140.0) - 20.0) * 0.018
          : -((20.0 - distToTrackMeters) / 20.0) * 1.5;
      final quietAdjust = highTrailFactor + trackFactor;

      if (candidate.kind == _OsmKind.forestEdgeBay) {
        final hasMeadowEdge = distToMeadowMeters <= 75.0;
        final hasFarmlandEdge = distToFarmlandMeters <= 65.0;
        final edgeBonus = hasMeadowEdge
            ? 8.5 - (distToMeadowMeters.clamp(0.0, 75.0) * 0.04)
            : (hasFarmlandEdge
                  ? 5.0 - (distToFarmlandMeters.clamp(0.0, 65.0) * 0.03)
                  : 1.5);
        score = 71.0 + edgeBonus + quietAdjust;
        zoneType = HabitatZoneType.optimalEdge;
        title = hasMeadowEdge
            ? 'Waldbucht & Wiesen-Äsungssaum'
            : (hasFarmlandEdge
                  ? 'Wald-Feld-Austrittskante'
                  : 'Waldrand-Saum');
      } else if (candidate.kind == _OsmKind.meadow &&
          distToAnyForestMeters <= 150.0) {
        final forestProximityBonus =
            6.5 - (distToAnyForestMeters.clamp(0.0, 150.0) * 0.035);
        score = 71.0 + forestProximityBonus + quietAdjust;
        zoneType = HabitatZoneType.optimalEdge;
        title = distToAnyForestMeters <= 65.0
            ? 'Äsungswiese am Waldrand'
            : 'Waldnahe Äsungswiese';
      } else if (candidate.kind == _OsmKind.largeForest &&
          candidate.areaHectares >= 1.5) {
        final areaBonus = (candidate.areaHectares.clamp(1.5, 25.0) - 1.5) * 0.12;
        score = 69.0 + areaBonus + quietAdjust;
        zoneType = HabitatZoneType.coreRefuge;
        title = 'Waldeinstand (${candidate.areaHectares.round()} ha)';
      } else if ((candidate.kind == _OsmKind.scrub ||
              candidate.kind == _OsmKind.smallWoodlot) &&
          candidate.areaHectares >= 0.18) {
        final forestBonus = distToAnyForestMeters <= 120.0 ? 3.5 : 1.0;
        score = 67.5 + forestBonus + quietAdjust;
        zoneType = HabitatZoneType.coreRefuge;
        title = candidate.kind == _OsmKind.scrub
            ? 'Dickung / Hecken-Einstand (${candidate.areaHectares.toStringAsFixed(1)} ha)'
            : 'Feldgehölz-Einstand (${candidate.areaHectares.toStringAsFixed(1)} ha)';
      } else if (candidate.kind == _OsmKind.farmland &&
          distToAnyForestMeters <= 55.0) {
        score = 66.5 + quietAdjust;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Wald-Feld-Äsungskante';
      } else {
        return null;
      }
    } else if (id == 'red_deer') {
      // ROTWILD:
      // - NIEMALS in kleinen Feldgehölzen (`smallWoodlot` < 2.5 ha) oder Hecken mitten im Feld!
      // - Braucht großen, zusammenhängenden Hochwald (`largeForest`) oder ruhige
      //   Wiesen/Waldkanten UNMITTELBAR an einem großen Hochwald (distToLargeForest <= 55m).
      if (candidate.kind == _OsmKind.smallWoodlot ||
          candidate.kind == _OsmKind.scrub ||
          candidate.kind == _OsmKind.farmland) {
        return null;
      }
      if (distToHighTrailMeters < 55.0 || distToNearestTrailMeters < 35.0) {
        return null;
      }
      if (surroundingHighTrailQuadrants >= 3) {
        return null;
      }

      if (candidate.kind == _OsmKind.largeForest) {
        if (candidate.areaHectares < 12.0) return null;
        score =
            62.0 +
            (distToNearestTrailMeters.clamp(35.0, 380.0) - 35.0) * 0.08;
        zoneType = HabitatZoneType.coreRefuge;
        title = 'Hochwald-Ruhezone (${candidate.areaHectares.round()} ha)';
      } else if (candidate.kind == _OsmKind.forestEdgeBay) {
        if (candidate.areaHectares < 10.0) return null;
        score =
            60.0 +
            (distToNearestTrailMeters.clamp(35.0, 350.0) - 35.0) * 0.075;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Hochwald-Austrittskante';
      } else if (candidate.kind == _OsmKind.meadow &&
          distToLargeForestMeters <= 55.0) {
        score =
            61.0 +
            (distToNearestTrailMeters.clamp(35.0, 350.0) - 35.0) * 0.075;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Waldwiese am Hochwald';
      } else if (candidate.kind == _OsmKind.wetland &&
          distToLargeForestMeters <= 120.0) {
        score =
            66.0 +
            (distToNearestTrailMeters.clamp(35.0, 300.0) - 35.0) * 0.07;
        zoneType = HabitatZoneType.waterSuhle;
        title = 'Waldnahe Suhle / Feuchtgebiet';
      } else {
        return null;
      }
    } else if (id == 'wild_boar') {
      // SCHWARZWILD:
      if (distToHighTrailMeters < 28.0) return null;
      if (surroundingHighTrailQuadrants >= 3) return null;

      if (candidate.kind == _OsmKind.wetland &&
          distToAnyForestMeters <= 180.0) {
        score =
            75.0 +
            (distToNearestTrailMeters.clamp(25.0, 250.0) - 25.0) * 0.07;
        zoneType = HabitatZoneType.waterSuhle;
        title = 'Suhle / Feuchtsenke';
      } else if (candidate.kind == _OsmKind.largeForest) {
        score =
            68.0 +
            (distToNearestTrailMeters.clamp(25.0, 280.0) - 25.0) * 0.07;
        zoneType = HabitatZoneType.coreRefuge;
        title = 'Waldeinstand / Tageskessel';
      } else if (candidate.kind == _OsmKind.forestEdgeBay) {
        score =
            70.0 +
            (distToNearestTrailMeters.clamp(25.0, 240.0) - 25.0) * 0.07;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Waldkante / Gebrächzone';
      } else if (candidate.kind == _OsmKind.scrub &&
          candidate.areaHectares >= 0.4 &&
          distToAnyForestMeters <= 150.0) {
        score = 71.0;
        zoneType = HabitatZoneType.coreRefuge;
        title = 'Schwarzdorn-/Brombeerdickung';
      } else {
        return null;
      }
    } else if (id == 'red_fox') {
      // ROTFUCHS:
      if (distToHighTrailMeters < 15.0) return null;

      if (candidate.kind == _OsmKind.meadow) {
        score =
            74.0 +
            (distToNearestTrailMeters.clamp(15.0, 180.0) - 15.0) * 0.08;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Mäusewiese';
      } else if ((candidate.kind == _OsmKind.scrub ||
              candidate.kind == _OsmKind.smallWoodlot) &&
          candidate.areaHectares >= 0.25) {
        score =
            70.0 +
            (distToNearestTrailMeters.clamp(15.0, 160.0) - 15.0) * 0.07;
        zoneType = HabitatZoneType.coreRefuge;
        title = 'Heckenriegel / Feldgehölz';
      } else if (candidate.kind == _OsmKind.forestEdgeBay) {
        score =
            72.0 +
            (distToNearestTrailMeters.clamp(15.0, 180.0) - 15.0) * 0.07;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Waldrand-Schnürwechsel';
      } else {
        return null;
      }
    } else if (id == 'badger') {
      // DACHS (Meles meles):
      // 1. Waldboden- & Bau-Kriterien:
      //    - Braucht zwingend TROCKENE, gut drainierte, grabfähige Böden (lehmiger Sand,
      //      Löss, tiefer Waldmull) ohne Staunässe -> Feuchtgebiete/Moore (`wetland`)
      //      und Gewässerläufe sind als Dachsbau komplett ausgeschlossen!
      //    - Bevorzugt Hanglagen, Böschungen (`man_made=embankment`), Hohlwege und
      //      wurzelreiche Waldkanten (20–50m im Bestand unter Buchen/Eichen), deren
      //      Wurzelwerk die Kesseldecke stützt.
      // 2. Nahrungs-Kriterien:
      //    - Hauptnahrung sind Regenwürmer (Lumbricus terrestris) & Fallobst ->
      //      unmittelbare Nähe zu Wiesen (`meadow`) und Streuobstwiesen (`landuse=orchard`).
      // 3. Störungs- & Trittschall-Empfindlichkeit:
      //    - Empfindlich gegen Trittschall/Hunde auf Fußpfaden (`trailHigh` >= 20m),
      //      nutzt aber ruhige Forstwege (`highway=track`) nachts gerne als Schnürpfade.
      if (candidate.kind == _OsmKind.wetland ||
          candidate.kind == _OsmKind.waterStream) {
        return null;
      }
      if (distToHighTrailMeters < 20.0) return null;

      final quietBonus =
          (distToHighTrailMeters.clamp(20.0, 220.0) - 20.0) * 0.055;
      // Trockener Boden ohne unmittelbare Staunässe (> 25m zu Sumpf/Wasser) wird für Baue bevorzugt
      final drySoilBonus = distToWaterMeters >= 25.0 ? 3.0 : -3.5;

      if (candidate.kind == _OsmKind.forestEdgeBay) {
        final hasMeadowEdge = distToMeadowMeters <= 80.0;
        final hasFarmlandEdge = distToFarmlandMeters <= 70.0;
        final foragingEdgeBonus = hasMeadowEdge
            ? 6.5 - (distToMeadowMeters.clamp(0.0, 80.0) * 0.04)
            : (hasFarmlandEdge ? 3.5 : 1.0);
        score = 71.5 + foragingEdgeBonus + quietBonus + drySoilBonus;
        zoneType = HabitatZoneType.coreRefuge;
        title = hasMeadowEdge
            ? 'Dachsbau-Waldkante & Regenwurmsaum'
            : 'Dachsbau-Hanglage / Waldrand';
      } else if (candidate.kind == _OsmKind.largeForest &&
          candidate.areaHectares >= 1.5) {
        score = 70.0 + quietBonus + drySoilBonus;
        zoneType = HabitatZoneType.coreRefuge;
        title =
            'Altholz-Dachsburg & Wurzelboden (${candidate.areaHectares.round()} ha)';
      } else if ((candidate.kind == _OsmKind.scrub ||
              candidate.kind == _OsmKind.smallWoodlot) &&
          candidate.areaHectares >= 0.20) {
        final isEmbankment = candidate.primaryTag.contains('embankment');
        final slopeBonus = isEmbankment ? 5.5 : 1.5;
        score = 69.5 + slopeBonus + quietBonus + drySoilBonus;
        zoneType = HabitatZoneType.coreRefuge;
        title = isEmbankment
            ? 'Böschung / Hohlweg-Dachsbau'
            : 'Wurzel-Heckenriegel / Nebenbau';
      } else if (candidate.kind == _OsmKind.meadow &&
          distToAnyForestMeters <= 125.0) {
        final forestProx =
            5.0 - (distToAnyForestMeters.clamp(0.0, 125.0) * 0.03);
        score = 71.0 + forestProx + quietBonus;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Regenwurm-Wiese am Waldrand';
      } else if (candidate.kind == _OsmKind.farmland &&
          (candidate.primaryTag == 'landuse=orchard' ||
              distToAnyForestMeters <= 60.0)) {
        final isOrchard = candidate.primaryTag == 'landuse=orchard';
        score = (isOrchard ? 72.5 : 67.5) + quietBonus;
        zoneType = HabitatZoneType.optimalEdge;
        title = isOrchard
            ? 'Streuobstwiese / Fallobst-Äsung'
            : 'Wald-Feld-Kante / Dachswechsel';
      } else {
        return null;
      }
    } else {
      // EISVOGEL:
      if (candidate.kind == _OsmKind.waterStream) {
        score =
            78.0 +
            (distToNearestTrailMeters.clamp(15.0, 150.0) - 15.0) * 0.10;
        zoneType = HabitatZoneType.waterSuhle;
        title = candidate.name != null
            ? 'Gewässer: ${candidate.name}'
            : 'Bachlauf / Teich';
      } else if (candidate.kind == _OsmKind.wetland) {
        score =
            70.0 +
            (distToNearestTrailMeters.clamp(15.0, 150.0) - 15.0) * 0.08;
        zoneType = HabitatZoneType.waterSuhle;
        title = 'Feuchtufer';
      } else {
        return null;
      }
    }

    // 2. Moderater Wassernähe-Bonus (maximal +4 Punkte)
    final waterRule = species.habitatRules.waterProximity;
    if (waterRule != null && distToWaterMeters <= waterRule.maxDistanceMeters) {
      score += math.min(4.0, waterRule.scoreBoost);
    }

    // 3. Moderater Abzug nur bei echter mehrseitiger Einkesselung durch Hauptwege
    //    (beim Rehwild deutlich sanfter gewichtet als bei Rotwild!)
    if (surroundingHighTrailQuadrants >= 2) {
      final perQuadrantPenalty = id == 'roe_deer' ? 2.5 : 6.0;
      score -= (surroundingHighTrailQuadrants - 1) * perQuadrantPenalty;
    }

    // 4. Geologischer Bodenuntergrund-Einfluss (BGR BÜK200 / ISRIC SoilGrids):
    //    Prüft, ob das Erdreich für Dachs-/Fuchsbauten trocken & grabfähig ist
    //    (oder bei Staunässe/Fels ungeeignet für Erdhöhlen).
    if (soilProfile != null) {
      score += soilProfile.scoreAdjustmentForSpecies(
        id,
        isBurrowRefuge: zoneType == HabitatZoneType.coreRefuge,
      );
    }

    final clampedScore = score.clamp(35.0, 93.0);
    if (clampedScore < 58.0) return null;

    final trailInfo = '${distToNearestTrailMeters.round()}m zum nächsten Weg';
    final densityInfo = surroundingHighTrailQuadrants <= 1
        ? 'Ruhige Lage'
        : 'Wege in $surroundingHighTrailQuadrants Richtungen';
    final waterInfo = distToWaterMeters < 15
        ? 'Am Wasser'
        : 'Wasser ${distToWaterMeters.round()}m';
    final soilInfo =
        soilProfile != null && soilProfile.diggability != SoilDiggability.unknown
            ? ' • Boden: ${soilProfile.shortLabel}'
            : '';

    return (
      score: clampedScore,
      zoneType: zoneType,
      title: title,
      subtitle: '$trailInfo ($densityInfo) • $waterInfo$soilInfo',
    );
  }

  /// Findet im Inneren eines geschlossenen Waldes (>= 2.0 ha) die besten
  /// Einstände (die Punkte mit dem relativ größten Abstand zu Wegen, auch
  /// wenn ein Forst- oder Wanderweg durch den Wald verläuft).
  static List<_ParsedOsmWay> _sampleInteriorQuietPockets(
    _ParsedOsmWay forest, {
    required LatLng origin,
    required List<_ParsedOsmWay> highDisturbanceWays,
    required List<_ParsedOsmWay> allDisturbanceWays,
  }) {
    final minLat = forest.minLat;
    final maxLat = forest.maxLat;
    final minLon = forest.minLon;
    final maxLon = forest.maxLon;

    final pockets = <({LatLng pt, double effectiveDist})>[];
    const int gridSteps = 5;
    for (int r = 1; r < gridSteps; r++) {
      for (int c = 1; c < gridSteps; c++) {
        final lat = minLat + (maxLat - minLat) * (r / gridSteps);
        final lon = minLon + (maxLon - minLon) * (c / gridSteps);
        final candidatePt = LatLng(lat, lon);

        if (_distance.as(LengthUnit.Meter, origin, candidatePt) > 1950) {
          continue;
        }
        if (!_isPointInPolygon(candidatePt, forest.points)) continue;

        final dHigh = _minSegmentDistanceToWaysMeters(
          candidatePt,
          highDisturbanceWays,
          maxSearchMeters: 300.0,
        );
        final dAny = _minSegmentDistanceToWaysMeters(
          candidatePt,
          allDisturbanceWays,
          maxSearchMeters: 250.0,
        );
        if (dHigh >= 18.0) {
          pockets.add((pt: candidatePt, effectiveDist: dHigh * 0.7 + dAny * 0.3));
        }
      }
    }

    pockets.sort((a, b) => b.effectiveDist.compareTo(a.effectiveDist));
    final result = <_ParsedOsmWay>[];
    int idx = 0;
    for (final p in pockets) {
      final tooClose = result.any(
        (existing) =>
            _distance.as(LengthUnit.Meter, existing.centroid, p.pt) < 140.0,
      );
      if (tooClose) continue;

      final circlePoly = _buildCirclePolygon(p.pt, radiusMeters: 48.0);
      result.add(
        _ParsedOsmWay.withBounds(
          osmId: '${forest.osmId}_quiet_${idx++}',
          primaryTag: 'Tiefen-Einstand (${forest.primaryTag})',
          name: forest.name,
          kind: _OsmKind.largeForest,
          points: circlePoly,
          centroid: p.pt,
          isClosedPolygon: true,
          areaHectares: forest.areaHectares,
          maxSpanMeters: forest.maxSpanMeters,
        ),
      );
      if (result.length >= 2) break;
    }
    return result;
  }

  /// AABB-beschleunigte Punkt-zu-Liniensegment-Distanz (in Metern) für:
  /// - Haupt-Störungswege (`trailsHigh`: Fuß-, Wander-, Radwege)
  /// - Einfache Forst-/Feldwege (`trailsTrack`: `highway=track`, `highway=service`)
  /// - Straßen (`roadsOnly`)
  /// Überspringt >97% aller entfernten Wege in O(1) per Bounding-Box-Prüfung!
  static ({
    double minDistanceToAnyTrail,
    double minDistanceToHighTrail,
    double minDistanceToTrack,
    double minDistanceToRoad,
    int surroundingHighTrailQuadrants,
  }) _computeExactTrailMetrics(
    LatLng centroid,
    List<LatLng> polygonPoints,
    List<_ParsedOsmWay> trailsHigh,
    List<_ParsedOsmWay> trailsTrack,
    List<_ParsedOsmWay> roadsOnly,
  ) {
    double minHighCenter = 450.0;
    double minHighBoundary = 450.0;
    double minTrackCenter = 400.0;
    double minRoad = 500.0;

    final step = math.max(1, polygonPoints.length ~/ 4);
    final occupiedQuadrants = <int>{};

    // 1. Haupt-Störungswege (Fuß-, Wander-, Radwege) mit AABB-Vorfilter
    for (final w in trailsHigh) {
      final searchLimit = math.max(minHighCenter, 120.0);
      final latPad = searchLimit * 0.0000092;
      final lonPad = searchLimit * 0.0000150;
      if (centroid.latitude < w.minLat - latPad ||
          centroid.latitude > w.maxLat + latPad ||
          centroid.longitude < w.minLon - lonPad ||
          centroid.longitude > w.maxLon + lonPad) {
        continue;
      }

      final dCenter = _distancePointToPolylineMeters(centroid, w.points);
      if (dCenter < minHighCenter) minHighCenter = dCenter;

      if (dCenter < 180.0) {
        double dPoly = dCenter;
        for (int i = 0; i < polygonPoints.length; i += step) {
          final dp = _distancePointToPolylineMeters(polygonPoints[i], w.points);
          if (dp < dPoly) dPoly = dp;
        }
        if (dPoly < minHighBoundary) minHighBoundary = dPoly;
      } else if (dCenter < minHighBoundary) {
        minHighBoundary = dCenter;
      }

      if (dCenter <= 115.0) {
        final bearing = _distance.bearing(centroid, w.centroid);
        final quadrant = (((bearing + 360.0) % 360.0) / 90.0).floor() % 4;
        occupiedQuadrants.add(quadrant);
      }
    }

    // 2. Straßen in einem einzigen Durchgang (für minRoad UND minHighCenter)
    for (final r in roadsOnly) {
      final searchLimit = math.max(minRoad, minHighCenter);
      final latPad = searchLimit * 0.0000092;
      final lonPad = searchLimit * 0.0000150;
      if (centroid.latitude < r.minLat - latPad ||
          centroid.latitude > r.maxLat + latPad ||
          centroid.longitude < r.minLon - lonPad ||
          centroid.longitude > r.maxLon + lonPad) {
        continue;
      }

      final d = _distancePointToPolylineMeters(centroid, r.points);
      if (d < minRoad) minRoad = d;
      if (d < minHighCenter) minHighCenter = d;
      if (d < minHighBoundary) minHighBoundary = d;

      if (d <= 115.0) {
        final bearing = _distance.bearing(centroid, r.centroid);
        final quadrant = (((bearing + 360.0) % 360.0) / 90.0).floor() % 4;
        occupiedQuadrants.add(quadrant);
      }
    }

    // 3. Forst- und Feldwege mit AABB-Vorfilter
    for (final t in trailsTrack) {
      final latPad = minTrackCenter * 0.0000092;
      final lonPad = minTrackCenter * 0.0000150;
      if (centroid.latitude < t.minLat - latPad ||
          centroid.latitude > t.maxLat + latPad ||
          centroid.longitude < t.minLon - lonPad ||
          centroid.longitude > t.maxLon + lonPad) {
        continue;
      }

      final dCenter = _distancePointToPolylineMeters(centroid, t.points);
      if (dCenter < minTrackCenter) minTrackCenter = dCenter;
    }

    final effectiveHighDist = minHighCenter * 0.80 + minHighBoundary * 0.20;
    final minAnyDist = math.min(effectiveHighDist, minTrackCenter);

    return (
      minDistanceToAnyTrail: minAnyDist,
      minDistanceToHighTrail: effectiveHighDist,
      minDistanceToTrack: minTrackCenter,
      minDistanceToRoad: minRoad,
      surroundingHighTrailQuadrants: occupiedQuadrants.length,
    );
  }

  static double _minSegmentDistanceToWaysMeters(
    LatLng point,
    List<_ParsedOsmWay> ways, {
    double maxSearchMeters = 450.0,
  }) {
    if (ways.isEmpty) return 500.0;
    double minDist = maxSearchMeters;
    for (final w in ways) {
      final latPad = minDist * 0.0000092;
      final lonPad = minDist * 0.0000150;
      if (point.latitude < w.minLat - latPad ||
          point.latitude > w.maxLat + latPad ||
          point.longitude < w.minLon - lonPad ||
          point.longitude > w.maxLon + lonPad) {
        continue;
      }

      final d = _distancePointToPolylineMeters(point, w.points);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  static List<LatLng> _simplifyPolylinePoints(
    List<LatLng> pts, {
    required int maxVertices,
  }) {
    if (pts.length <= maxVertices) return pts;
    final result = <LatLng>[pts.first];
    final step = (pts.length - 1) / (maxVertices - 1);
    for (int i = 1; i < maxVertices - 1; i++) {
      result.add(pts[(i * step).round()]);
    }
    result.add(pts.last);
    return result;
  }

  /// Berechnet den exakten kürzesten Abstand (in Metern) von einem Punkt `p`
  /// zu allen Liniensegmenten `[a, b]` eines Polygons oder Weges.
  static double _distancePointToPolylineMeters(
    LatLng p,
    List<LatLng> polyline,
  ) {
    if (polyline.isEmpty) return 999.0;
    if (polyline.length == 1) {
      return _distance.as(LengthUnit.Meter, p, polyline.first);
    }

    final cosLat = math.cos(p.latitude * math.pi / 180.0);
    const double metersPerDegLat = 111320.0;
    final double metersPerDegLon = 111320.0 * cosLat;

    double minDistSq = double.infinity;

    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];

      final ax = (a.longitude - p.longitude) * metersPerDegLon;
      final ay = (a.latitude - p.latitude) * metersPerDegLat;
      final bx = (b.longitude - p.longitude) * metersPerDegLon;
      final by = (b.latitude - p.latitude) * metersPerDegLat;

      final dx = bx - ax;
      final dy = by - ay;
      final lenSq = dx * dx + dy * dy;

      double t = 0.0;
      if (lenSq > 0.0001) {
        t = (-(ax * dx + ay * dy) / lenSq).clamp(0.0, 1.0);
      }

      final projX = ax + t * dx;
      final projY = ay + t * dy;
      final distSq = projX * projX + projY * projY;
      if (distSq < minDistSq) {
        minDistSq = distSq;
      }
    }

    return math.sqrt(minDistSq);
  }

  /// Berechnet die reale Fläche eines Polygons in Hektar (1 ha = 10.000 m²).
  static double _computePolygonAreaHectares(List<LatLng> pts) {
    if (pts.length < 3) return 0.0;
    final ref = pts.first;
    final cosLat = math.cos(ref.latitude * math.pi / 180.0);
    const double mLat = 111320.0;
    final double mLon = 111320.0 * cosLat;

    double areaSqMeters = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % pts.length];
      final x1 = (p1.longitude - ref.longitude) * mLon;
      final y1 = (p1.latitude - ref.latitude) * mLat;
      final x2 = (p2.longitude - ref.longitude) * mLon;
      final y2 = (p2.latitude - ref.latitude) * mLat;
      areaSqMeters += (x1 * y2 - x2 * y1);
    }
    return (areaSqMeters.abs() * 0.5) / 10000.0;
  }

  static double _computeMaxSpanMeters(List<LatLng> pts) {
    if (pts.length < 2) return 0.0;
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    return _distance.as(
      LengthUnit.Meter,
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );
  }

  static bool _isPointInPolygon(LatLng pt, List<LatLng> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].latitude, yi = polygon[i].longitude;
      final xj = polygon[j].latitude, yj = polygon[j].longitude;
      final intersect =
          ((yi > pt.longitude) != (yj > pt.longitude)) &&
          (pt.latitude <
              (xj - xi) * (pt.longitude - yi) / (yj - yi + 1e-12) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static List<LatLng> _buildCirclePolygon(
    LatLng center, {
    required double radiusMeters,
  }) {
    const int steps = 16;
    return List.generate(
      steps,
      (i) => _distance.offset(center, radiusMeters, (i * 360.0 / steps) % 360.0),
    );
  }

  static List<LatLng> _clipLargePolygonAroundEdge(
    List<LatLng> pts,
    List<_ParsedOsmWay> forests, {
    required LatLng origin,
    required double maxSpanMeters,
  }) {
    if (pts.length <= 20 || _computeMaxSpanMeters(pts) <= maxSpanMeters * 1.15) {
      return pts;
    }

    // Geschlossenes Ring-Ende ohne doppelten Schlussknoten betrachten
    final ring =
        pts.length >= 4 &&
            _distance.as(LengthUnit.Meter, pts.first, pts.last) < 2.0
        ? pts.sublist(0, pts.length - 1)
        : pts;
    if (ring.length < 4) return pts;

    int bestIdx = 0;
    double bestMetric = double.infinity;

    final step = math.max(1, ring.length ~/ 24);
    for (int i = 0; i < ring.length; i += step) {
      final dOrigin = _distance.as(LengthUnit.Meter, origin, ring[i]);
      final dForest = _minSegmentDistanceToWaysMeters(ring[i], forests);
      final combined = dOrigin * 0.6 + dForest * 0.4;
      if (combined < bestMetric) {
        bestMetric = combined;
        bestIdx = i;
      }
    }

    final anchor = ring[bestIdx];
    // Zusammenhängendes Ring-Segment um bestIdx herum extrahieren (verhindert Sprünge über die Polygon-Naht!)
    final contiguous = <LatLng>[anchor];
    final maxSideSteps = ring.length ~/ 2;

    for (int offset = 1; offset <= maxSideSteps; offset++) {
      final nextPt = ring[(bestIdx + offset) % ring.length];
      if (_distance.as(LengthUnit.Meter, anchor, nextPt) <= maxSpanMeters) {
        contiguous.add(nextPt);
      } else {
        break;
      }
    }

    final backPts = <LatLng>[];
    for (int offset = 1; offset < maxSideSteps; offset++) {
      final prevPt = ring[(bestIdx - offset + ring.length) % ring.length];
      if (_distance.as(LengthUnit.Meter, anchor, prevPt) <= maxSpanMeters) {
        backPts.add(prevPt);
      } else {
        break;
      }
    }

    final combinedRing = [...backPts.reversed, ...contiguous];
    if (combinedRing.length < 4) {
      return _computeConvexHull(ring.take(24).toList());
    }
    return _hasPolygonSelfIntersection(combinedRing)
        ? _computeConvexHull(combinedRing)
        : combinedRing;
  }

  /// Baut einen sauberen, überschneidungsfreien Saum-Korridor entlang einer Linie.
  ///
  /// Wichtig: Am letzten Punkt muss die Vorwärtsrichtung (`pts[i - 1] -> pts[i]`)
  /// beibehalten werden (statt `pts[i] -> pts[i - 1]`), da sonst Links- und Rechts-Normale
  /// am Ende um 180° vertauscht werden und eine verkreuzte „Sanduhr“-Form entsteht!
  static List<LatLng> _buildCorridorPolygonAlongLine(
    List<LatLng> line, {
    required double widthMeters,
  }) {
    if (line.length < 2) return [];

    // 1. Zu eng beieinander liegende Zwischenpunkte (< 14 m) bereinigen,
    //    damit scharfe Mikro-Knicke beim Versetzen um `widthMeters` keine Schleifen werfen.
    final cleaned = <LatLng>[line.first];
    for (int i = 1; i < line.length && cleaned.length < 14; i++) {
      final d = _distance.as(LengthUnit.Meter, cleaned.last, line[i]);
      if (d >= 14.0 || (i == line.length - 1 && d >= 2.0)) {
        cleaned.add(line[i]);
      }
    }
    if (cleaned.length < 2) return [];

    // 2. Vorwärts-Peilung (Bearing) für jedes Liniensegment berechnen
    final segBearings = <double>[];
    for (int i = 0; i < cleaned.length - 1; i++) {
      segBearings.add(_distance.bearing(cleaned[i], cleaned[i + 1]));
    }

    final leftSide = <LatLng>[];
    final rightSide = <LatLng>[];

    for (int i = 0; i < cleaned.length; i++) {
      final double forwardBearing;
      if (i == 0) {
        forwardBearing = segBearings.first;
      } else if (i == cleaned.length - 1) {
        // Vorwärtsrichtung vom vorletzten zum letzten Punkt beibehalten!
        forwardBearing = segBearings.last;
      } else {
        // Winkelhalbierende der beiden angrenzenden Segmente für sanfte Kurven
        forwardBearing = _averageBearingDegrees(
          segBearings[i - 1],
          segBearings[i],
        );
      }

      final normalLeft = (forwardBearing - 90.0 + 360.0) % 360.0;
      final normalRight = (forwardBearing + 90.0 + 360.0) % 360.0;

      leftSide.add(_distance.offset(cleaned[i], widthMeters, normalLeft));
      rightSide.add(_distance.offset(cleaned[i], widthMeters, normalRight));
    }

    final corridor = [...leftSide, ...rightSide.reversed];
    if (_hasPolygonSelfIntersection(corridor)) {
      return _computeConvexHull(corridor);
    }
    return corridor;
  }

  static double _averageBearingDegrees(double b1, double b2) {
    final r1 = b1 * math.pi / 180.0;
    final r2 = b2 * math.pi / 180.0;
    final x = math.cos(r1) + math.cos(r2);
    final y = math.sin(r1) + math.sin(r2);
    if (x.abs() < 1e-6 && y.abs() < 1e-6) return b2;
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  static bool _hasPolygonSelfIntersection(List<LatLng> poly) {
    final n = poly.length;
    if (n < 4) return false;
    for (int i = 0; i < n; i++) {
      final a1 = poly[i];
      final a2 = poly[(i + 1) % n];
      for (int j = i + 2; j < n; j++) {
        // Nachbarkanten teilen einen gemeinsamen Knoten und schneiden sich nicht echt
        if (i == 0 && j == n - 1) continue;
        final b1 = poly[j];
        final b2 = poly[(j + 1) % n];
        if (_segmentsProperlyIntersect(a1, a2, b1, b2)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _segmentsProperlyIntersect(
    LatLng a,
    LatLng b,
    LatLng c,
    LatLng d,
  ) {
    double ccw(LatLng p1, LatLng p2, LatLng p3) {
      return (p2.longitude - p1.longitude) * (p3.latitude - p1.latitude) -
          (p2.latitude - p1.latitude) * (p3.longitude - p1.longitude);
    }

    final d1 = ccw(a, b, c);
    final d2 = ccw(a, b, d);
    final d3 = ccw(c, d, a);
    final d4 = ccw(c, d, b);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  static List<LatLng> _computeConvexHull(List<LatLng> pts) {
    if (pts.length <= 3) return pts;
    final sorted = [...pts]..sort((a, b) {
      final cmpLon = a.longitude.compareTo(b.longitude);
      return cmpLon != 0 ? cmpLon : a.latitude.compareTo(b.latitude);
    });

    double cross(LatLng o, LatLng a, LatLng b) {
      return (a.longitude - o.longitude) * (b.latitude - o.latitude) -
          (a.latitude - o.latitude) * (b.longitude - o.longitude);
    }

    final lower = <LatLng>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <LatLng>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  static LatLng _computeCentroid(List<LatLng> pts) {
    double latSum = 0;
    double lonSum = 0;
    for (final p in pts) {
      latSum += p.latitude;
      lonSum += p.longitude;
    }
    return LatLng(latSum / pts.length, lonSum / pts.length);
  }

  static double _penaltyRadiusForTag(
    SpeciesProfile species,
    String tag, {
    required double fallback,
  }) {
    for (final rule in species.habitatRules.disturbancePenalties) {
      if (rule.osmTag == tag) return rule.radiusMeters;
    }
    return fallback;
  }

  static String _germanLabelForTag(String tag) {
    switch (tag) {
      case 'highway=path':
        return 'Wanderpfad';
      case 'highway=footway':
        return 'Fußweg';
      case 'highway=cycleway':
        return 'Radweg';
      case 'highway=track':
        return 'Forst-/Feldweg';
      case 'highway=service':
        return 'Wirtschaftsweg';
      default:
        return tag;
    }
  }

  static String _sectorKeyFor(LatLng pos) {
    final sLat = (pos.latitude * 120).round();
    final sLon = (pos.longitude * 120).round();
    return '${sLat}_$sLon';
  }
}
