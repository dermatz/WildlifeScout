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
  final List<LatLng> huntingStands;
  final int totalOsmElementsEvaluated;
  final String dataSourceLabel;
  final SoilSubstrateProfile? soilProfile;

  const HabitatAnalysisResult({
    required this.habitatZones,
    required this.disturbanceTrails,
    this.huntingStands = const [],
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
      huntingStands: base.huntingStands,
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
    // Flächige Stillgewässer (Seen, Baggerseen, Weiher) als Ausschluss-Maske
    // für alle Landlebensräume: Rehwild steht nicht im Wasser!
    final waterBodies = waterStreams
        .where((w) => w.isClosedPolygon && w.primaryTag == 'natural=water')
        .toList();
    // Siedlungs- & Gewerbeflächen als Ausschluss-Maske: Wild hat keine
    // Einstands- und Äsungshabitate inmitten von Wohn- und Industriegebieten!
    final settlementPolygons = roadsAndSettlements
        .where((w) => w.isClosedPolygon && w.primaryTag.startsWith('landuse='))
        .toList();
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
          waterBodies: waterBodies,
          settlementPolygons: settlementPolygons,
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

      // Landlebensräume, die überwiegend auf einer Wasserfläche oder im Siedlungsgebiet liegen
      // (z. B. als „Waldlichtung“ fehlinterpretierter Baggersee / Wohnsiedlung), verwerfen.
      final isLandCandidate = cand.kind != OsmKind.waterStream &&
          cand.kind != OsmKind.wetland;
      final isMostlyOpenWater =
          isLandCandidate && _polygonCoverageFraction(cand, waterBodies) >= 0.4;
      final isMostlySettlement = isLandCandidate &&
          _polygonCoverageFraction(cand, settlementPolygons) >= 0.25;

      // Abstände zu allen klassifizierten Straßen & Siedlungen (für Lärm-Puffer laut Matrix)
      final roadDistances = _roadDistancesNear(
        cand.centroid,
        roadsAndSettlements,
        boundaryPoints: cand.points,
      );

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

      // Abstand zum nächsten Hochsitz (amenity=hunting_stand)
      double? distToHuntingStand;
      if (ways.huntingStands.isNotEmpty) {
        double minDist = double.infinity;
        for (final stand in ways.huntingStands) {
          final d = _distance.as(LengthUnit.Meter, cand.centroid, stand);
          if (d < minDist) minDist = d;
        }
        if (minDist <= 300.0) {
          distToHuntingStand = minDist;
        }
      }

      for (final sp in activeSpeciesList) {
        if (isMostlyOpenWater && sp.id != 'kingfisher') continue;
        if (isMostlySettlement && sp.id != 'red_fox') continue;

        final roadImpact = _roadNoiseImpact(roadDistances, sp.id);

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
          insideRoadNoiseBuffer: roadImpact.insideBuffer,
          roadNoisePenalty: roadImpact.penalty,
          distToHuntingStandMeters: distToHuntingStand,
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

      // Nach dem Zuschnitt erneut prüfen: Der sichtbare Zonen-Mittelpunkt darf
      // weder im See, noch in einer Siedlung, noch im Lärmpuffer einer Autobahn/Bundesstraße liegen.
      final finalCenter = _computeCentroid(polygonPts);
      if (z.speciesId != 'kingfisher') {
        final centerInWater = waterBodies.any(
          (w) => _isInsideBounds(finalCenter, w) &&
              _isPointInPolygon(finalCenter, w.points),
        );
        if (centerInWater) continue;

        final centerInSettlement = settlementPolygons.any(
          (w) => _isInsideBounds(finalCenter, w) &&
              _isPointInPolygon(finalCenter, w.points),
        );
        if (centerInSettlement && z.speciesId != 'red_fox') continue;

        final finalRoadImpact = _roadNoiseImpact(
          _roadDistancesNear(
            finalCenter,
            roadsAndSettlements,
            boundaryPoints: polygonPts,
          ),
          z.speciesId,
        );
        if (finalRoadImpact.insideBuffer) continue;
      }

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
          center: finalCenter,
          facingBearingDegrees: z.facingBearingDegrees,
        ),
      );
      if (deduplicatedZones.length >= 14) break;
    }

    return HabitatAnalysisResult(
      habitatZones: deduplicatedZones,
      disturbanceTrails: disturbanceTrails,
      huntingStands: ways.huntingStands,
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
    List<ParsedOsmWay> waterBodies = const [],
    List<ParsedOsmWay> settlementPolygons = const [],
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
        // Waldsee / Baggersee als innerer Ring: kein Einstand im Wasser
        if (waterBodies.any(
          (w) => _isInsideBounds(candidatePt, w) &&
              _isPointInPolygon(candidatePt, w.points),
        )) {
          continue;
        }
        // Siedlungsfläche im Wald (z. B. Waldsiedlung/Klinik): kein Ruheeinstand
        if (settlementPolygons.any(
          (w) => _isInsideBounds(candidatePt, w) &&
              _isPointInPolygon(candidatePt, w.points),
        )) {
          continue;
        }

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

  // --- Wasserflächen- & Straßenlärm-Masken ---

  static bool _isInsideBounds(LatLng p, ParsedOsmWay w) =>
      p.latitude >= w.minLat &&
      p.latitude <= w.maxLat &&
      p.longitude >= w.minLon &&
      p.longitude <= w.maxLon;

  /// Anteil (0.0–1.0) der Stichprobenpunkte eines Kandidaten, die innerhalb
  /// einer gegebenen Masken-Polygon-Liste (z. B. Wasserflächen oder Siedlungen) liegen.
  static double _polygonCoverageFraction(
    ParsedOsmWay cand,
    List<ParsedOsmWay> maskPolygons,
  ) {
    if (maskPolygons.isEmpty) return 0.0;
    final nearby = maskPolygons
        .where(
          (w) =>
              w.maxLat >= cand.minLat &&
              w.minLat <= cand.maxLat &&
              w.maxLon >= cand.minLon &&
              w.minLon <= cand.maxLon,
        )
        .toList();
    if (nearby.isEmpty) return 0.0;

    final samples = <LatLng>[cand.centroid];
    if (cand.isClosedPolygon && cand.points.length >= 4) {
      const steps = 6;
      for (int r = 1; r < steps; r++) {
        for (int c = 1; c < steps; c++) {
          final pt = LatLng(
            cand.minLat + (cand.maxLat - cand.minLat) * (r / steps),
            cand.minLon + (cand.maxLon - cand.minLon) * (c / steps),
          );
          if (_isPointInPolygon(pt, cand.points)) samples.add(pt);
        }
      }
    }

    int inMask = 0;
    for (final s in samples) {
      if (nearby.any(
        (w) => _isInsideBounds(s, w) && _isPointInPolygon(s, w.points),
      )) {
        inMask++;
      }
    }
    return inMask / samples.length;
  }

  /// Abstände (in Metern) eines Punktes und optionaler Polygonränder zu allen
  /// Straßen, Bahnen und Siedlungen im Umkreis von 450 m.
  static List<({String tag, double dist})> _roadDistancesNear(
    LatLng p,
    List<ParsedOsmWay> roads, {
    List<LatLng> boundaryPoints = const [],
  }) {
    const searchMeters = 450.0;
    const latPad = searchMeters * 0.0000092;
    const lonPad = searchMeters * 0.0000150;
    final result = <({String tag, double dist})>[];
    for (final r in roads) {
      if (p.latitude < r.minLat - latPad ||
          p.latitude > r.maxLat + latPad ||
          p.longitude < r.minLon - lonPad ||
          p.longitude > r.maxLon + lonPad) {
        continue;
      }
      double d = GeoGeometryUtils.distancePointToPolylineMeters(p, r.points);
      if (boundaryPoints.isNotEmpty && d < 300.0) {
        final step = math.max(1, boundaryPoints.length ~/ 6);
        for (int i = 0; i < boundaryPoints.length; i += step) {
          final dp = GeoGeometryUtils.distancePointToPolylineMeters(
            boundaryPoints[i],
            r.points,
          );
          if (dp < d) d = dp;
        }
      }
      if (d <= searchMeters) result.add((tag: r.primaryTag, dist: d));
    }
    return result;
  }

  /// Wertet die Straßenabstände gegen die Störungsmatrix aus:
  /// - Innerhalb des (artspezifisch skalierten) Störradius → Ausschluss.
  /// - Zwischen Störradius und Ruhedistanz → linear abklingender Abzug.
  static ({bool insideBuffer, double penalty}) _roadNoiseImpact(
    List<({String tag, double dist})> roadDistances,
    String speciesId,
  ) {
    bool inside = false;
    double maxPenalty = 0.0;
    for (final r in roadDistances) {
      final radius = DisturbanceMatrixService.getRadius(
        r.tag,
        speciesId: speciesId,
      );
      if (radius <= 0.0) continue;
      if (r.dist < radius) {
        inside = true;
        continue;
      }
      final rule = DisturbanceMatrixService.getRule(r.tag);
      final quiet = math.max(rule.quietBonusDistance, radius + 1.0);
      if (r.dist >= quiet) continue;
      final fullPenalty = DisturbanceMatrixService.getEffectivePenaltyPercent(
        r.tag,
        speciesId: speciesId,
      ).abs();
      final falloff = 1.0 - (r.dist - radius) / (quiet - radius);
      maxPenalty = math.max(maxPenalty, fullPenalty * falloff);
    }
    return (insideBuffer: inside, penalty: maxPenalty);
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
