import 'dart:math' as math;
import '../models/habitat_zone.dart';
import '../models/osm_way_models.dart';
import '../models/soil_substrate_profile.dart';
import '../models/species_profile.dart';

/// Wildbiologische Bewertungs-Engine für Habitatkandidaten.
///
/// Berechnet nach wildbiologischen Kriterien (Deckung, Ruhe, Äsung, Bodenbeschaffenheit,
/// Störungspuffer zu Wegen und Straßen) einen Eignungs-Score (35–93 Punkte).
class HabitatBiologicalScorer {
  /// Berechnet für einen gegebenen Kandidaten den artspezifischen Eignungs-Score.
  /// Gibt `null` zurück, falls der Kandidat aus wildbiologischen Gründen ausgeschlossen wird.
  static ({
    double score,
    HabitatZoneType zoneType,
    String title,
    String subtitle,
  })? scoreCandidate({
    required ParsedOsmWay candidate,
    required SpeciesProfile species,
    required double distToNearestTrailMeters,
    required double distToHighTrailMeters,
    required double distToTrackMeters,
    required double distToNearestRoadMeters,
    required int surroundingHighTrailQuadrants,
    required double distToWaterMeters,
    required double distToLargeForestMeters,
    required double distToSubstantialForestMeters,
    required double distToAnyForestMeters,
    required double distToMeadowMeters,
    required double distToFarmlandMeters,
    SoilSubstrateProfile? soilProfile,
    bool insideRoadNoiseBuffer = false,
    double roadNoisePenalty = 0.0,
    double? distToHuntingStandMeters,
  }) {
    final id = species.id;
    double score = 0.0;
    HabitatZoneType zoneType = HabitatZoneType.optimalEdge;
    String title = '';

    // 0. Klassifizierte Lärm-/Störpuffer großer Straßen (Autobahn 150 m,
    //    Bundesstraße 85 m … laut Störungsmatrix, artspezifisch skaliert).
    //    Der Eisvogel ist am Gewässer straßentolerant und nur vom Abzug betroffen.
    if (insideRoadNoiseBuffer && id != 'kingfisher') {
      return null;
    }

    // 1. Ausschluss von unmittelbaren Asphalt-Straßenrändern (Wildunfall-Gefahr!)
    final minRoadDist =
        id == 'roe_deer' || id == 'red_fox' || id == 'badger' ? 45.0 : 80.0;
    if (id != 'kingfisher' && distToNearestRoadMeters < minRoadDist) {
      return null;
    }

    if (id == 'roe_deer') {
      // FOKUS-ART REHWILD (Capreolus capreolus):
      // - Klassischer Konzentratselektierer & Schlüpfertyp der Wald-Feld-Kanten.
      // - Waldränder, Wiesen und lichte Waldbuchten bilden Top-Äsungs- und Einstandsflächen.
      // - Einstandsqualität (Tageseinstände):
      //   * Echte Hochwälder (largeForest) und Waldrandbuchten (forestEdgeBay) sind Top-Einstände.
      //   * Kleine Feldgehölze (smallWoodlot) bieten nur dann verlässliche Deckung und Ruhe, wenn
      //     sie eine geschlossene Fläche mit Mindestgröße (>= 0.55 ha isoliert, bzw. >= 0.35 ha waldfolgend)
      //     aufweisen und nicht durch extrem langgestreckte Form (< 0.75 ha bei span > 190m)
      //     nur eine winddurchzogene Baumreihe darstellen.
      //   * Dichte Dickungen (scrub wie Schwarzdorn/Brombeere) müssen kompakte geschlossene
      //     Flächen (>= 0.40 ha) sein.
      //   * Lineare Baumreihen (tree_row) bieten weder Bodendeckung noch Sichtschutz und
      //     werden niemals als Einstand gewählt.
      //   * Störung an Wegen: In kleinen Gehölzen (< 1.5 ha) meidet Rehwild unmittelbare Wegnähe (< 18m).

      // Differenzierter Ruhe-/Störungsfaktor für Rehwild (Entzerrung):
      // - Hauptwege, Straßen, Badestellen, Parkplätze: bis +11 Punkte bei >250m Ruhe,
      //   spürbarer Abzug bei Wegenähe (<40m bis zu -8 Punkte).
      // - Forst-/Feldwege (track): +2.5 Punkte bei Ruhe, bis -3 Punkte direkt am Weg.
      final highTrailFactor = distToHighTrailMeters >= 40.0
          ? ((distToHighTrailMeters.clamp(40.0, 260.0) - 40.0) / 220.0) * 11.0
          : -((40.0 - distToHighTrailMeters) / 40.0) * 8.0;
      final trackFactor = distToTrackMeters >= 20.0
          ? ((distToTrackMeters.clamp(20.0, 150.0) - 20.0) / 130.0) * 2.5
          : -((20.0 - distToTrackMeters) / 20.0) * 3.0;
      final quietAdjust = highTrailFactor + trackFactor;

      if (candidate.kind == OsmKind.forestEdgeBay) {
        final hasMeadowEdge = distToMeadowMeters <= 75.0;
        final hasFarmlandEdge = distToFarmlandMeters <= 65.0;
        final edgeBonus = hasMeadowEdge
            ? 12.0 - (distToMeadowMeters.clamp(0.0, 75.0) * 0.08)
            : (hasFarmlandEdge
                  ? 6.5 - (distToFarmlandMeters.clamp(0.0, 65.0) * 0.05)
                  : 2.0);
        score = 63.0 + edgeBonus + quietAdjust;
        zoneType = HabitatZoneType.optimalEdge;
        title = hasMeadowEdge
            ? 'Waldbucht & Wiesen-Äsungssaum'
            : (hasFarmlandEdge
                  ? 'Wald-Feld-Austrittskante'
                  : 'Waldrand-Saum');
      } else if (candidate.kind == OsmKind.meadow &&
          distToSubstantialForestMeters <= 150.0) {
        final forestProximityBonus =
            12.0 - (distToSubstantialForestMeters.clamp(0.0, 150.0) * 0.07);
        score = 60.0 + forestProximityBonus + quietAdjust;
        zoneType = HabitatZoneType.optimalEdge;
        title = distToSubstantialForestMeters <= 65.0
            ? 'Äsungswiese am Waldrand'
            : 'Waldnahe Äsungswiese';
      } else if (candidate.kind == OsmKind.largeForest &&
          candidate.areaHectares >= 1.5) {
        final areaBonus = (candidate.areaHectares.clamp(1.5, 25.0) - 1.5) * 0.16;
        score = 58.0 + areaBonus + quietAdjust;
        zoneType = HabitatZoneType.coreRefuge;
        title = 'Waldeinstand (${candidate.areaHectares.round()} ha)';
      } else if (candidate.kind == OsmKind.smallWoodlot) {
        // Feldgehölz / Remise:
        // Muss zwingend ein geschlossenes Flächen-Polygon sein (keine bloße Linie)
        if (!candidate.isClosedPolygon) return null;

        final isIsolated = distToLargeForestMeters > 70.0;
        final minHa = isIsolated ? 0.55 : 0.35;
        if (candidate.areaHectares < minHa) return null;

        // Extrem schmale, langgezogene Baumstreifen filtern (kein Kernbereich)
        if (candidate.areaHectares < 0.75 && candidate.maxSpanMeters > 190.0) {
          return null;
        }

        // In kleinen Gehölzen (< 1.5 ha) führt direkte Wegnähe (< 18m) zu Fluchtunruhe
        if (candidate.areaHectares < 1.5 && distToNearestTrailMeters < 18.0) {
          return null;
        }

        final trailBufferPenalty =
            (candidate.areaHectares < 1.5 && distToNearestTrailMeters < 32.0)
                ? ((32.0 - distToNearestTrailMeters) / 32.0) * 4.0
                : 0.0;

        final forestBonus = distToLargeForestMeters <= 70.0 ? 4.0 : 0.5;
        score = 54.0 +
            (candidate.areaHectares.clamp(0.4, 2.5) * 2.8) +
            forestBonus +
            quietAdjust -
            trailBufferPenalty;
        zoneType = HabitatZoneType.coreRefuge;
        title =
            'Feldgehölz-Einstand (${candidate.areaHectares.toStringAsFixed(1)} ha)';
      } else if (candidate.kind == OsmKind.scrub) {
        final isHedge = candidate.primaryTag.contains('hedge');
        if (isHedge) {
          final forestBonus = distToSubstantialForestMeters <= 90.0 ? 5.0 : 1.5;
          score = 63.0 + forestBonus + quietAdjust;
          zoneType = HabitatZoneType.optimalEdge;
          title = 'Heckenriegel & Deckungskorridor';
        } else {
          // Dichte Dickung (Schwarzdorn, Brombeere, Verjüngungskegel)
          if (!candidate.isClosedPolygon) return null;
          if (candidate.areaHectares < 0.40) return null;
          if (candidate.areaHectares < 0.75 && candidate.maxSpanMeters > 180.0) {
            return null;
          }
          if (distToNearestTrailMeters < 18.0) return null;

          final trailBufferPenalty = distToNearestTrailMeters < 30.0
              ? ((30.0 - distToNearestTrailMeters) / 30.0) * 3.5
              : 0.0;

          final forestBonus =
              distToSubstantialForestMeters <= 100.0 ? 3.5 : 0.0;
          score = 56.0 + forestBonus + quietAdjust - trailBufferPenalty;
          zoneType = HabitatZoneType.coreRefuge;
          title =
              'Dickungs-Einstand (${candidate.areaHectares.toStringAsFixed(1)} ha)';
        }
      } else if (candidate.kind == OsmKind.wetland &&
          candidate.primaryTag.contains('reedbed')) {
        score = 62.0 + quietAdjust;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Schilfgürtel-Deckung';
      } else if (candidate.kind == OsmKind.farmland &&
          distToSubstantialForestMeters <= 50.0) {
        final isOrchard = candidate.primaryTag == 'landuse=orchard';
        score = (isOrchard ? 62.0 : 54.0) + quietAdjust;
        zoneType = HabitatZoneType.optimalEdge;
        title = isOrchard ? 'Streuobstwiesen-Äsung' : 'Wald-Feld-Äsungskante';
      } else {
        return null;
      }
    } else if (id == 'red_deer') {
      // ROTWILD:
      // - NIEMALS in kleinen Feldgehölzen (`smallWoodlot` < 2.5 ha) oder Hecken mitten im Feld!
      // - Braucht großen, zusammenhängenden Hochwald (`largeForest`) oder ruhige
      //   Wiesen/Waldkanten UNMITTELBAR an einem großen Hochwald (distToLargeForest <= 55m).
      if (candidate.kind == OsmKind.smallWoodlot ||
          candidate.kind == OsmKind.scrub ||
          candidate.kind == OsmKind.farmland) {
        return null;
      }
      if (distToHighTrailMeters < 55.0 || distToNearestTrailMeters < 35.0) {
        return null;
      }
      if (surroundingHighTrailQuadrants >= 3) {
        return null;
      }

      if (candidate.kind == OsmKind.largeForest) {
        if (candidate.areaHectares < 12.0) return null;
        score =
            62.0 +
            (distToNearestTrailMeters.clamp(35.0, 380.0) - 35.0) * 0.08;
        zoneType = HabitatZoneType.coreRefuge;
        title = 'Hochwald-Ruhezone (${candidate.areaHectares.round()} ha)';
      } else if (candidate.kind == OsmKind.forestEdgeBay) {
        if (candidate.areaHectares < 10.0) return null;
        score =
            60.0 +
            (distToNearestTrailMeters.clamp(35.0, 350.0) - 35.0) * 0.075;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Hochwald-Austrittskante';
      } else if (candidate.kind == OsmKind.meadow &&
          distToLargeForestMeters <= 55.0) {
        score =
            61.0 +
            (distToNearestTrailMeters.clamp(35.0, 350.0) - 35.0) * 0.075;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Waldwiese am Hochwald';
      } else if (candidate.kind == OsmKind.wetland &&
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

      if (candidate.kind == OsmKind.wetland &&
          distToAnyForestMeters <= 180.0) {
        score =
            75.0 +
            (distToNearestTrailMeters.clamp(25.0, 250.0) - 25.0) * 0.07;
        zoneType = HabitatZoneType.waterSuhle;
        title = 'Suhle / Feuchtsenke';
      } else if (candidate.kind == OsmKind.largeForest) {
        score =
            68.0 +
            (distToNearestTrailMeters.clamp(25.0, 280.0) - 25.0) * 0.07;
        zoneType = HabitatZoneType.coreRefuge;
        title = 'Waldeinstand / Tageskessel';
      } else if (candidate.kind == OsmKind.forestEdgeBay) {
        score =
            70.0 +
            (distToNearestTrailMeters.clamp(25.0, 240.0) - 25.0) * 0.07;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Waldkante / Gebrächzone';
      } else if (candidate.kind == OsmKind.scrub &&
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

      if (candidate.kind == OsmKind.meadow) {
        score =
            74.0 +
            (distToNearestTrailMeters.clamp(15.0, 180.0) - 15.0) * 0.08;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Mäusewiese';
      } else if ((candidate.kind == OsmKind.scrub ||
              candidate.kind == OsmKind.smallWoodlot) &&
          candidate.areaHectares >= 0.25) {
        score =
            70.0 +
            (distToNearestTrailMeters.clamp(15.0, 160.0) - 15.0) * 0.07;
        zoneType = HabitatZoneType.coreRefuge;
        title = 'Heckenriegel / Feldgehölz';
      } else if (candidate.kind == OsmKind.forestEdgeBay) {
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
      if (candidate.kind == OsmKind.wetland ||
          candidate.kind == OsmKind.waterStream) {
        return null;
      }
      if (distToHighTrailMeters < 20.0) return null;

      final quietBonus =
          (distToHighTrailMeters.clamp(20.0, 220.0) - 20.0) * 0.055;
      // Trockener Boden ohne unmittelbare Staunässe (> 25m zu Sumpf/Wasser) wird für Baue bevorzugt
      final drySoilBonus = distToWaterMeters >= 25.0 ? 3.0 : -3.5;

      if (candidate.kind == OsmKind.forestEdgeBay) {
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
      } else if (candidate.kind == OsmKind.largeForest &&
          candidate.areaHectares >= 1.5) {
        score = 70.0 + quietBonus + drySoilBonus;
        zoneType = HabitatZoneType.coreRefuge;
        title =
            'Altholz-Dachsburg & Wurzelboden (${candidate.areaHectares.round()} ha)';
      } else if ((candidate.kind == OsmKind.scrub ||
              candidate.kind == OsmKind.smallWoodlot) &&
          candidate.areaHectares >= 0.20) {
        final isEmbankment = candidate.primaryTag.contains('embankment');
        final slopeBonus = isEmbankment ? 5.5 : 1.5;
        score = 69.5 + slopeBonus + quietBonus + drySoilBonus;
        zoneType = HabitatZoneType.coreRefuge;
        title = isEmbankment
            ? 'Böschung / Hohlweg-Dachsbau'
            : 'Wurzel-Heckenriegel / Nebenbau';
      } else if (candidate.kind == OsmKind.meadow &&
          distToAnyForestMeters <= 125.0) {
        final forestProx =
            5.0 - (distToAnyForestMeters.clamp(0.0, 125.0) * 0.03);
        score = 71.0 + forestProx + quietBonus;
        zoneType = HabitatZoneType.optimalEdge;
        title = 'Regenwurm-Wiese am Waldrand';
      } else if (candidate.kind == OsmKind.farmland &&
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
      if (candidate.kind == OsmKind.waterStream) {
        score =
            78.0 +
            (distToNearestTrailMeters.clamp(15.0, 150.0) - 15.0) * 0.10;
        zoneType = HabitatZoneType.waterSuhle;
        title = candidate.name != null
            ? 'Gewässer: ${candidate.name}'
            : 'Bachlauf / Teich';
      } else if (candidate.kind == OsmKind.wetland) {
        score =
            70.0 +
            (distToNearestTrailMeters.clamp(15.0, 150.0) - 15.0) * 0.08;
        zoneType = HabitatZoneType.waterSuhle;
        title = 'Feuchtufer';
      } else {
        return null;
      }
    }

    // 2. Differenzierter Wassernähe-Bonus (25-250 m ideal für Äsung & Schöpfen)
    final waterRule = species.habitatRules.waterProximity;
    if (waterRule != null && distToWaterMeters <= waterRule.maxDistanceMeters) {
      if (distToWaterMeters >= 25.0 && distToWaterMeters <= 220.0) {
        score += math.min(5.0, waterRule.scoreBoost);
      } else if (distToWaterMeters < 25.0) {
        score += 1.0;
      }
    }

    // 3. Moderater Abzug nur bei echter mehrseitiger Einkesselung durch Hauptwege
    if (surroundingHighTrailQuadrants >= 2) {
      final perQuadrantPenalty = id == 'roe_deer' ? 2.5 : 6.0;
      score -= (surroundingHighTrailQuadrants - 1) * perQuadrantPenalty;
    }

    // 3b. Abklingender Verkehrslärm-Abzug zwischen Störradius und Ruhedistanz
    //     (z. B. Autobahn: voller Abzug bei 150 m, kein Abzug mehr ab 350 m).
    score -= roadNoisePenalty;

    // 4. Geologischer Bodenuntergrund-Einfluss (BGR BÜK200 / ISRIC SoilGrids)
    if (soilProfile != null) {
      score += soilProfile.scoreAdjustmentForSpecies(
        id,
        isBurrowRefuge: zoneType == HabitatZoneType.coreRefuge,
      );
    }

    // 5. Praxis-Indikator: Hochsitz / Jägerstand in OSM (amenity=hunting_stand)
    // Jäger errichten Ansitze an bewährten Wechseln, Austrittsbuchten und Einständen.
    // Ein Hochsitz in 30–180 m Entfernung ist ein starker feldbiologischer Praxisnachweis.
    bool huntingStandNearby = false;
    if (distToHuntingStandMeters != null &&
        distToHuntingStandMeters >= 25.0 &&
        distToHuntingStandMeters <= 180.0) {
      if (const {'roe_deer', 'wild_boar', 'red_deer', 'red_fox'}.contains(id)) {
        score += 3.5;
        huntingStandNearby = true;
      }
    }

    // Entzerrter Score: Dynamischer Wertebereich zwischen 30.0 und 95.0
    final clampedScore = score.clamp(30.0, 95.0);
    if (clampedScore < 52.0) return null;

    final trailInfo = '${distToNearestTrailMeters.round()}m zum nächsten Wanderweg';
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
    final standInfo = huntingStandNearby
        ? ' • 🎯 Hochsitz ${distToHuntingStandMeters!.round()}m (bewährter Wechsel)'
        : '';

    return (
      score: clampedScore,
      zoneType: zoneType,
      title: title,
      subtitle: '$trailInfo ($densityInfo) • $waterInfo$soilInfo$standInfo',
    );
  }
}
