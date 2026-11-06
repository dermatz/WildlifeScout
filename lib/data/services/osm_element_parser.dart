import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:latlong2/latlong.dart';
import '../../core/geo/geo_geometry_utils.dart';
import '../../domain/models/osm_way_models.dart';

/// Container für alle nach Habitat- und Störungstypen vorklassifizierten OSM-Wege.
class CategorizedOsmWays {
  final List<ParsedOsmWay> largeForests;
  final List<ParsedOsmWay> smallWoodlots;
  final List<ParsedOsmWay> meadows;
  final List<ParsedOsmWay> farmlands;
  final List<ParsedOsmWay> scrubs;
  final List<ParsedOsmWay> wetlands;
  final List<ParsedOsmWay> waterStreams;
  final List<ParsedOsmWay> trailsHigh;
  final List<ParsedOsmWay> trailsTrack;
  final List<ParsedOsmWay> roadsAndSettlements;
  final List<LatLng> huntingStands;

  const CategorizedOsmWays({
    required this.largeForests,
    required this.smallWoodlots,
    required this.meadows,
    required this.farmlands,
    required this.scrubs,
    required this.wetlands,
    required this.waterStreams,
    required this.trailsHigh,
    required this.trailsTrack,
    required this.roadsAndSettlements,
    this.huntingStands = const [],
  });
}

/// Parser, Decoder und Klassifizierer für rohe OSM JSON-Elemente (Nodes, Ways, Multipolygon-Relations).
class OsmElementParser {
  static const Distance _distance = Distance();

  /// Erkennt flächige Stillgewässer (Seen, Baggerseen, Weiher, Rückhaltebecken,
  /// Flussflächen) anhand der gängigen OSM-Tagging-Varianten.
  static bool _isWaterBodyTagged(Map<String, dynamic> tags) {
    return tags['natural'] == 'water' ||
        tags.containsKey('water') ||
        tags['waterway'] == 'riverbank' ||
        const {'reservoir', 'basin'}.contains(tags['landuse']);
  }

  /// Web-sicherer Decoder: Nutzt auf nativen Plattformen (iOS/Android/macOS)
  /// ein Hintergrund-Isolate und fällt im Web (`kIsWeb`, wo `Isolate.run`
  /// eine `UnsupportedError` wirft) sauber auf asynchrone Event-Loop-Ausführung zurück.
  static Future<List<Map<String, dynamic>>> decodeAndCompactAsync(
    List<String> rawJsonBodies,
  ) async {
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      return decodeAndCompactOsmBodies(rawJsonBodies);
    }
    try {
      return await Isolate.run(
        () => decodeAndCompactOsmBodies(rawJsonBodies),
      );
    } catch (_) {
      return decodeAndCompactOsmBodies(rawJsonBodies);
    }
  }

  /// Läuft im Hintergrund-Isolate: Parst große JSON-Antworten, löst Node-Koordinaten
  /// direkt in `geometry` auf und verwirft alle irrelevanten Häuser/Nodes (reduziert
  /// 50.000+ Roh-Objekte auf ~350–600 wildbiologisch relevante Ways/Relationen).
  static List<Map<String, dynamic>> decodeAndCompactOsmBodies(
    List<String> rawJsonBodies,
  ) {
    final nodes = <int, Map<String, double>>{};
    final waysById = <int, Map<String, dynamic>>{};
    final relations = <Map<String, dynamic>>[];
    final seenRelIds = <dynamic>{};
    final compactedHuntingStandNodes = <Map<String, dynamic>>[];

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
            final tags = item['tags'] as Map<String, dynamic>?;
            if (tags != null && tags['amenity'] == 'hunting_stand') {
              compactedHuntingStandNodes.add({
                'type': 'node',
                'id': id,
                'tags': tags,
                'lat': lat,
                'lon': lon,
              });
            }
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
          landuse == 'residential' ||
          landuse == 'industrial' ||
          landuse == 'commercial' ||
          tags.containsKey('leisure') ||
          tags.containsKey('tourism') ||
          _isWaterBodyTagged(tags);
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
          tags.containsKey('railway') ||
          tags.containsKey('landuse') ||
          tags.containsKey('natural') ||
          tags.containsKey('waterway') ||
          tags.containsKey('leisure') ||
          tags.containsKey('tourism') ||
          tags.containsKey('barrier') ||
          tags['amenity'] == 'parking' ||
          tags['amenity'] == 'hunting_stand' ||
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

    return [...compactedWays, ...compactedRelations, ...compactedHuntingStandNodes];
  }

  /// Parst und klassifiziert rohe Overpass-/OSM-Elemente in typisierte Polygone und Wege.
  static CategorizedOsmWays parse(List<dynamic> rawElements) {
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
      OsmKind kind,
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
      final isWaterRel = _isWaterBodyTagged(tags);
      final isWetlandRel = natural == 'wetland' || isWaterRel;
      final isSettlementRel =
          landuse == 'residential' ||
          landuse == 'industrial' ||
          landuse == 'commercial' ||
          landuse == 'retail';
      final isLeisureRel =
          tags.containsKey('leisure') || tags.containsKey('tourism');

      if (!isForestRel &&
          !isMeadowRel &&
          !isWetlandRel &&
          !isSettlementRel &&
          !isLeisureRel) {
        continue;
      }

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
          // Innere Ringe sind nur dann eine Waldlichtung, wenn sie kein
          // Gewässer, Gebäude oder Siedlungsfläche sind (z. B. Baggersee im Wald!).
          if (!memberOwnTags.containsKey('building') &&
              memberOwnTags['landuse'] != 'residential' &&
              !_isWaterBodyTagged(memberOwnTags)) {
            relationDerivedWays.add((
              id: '${refId}_clearing',
              tag: 'Waldlichtung (inner forest ring)',
              name: name,
              kind: OsmKind.meadow,
              points: pts,
              minAreaBoostHa: 1.5,
            ));
          }
        } else if (isForestRel) {
          relationDerivedWays.add((
            id: '${relId}_$refId',
            tag: landuse == 'forest' ? 'landuse=forest' : 'natural=wood',
            name: name,
            kind: OsmKind.largeForest,
            points: pts,
            minAreaBoostHa: 35.0,
          ));
        } else if (role == 'inner') {
          // Innere Ringe von Wiesen- (Aussparung) bzw. Gewässer-Relationen
          // (Inseln) dürfen nicht als Wiese bzw. Wasserfläche gewertet werden.
          continue;
        } else if (isMeadowRel) {
          relationDerivedWays.add((
            id: '${relId}_$refId',
            tag: 'landuse=meadow',
            name: name,
            kind: OsmKind.meadow,
            points: pts,
            minAreaBoostHa: 2.0,
          ));
        } else if (isWetlandRel) {
          relationDerivedWays.add((
            id: '${relId}_$refId',
            tag: isWaterRel ? 'natural=water' : 'natural=wetland',
            name: name,
            kind: isWaterRel ? OsmKind.waterStream : OsmKind.wetland,
            points: pts,
            minAreaBoostHa: 1.0,
          ));
        } else if (isSettlementRel) {
          relationDerivedWays.add((
            id: '${relId}_$refId',
            tag: 'landuse=$landuse',
            name: name,
            kind: OsmKind.roadSettlement,
            points: pts,
            minAreaBoostHa: 2.0,
          ));
        } else if (isLeisureRel) {
          final leisureTag = tags.containsKey('leisure')
              ? 'leisure=${tags['leisure']}'
              : 'tourism=${tags['tourism']}';
          relationDerivedWays.add((
            id: '${relId}_$refId',
            tag: leisureTag,
            name: name,
            kind: OsmKind.trailHigh,
            points: pts,
            minAreaBoostHa: 1.0,
          ));
        }
      }
    }

    final largeForests = <ParsedOsmWay>[];
    final smallWoodlots = <ParsedOsmWay>[];
    final meadows = <ParsedOsmWay>[];
    final farmlands = <ParsedOsmWay>[];
    final scrubs = <ParsedOsmWay>[];
    final wetlands = <ParsedOsmWay>[];
    final waterStreams = <ParsedOsmWay>[];
    final trailsHigh = <ParsedOsmWay>[];
    final trailsTrack = <ParsedOsmWay>[];
    final roadsAndSettlements = <ParsedOsmWay>[];
    final huntingStands = <LatLng>[];

    // Sammle alle Standorte von Hochsitzen (Nodes mit amenity=hunting_stand)
    for (final item in rawElements) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type']?.toString() == 'node') {
        final tags = item['tags'] as Map<String, dynamic>?;
        if (tags != null && tags['amenity'] == 'hunting_stand') {
          final lat = (item['lat'] as num?)?.toDouble();
          final lon = (item['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) {
            huntingStands.add(LatLng(lat, lon));
          }
        }
      }
    }

    void registerCategorizedWay({
      required String idStr,
      required String primaryTag,
      required String? name,
      required OsmKind rawKind,
      required List<LatLng> pts,
      double minAreaOverrideHa = 0.0,
    }) {
      final center = GeoGeometryUtils.computeCentroid(pts);
      final span = GeoGeometryUtils.computeMaxSpanMeters(pts);
      final isClosed =
          pts.length >= 4 &&
          _distance.as(LengthUnit.Meter, pts.first, pts.last) < 40.0;
      final computedHa = isClosed
          ? GeoGeometryUtils.computePolygonAreaHectares(pts)
          : (span > 350.0 ? 25.0 : math.max(0.02, (span * 8.0) / 10000.0));
      final effectiveHa = math.max(computedHa, minAreaOverrideHa);

      OsmKind finalKind = rawKind;
      if (rawKind == OsmKind.largeForest) {
        if (effectiveHa < 2.5 && span < 260.0) {
          finalKind = OsmKind.smallWoodlot;
        }
      }

      final parsed = ParsedOsmWay.withBounds(
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
        case OsmKind.largeForest:
          largeForests.add(parsed);
        case OsmKind.smallWoodlot:
          smallWoodlots.add(parsed);
        case OsmKind.forestEdgeBay:
        case OsmKind.meadow:
          meadows.add(parsed);
        case OsmKind.farmland:
          farmlands.add(parsed);
        case OsmKind.scrub:
          scrubs.add(parsed);
        case OsmKind.treeRow:
          break;
        case OsmKind.wetland:
          wetlands.add(parsed);
        case OsmKind.waterStream:
          waterStreams.add(parsed);
        case OsmKind.trailHigh:
          trailsHigh.add(parsed);
        case OsmKind.trailTrack:
          trailsTrack.add(parsed);
        case OsmKind.roadSettlement:
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
      final railway = tags['railway']?.toString();
      final leisure = tags['leisure']?.toString();
      final tourism = tags['tourism']?.toString();
      final amenity = tags['amenity']?.toString();
      final barrier = tags['barrier']?.toString();

      // Aktive, oberirdische Bahnstrecken als Störungskorridor.
      // Ignoriert: Tunnel (kein Lärm/Sichtkontakt an der Oberfläche) sowie
      // Rangier-, Abstell- & Anschlussgleise (`service=*`) mit seltenem Verkehr.
      // Stillgelegte Strecken tragen `railway=disused/abandoned` und fallen raus.
      if (railway != null &&
          const {'rail', 'light_rail', 'narrow_gauge'}.contains(railway) &&
          tags['tunnel'] != 'yes' &&
          tags['tunnel'] != 'building_passage' &&
          !tags.containsKey('service')) {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: railway == 'light_rail' ? 'railway=light_rail' : 'railway=rail',
          name: name ?? tags['ref']?.toString(),
          rawKind: OsmKind.roadSettlement,
          pts: pts,
        );
      }

      if (highway != null) {
        if (const {
          'cycleway',
          'pedestrian',
          'bridleway',
          'steps',
        }.contains(highway)) {
          registerCategorizedWay(
            idStr: idStr,
            primaryTag: 'highway=$highway',
            name: name,
            rawKind: OsmKind.trailHigh,
            pts: pts,
          );
        } else if (highway == 'path' || highway == 'footway') {
          final isExplicitRecreationTrail =
              name != null ||
              tags['footway'] == 'designated' ||
              tags['bicycle'] == 'designated' ||
              tags['sac_scale'] != null ||
              tags['route'] == 'hiking' ||
              tags['hiking'] == 'yes' ||
              const {'asphalt', 'paved', 'concrete', 'sett'}.contains(tags['surface']);

          final isInformalOrUnpaved =
              tags['informal'] == 'yes' ||
              const {'bad', 'horrible', 'intermediate', 'no'}.contains(tags['trail_visibility']) ||
              const {'ground', 'dirt', 'grass', 'earth', 'mud', 'sand'}.contains(tags['surface']);

          if (isExplicitRecreationTrail && !isInformalOrUnpaved) {
            registerCategorizedWay(
              idStr: idStr,
              primaryTag: 'highway=$highway',
              name: name,
              rawKind: OsmKind.trailHigh,
              pts: pts,
            );
          } else {
            registerCategorizedWay(
              idStr: idStr,
              primaryTag: 'highway=$highway',
              name: name,
              rawKind: OsmKind.trailTrack,
              pts: pts,
            );
          }
        } else if (highway == 'track' || highway == 'service') {
          final hasName = name != null && name.trim().isNotEmpty;
          final isPavedOrCycle =
              tags['tracktype'] == 'grade1' ||
              tags['bicycle'] == 'yes' ||
              tags['bicycle'] == 'designated' ||
              tags['route'] == 'bicycle' ||
              const {'asphalt', 'paved', 'concrete', 'compacted'}.contains(tags['surface']);

          final isFrequentedWirtschaftsweg = hasName || isPavedOrCycle;

          registerCategorizedWay(
            idStr: idStr,
            primaryTag: isFrequentedWirtschaftsweg
                ? 'highway=$highway;frequented=yes'
                : 'highway=$highway',
            name: name,
            rawKind: isFrequentedWirtschaftsweg
                ? OsmKind.trailHigh
                : OsmKind.trailTrack,
            pts: pts,
          );
        } else if (const {
          // Autobahnen & Schnellstraßen inkl. Auf-/Abfahrten: stärkste
          // Störquelle (Dauerlärm, Wildschutzzaun) – dürfen niemals fehlen!
          'motorway',
          'motorway_link',
          'trunk',
          'trunk_link',
          'primary',
          'primary_link',
          'secondary',
          'secondary_link',
          'tertiary',
          'tertiary_link',
          'residential',
          'unclassified',
          'living_street',
        }.contains(highway)) {
          registerCategorizedWay(
            idStr: idStr,
            primaryTag: 'highway=$highway',
            name: name,
            rawKind: OsmKind.roadSettlement,
            pts: pts,
          );
        }
      }

      if (landuse == 'forest' || natural == 'wood') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: landuse == 'forest' ? 'landuse=forest' : 'natural=wood',
          name: name,
          rawKind: OsmKind.largeForest,
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
          rawKind: OsmKind.meadow,
          pts: pts,
        );
      } else if (landuse == 'farmland' || landuse == 'orchard') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'landuse=$landuse',
          name: name,
          rawKind: OsmKind.farmland,
          pts: pts,
        );
      } else if (natural == 'tree_row') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'natural=tree_row',
          name: name,
          rawKind: OsmKind.treeRow,
          pts: pts,
        );
      } else if (natural == 'scrub' ||
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
          rawKind: OsmKind.scrub,
          pts: pts,
          minAreaOverrideHa: isEmbankmentOrSlope ? 0.35 : 0.0,
        );
      } else if (natural == 'reedbed' || tags['wetland'] == 'reedbed') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'wetland=reedbed',
          name: name,
          rawKind: OsmKind.wetland,
          pts: pts,
        );
      } else if (natural == 'wetland') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'natural=wetland',
          name: name,
          rawKind: OsmKind.wetland,
          pts: pts,
        );
      } else if (natural == 'hedge' || barrier == 'hedge') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'barrier=hedge',
          name: name,
          rawKind: OsmKind.scrub,
          pts: pts,
          minAreaOverrideHa: 0.25,
        );
      } else if (_isWaterBodyTagged(tags) ||
          (waterway != null &&
              const {'stream', 'river', 'ditch', 'canal', 'drain'}.contains(
                waterway,
              ))) {
        final isWaterBody = _isWaterBodyTagged(tags);
        registerCategorizedWay(
          idStr: idStr,
          primaryTag:
              isWaterBody ? 'natural=water' : 'waterway=$waterway',
          name: name,
          rawKind: OsmKind.waterStream,
          pts: pts,
        );
      } else if (amenity == 'parking') {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'amenity=parking',
          name: name,
          rawKind: OsmKind.trailHigh,
          pts: pts,
        );
      } else if (leisure != null &&
          const {
            'swimming_area',
            'beach',
            'water_park',
            'park',
            'pitch',
            'golf_course',
            'dog_park',
          }.contains(leisure)) {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'leisure=$leisure',
          name: name,
          rawKind: OsmKind.trailHigh,
          pts: pts,
        );
      } else if (tourism != null &&
          const {'camp_site', 'caravan_site', 'theme_park'}.contains(tourism)) {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'tourism=$tourism',
          name: name,
          rawKind: OsmKind.trailHigh,
          pts: pts,
        );
      } else if (tags['amenity'] == 'hunting_stand') {
        final center = GeoGeometryUtils.computeCentroid(pts);
        huntingStands.add(center);
      } else if (landuse != null &&
          const {
            'residential',
            'industrial',
            'commercial',
            'retail',
            'farmyard',
          }.contains(landuse)) {
        registerCategorizedWay(
          idStr: idStr,
          primaryTag: 'landuse=$landuse',
          name: name,
          rawKind: OsmKind.roadSettlement,
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

    return CategorizedOsmWays(
      largeForests: largeForests,
      smallWoodlots: smallWoodlots,
      meadows: meadows,
      farmlands: farmlands,
      scrubs: scrubs,
      wetlands: wetlands,
      waterStreams: waterStreams,
      trailsHigh: trailsHigh,
      trailsTrack: trailsTrack,
      roadsAndSettlements: roadsAndSettlements,
      huntingStands: huntingStands,
    );
  }
}
