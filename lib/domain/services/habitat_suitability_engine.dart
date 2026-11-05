import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/geo/geo_geometry_utils.dart';
import '../../core/privacy/coordinate_guard.dart';
import '../../data/api/soil_and_terrain_client.dart';
import '../../data/services/osm_element_parser.dart';
import '../models/habitat_zone.dart';
import '../models/osm_way_models.dart';
import '../models/soil_substrate_profile.dart';
import '../models/species_profile.dart';
import 'disturbance_matrix_service.dart';
import 'habitat_biological_scorer.dart';
import 'osm_spatial_metrics.dart';

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

      double? facing = z.facingBearingDegrees;
      if (facing == null && slopeSample.slopeDegrees >= 3.0) {
        facing = _cardinalToDegrees(slopeSample.aspectCardinal);
      }

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
          facingBearingDegrees: facing,
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
    // Erweiterter Beobachtungs-Sektor (+50% Radius: ~2,4 km Durchmesser)
    final bbox = CoordinateGuard.buildPrivacyBoundingBoxForOsm(
      origin.latitude,
      origin.longitude,
      latHalfSpan: 0.0105,
      lonHalfSpan: 0.0150,
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
        final elements = await OsmElementParser.decodeAndCompactAsync([response.body]);
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
        final compacted = await OsmElementParser.decodeAndCompactAsync(rawBodies);
        if (compacted.isNotEmpty) {
          return compacted;
        }
      }
    } catch (_) {}

    // 3. Fallback: Kompakterer Kern-Radius um den Ansitz
    try {
      final microBbox = CoordinateGuard.buildPrivacyBoundingBoxForOsm(
        origin.latitude,
        origin.longitude,
        latHalfSpan: 0.0060,
        lonHalfSpan: 0.0090,
      );
      final uri = Uri.https('api.openstreetmap.org', '/api/0.6/map.json', {
        'bbox':
            '${microBbox.west},${microBbox.south},${microBbox.east},${microBbox.north}',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final elements = await OsmElementParser.decodeAndCompactAsync([res.body]);
        if (elements.isNotEmpty) {
          return elements;
        }
      }
    } catch (_) {}

    return const [];
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
    final ways = OsmElementParser.parse(rawElements);

    final largeForests = ways.largeForests;
    final smallWoodlots = ways.smallWoodlots;
    final meadows = ways.meadows;
    final farmlands = ways.farmlands;
    final scrubs = ways.scrubs;
    final wetlands = ways.wetlands;
    final waterStreams = ways.waterStreams;
    final trailsHigh = ways.trailsHigh;
    final trailsTrack = ways.trailsTrack;
    final roadsAndSettlements = ways.roadsAndSettlements;

    // 1. Störungswege aufbauen anhand der wissenschaftlichen Störungsmatrix (YAML/Config)
    final candidateTrailWays = <({double dist, ParsedOsmWay way})>[];
    for (final w in [...trailsHigh, ...roadsAndSettlements]) {
      // Nur Wege aufnehmen, die laut Matrix als rote Störungskorridore definiert sind
      if (!DisturbanceMatrixService.shouldRenderRedLine(w.primaryTag)) {
        continue;
      }
      final distFromOrigin = _distance.as(LengthUnit.Meter, origin, w.centroid);
      if (distFromOrigin <= DisturbanceMatrixService.displayDistanceMeters) {
        candidateTrailWays.add((dist: distFromOrigin, way: w));
      }
    }
    candidateTrailWays.sort((a, b) => a.dist.compareTo(b.dist));

    final disturbanceTrails = <DisturbanceTrail>[];
    for (final entry in candidateTrailWays.take(DisturbanceMatrixService.maxRenderWays)) {
      final w = entry.way;
      final radius = DisturbanceMatrixService.getRadius(
        w.primaryTag,
        speciesId: species.id,
      );

      disturbanceTrails.add(
        DisturbanceTrail(
          id: 'trail_${w.osmId}',
          osmId: w.osmId,
          name: w.name ?? 'OSM ${DisturbanceMatrixService.getGermanLabel(w.primaryTag)}',
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
    final substantialForests = [
      ...largeForests,
      ...smallWoodlots.where((w) => w.areaHectares >= 0.75),
    ];
    final allForestsAndWoodlots = [
      ...largeForests,
      ...smallWoodlots.where((w) => w.areaHectares >= 0.35),
    ];

    // 2. Echte Waldrand-Austrittskanten UND Tiefen-Ruhezonen an Wäldern extrahieren!
    final forestEdgeAndDeepZones = <ParsedOsmWay>[];
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
          // Ausrichtung der Waldkante nach außen (vom Waldschwerpunkt zum Kantenabschnitt)
          final facingBearing =
              (_distance.bearing(forest.centroid, segCenter) + 360.0) % 360.0;
          forestEdgeAndDeepZones.add(
            ParsedOsmWay.withBounds(
              osmId: '${forest.osmId}_edge_${edgeIdx++}',
              primaryTag: 'Hochwald-Austrittskante',
              name: forest.name,
              kind: OsmKind.forestEdgeBay,
              points: corridor,
              centroid: segCenter,
              isClosedPolygon: true,
              areaHectares: forest.areaHectares,
              maxSpanMeters: forest.maxSpanMeters,
              facingBearingDegrees: facingBearing,
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

    final scoredZones = <({HabitatZone zone, ParsedOsmWay rawCand})>[];
    final candidates = <ParsedOsmWay>[
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
      final trailStats = OsmSpatialMetrics.computeExactTrailMetrics(
        cand.centroid,
        cand.points,
        trailsHigh,
        trailsTrack,
        roadsAndSettlements,
      );

      final distToWater = cand.kind == OsmKind.wetland ||
              cand.kind == OsmKind.waterStream
          ? 0.0
          : _minSegmentDistanceToWaysMeters(
              cand.centroid,
              allWaterWays,
              maxSearchMeters: 260.0,
            );

      // Abstand zum nächsten großen Hochwald (>= 2.5 ha)
      final distToLargeForest = cand.kind == OsmKind.largeForest ||
              (cand.kind == OsmKind.forestEdgeBay && cand.areaHectares >= 2.5)
          ? 0.0
          : _minSegmentDistanceToWaysMeters(
              cand.centroid,
              largeForests,
              maxSearchMeters: 220.0,
            );

      // Abstand zum nächsten substanziellen Wald oder Feldgehölz (>= 0.75 ha) für Waldrand-Austritte
      final distToSubstantialForest = cand.kind == OsmKind.largeForest ||
              (cand.kind == OsmKind.smallWoodlot && cand.areaHectares >= 0.75) ||
              (cand.kind == OsmKind.forestEdgeBay && cand.areaHectares >= 0.75)
          ? 0.0
          : _minSegmentDistanceToWaysMeters(
              cand.centroid,
              substantialForests,
              maxSearchMeters: 220.0,
            );

      // Abstand zum nächsten Wald oder Feldgehölz (wichtig für Rehwild)
      final distToAnyForest = cand.kind == OsmKind.largeForest ||
              cand.kind == OsmKind.smallWoodlot ||
              cand.kind == OsmKind.forestEdgeBay
          ? 0.0
          : _minSegmentDistanceToWaysMeters(
              cand.centroid,
              allForestsAndWoodlots,
              maxSearchMeters: 220.0,
            );

      // Lazy-Berechnung für Wiesen-/Acker-Abstand (nur für Waldrand-Buchten benötigt!)
      final distToMeadow = cand.kind == OsmKind.meadow
          ? 0.0
          : (cand.kind == OsmKind.forestEdgeBay
                ? _minSegmentDistanceToWaysMeters(
                    cand.centroid,
                    meadows,
                    maxSearchMeters: 95.0,
                  )
                : 500.0);
      final distToFarmland = cand.kind == OsmKind.farmland
          ? 0.0
          : (cand.kind == OsmKind.forestEdgeBay
                ? _minSegmentDistanceToWaysMeters(
                    cand.centroid,
                    farmlands,
                    maxSearchMeters: 85.0,
                  )
                : 500.0);

      for (final sp in activeSpeciesList) {
        final evaluation = HabitatBiologicalScorer.scoreCandidate(
          candidate: cand,
          species: sp,
          distToNearestTrailMeters: trailStats.minDistanceToHighTrail,
          distToHighTrailMeters: trailStats.minDistanceToHighTrail,
          distToTrackMeters: trailStats.minDistanceToTrack,
          distToNearestRoadMeters: trailStats.minDistanceToRoad,
          surroundingHighTrailQuadrants:
              trailStats.surroundingHighTrailQuadrants,
          distToWaterMeters: distToWater,
          distToLargeForestMeters: distToLargeForest,
          distToSubstantialForestMeters: distToSubstantialForest,
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
            distanceToNearestTrailMeters: trailStats.minDistanceToHighTrail,
            distanceToWaterMeters: distToWater,
            distanceToForestMeters: distToAnyForest,
            polygonPoints: cand.points,
            center: cand.centroid,
            facingBearingDegrees: cand.facingBearingDegrees,
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
          facingBearingDegrees: z.facingBearingDegrees,
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

  /// Findet im Inneren eines geschlossenen Waldes (>= 2.0 ha) die besten
  /// Einstände (die Punkte mit dem relativ größten Abstand zu Wegen, auch
  /// wenn ein Forst- oder Wanderweg durch den Wald verläuft).
  static List<ParsedOsmWay> _sampleInteriorQuietPockets(
    ParsedOsmWay forest, {
    required LatLng origin,
    required List<ParsedOsmWay> highDisturbanceWays,
    required List<ParsedOsmWay> allDisturbanceWays,
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
    final result = <ParsedOsmWay>[];
    int idx = 0;
    for (final p in pockets) {
      final tooClose = result.any(
        (existing) =>
            _distance.as(LengthUnit.Meter, existing.centroid, p.pt) < 140.0,
      );
      if (tooClose) continue;

      final circlePoly = _buildCirclePolygon(p.pt, radiusMeters: 48.0);
      result.add(
        ParsedOsmWay.withBounds(
          osmId: '${forest.osmId}_quiet_${idx++}',
          primaryTag: 'Tiefen-Einstand (${forest.primaryTag})',
          name: forest.name,
          kind: OsmKind.largeForest,
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

  // --- Geometry & Spatial delegations for backwards compatibility ---

  static double _minSegmentDistanceToWaysMeters(
    LatLng point,
    List<ParsedOsmWay> ways, {
    double maxSearchMeters = 450.0,
  }) => OsmSpatialMetrics.minSegmentDistanceToWaysMeters(
    point,
    ways,
    maxSearchMeters: maxSearchMeters,
  );

  static List<LatLng> _simplifyPolylinePoints(
    List<LatLng> pts, {
    required int maxVertices,
  }) => GeoGeometryUtils.simplifyPolylinePoints(pts, maxVertices: maxVertices);

  static List<LatLng> _clipLargePolygonAroundEdge(
    List<LatLng> pts,
    List<ParsedOsmWay> forests, {
    required LatLng origin,
    required double maxSpanMeters,
  }) => GeoGeometryUtils.clipLargePolygonAroundEdge(
    pts,
    origin: origin,
    maxSpanMeters: maxSpanMeters,
    distanceToForests: (pt) => _minSegmentDistanceToWaysMeters(pt, forests),
  );

  static bool _isPointInPolygon(LatLng pt, List<LatLng> polygon) =>
      GeoGeometryUtils.isPointInPolygon(pt, polygon);

  static List<LatLng> _buildCirclePolygon(
    LatLng center, {
    required double radiusMeters,
  }) => GeoGeometryUtils.buildCirclePolygon(center, radiusMeters: radiusMeters);

  static List<LatLng> _buildCorridorPolygonAlongLine(
    List<LatLng> line, {
    required double widthMeters,
  }) => GeoGeometryUtils.buildCorridorPolygonAlongLine(
    line,
    widthMeters: widthMeters,
  );

  static LatLng _computeCentroid(List<LatLng> pts) =>
      GeoGeometryUtils.computeCentroid(pts);

  static double? _cardinalToDegrees(String cardinal) =>
      GeoGeometryUtils.cardinalToDegrees(cardinal);

  static String _sectorKeyFor(LatLng pos) =>
      GeoGeometryUtils.sectorKeyFor(pos);
}
