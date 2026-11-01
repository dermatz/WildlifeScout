import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildlifescout/core/privacy/coordinate_guard.dart';
import 'package:wildlifescout/data/api/open_meteo_client.dart';
import 'package:wildlifescout/data/api/soil_and_terrain_client.dart';
import 'package:wildlifescout/data/repositories/species_repository.dart';
import 'package:wildlifescout/domain/models/soil_substrate_profile.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/domain/services/activity_score_calculator.dart';
import 'package:wildlifescout/domain/services/habitat_suitability_engine.dart';
import 'package:wildlifescout/domain/services/sun_moon_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('WildlifeScout Privacy & Real OSM Geodata Engine Tests', () {
    test('CoordinateGuard rounds GPS coordinates to 2 decimal places (DSGVO)', () {
      final result = CoordinateGuard.obfuscateForWeatherApi(52.978543, 13.762091);
      expect(result.lat, 52.98);
      expect(result.lon, 13.76);
      expect(CoordinateGuard.isValidCoordinate(52.98, 13.76), isTrue);
      expect(CoordinateGuard.isValidCoordinate(120.0, 13.76), isFalse);

      final bbox = CoordinateGuard.buildPrivacyBoundingBoxForOsm(52.9742, 13.7562);
      expect(bbox.south, lessThan(52.9742));
      expect(bbox.north, greaterThan(52.9742));
    });

    test('HabitatSuitabilityEngine evaluates real OSM elements for species', () {
      final redDeer = SpeciesProfile.fromJson({
        'id': 'red_deer',
        'name': 'Rotwild',
        'scientificName': 'Cervus elaphus',
        'category': 'ungulate',
        'shortDescription': 'Test',
        'accentColorHex': '#F59E0B',
        'behavior': {
          'scentSensitivityMeters': 450,
          'scentConeAngleDegrees': 50,
          'primaryActivityPeriods': ['dawn', 'dusk'],
          'barometerDropSensitivity': 0.9,
          'maxToleratedWindSpeedKmh': 55,
          'flightDistanceMeters': 250,
        },
        'habitatRules': {
          'edgePreferences': [],
          'landuseWeights': [],
          'disturbancePenalties': [
            {
              'osmTag': 'highway=path',
              'radiusMeters': 250,
              'penaltyScore': -12.0,
              'label': 'Wanderpfad',
            },
          ],
          'waterProximity': {'maxDistanceMeters': 200, 'scoreBoost': 3.5},
          'minContiguousAreaHectares': 50.0,
        },
        'fieldTips': ['Tipp 1'],
      });

      final sampleOsmElements = [
        {
          'type': 'way',
          'id': 90160329,
          'tags': {'landuse': 'forest'},
          'geometry': [
            {'lat': 52.9723, 'lon': 13.7521},
            {'lat': 52.9747, 'lon': 13.7521},
            {'lat': 52.9747, 'lon': 13.7588},
            {'lat': 52.9723, 'lon': 13.7588},
            {'lat': 52.9723, 'lon': 13.7521},
          ],
        },
        {
          'type': 'way',
          'id': 305301628,
          'tags': {'natural': 'wetland'},
          'geometry': [
            {'lat': 52.9725, 'lon': 13.7632},
            {'lat': 52.9755, 'lon': 13.7632},
            {'lat': 52.9755, 'lon': 13.7668},
            {'lat': 52.9725, 'lon': 13.7668},
            {'lat': 52.9725, 'lon': 13.7632},
          ],
        },
        {
          'type': 'way',
          'id': 44112233,
          'tags': {'highway': 'path', 'name': 'Waldsteig'},
          'geometry': [
            {'lat': 52.9780, 'lon': 13.7500},
            {'lat': 52.9790, 'lon': 13.7550},
          ],
        },
      ];

      const origin = LatLng(52.9742, 13.7562);
      final analysis = HabitatSuitabilityEngine.evaluateRealOsmElements(
        rawElements: sampleOsmElements,
        origin: origin,
        species: redDeer,
        sourceLabel: 'Test OSM',
      );

      expect(analysis.habitatZones, isNotEmpty);
      expect(analysis.disturbanceTrails, hasLength(1));
      expect(analysis.disturbanceTrails.first.osmId, '44112233');

      final forecast = OpenMeteoClient.buildOfflineFallbackForecast();
      final dawnWeather = forecast[6];
      final astro = SunMoonCalculator.calculate(
        dateTime: dawnWeather.time,
        latitude: origin.latitude,
        longitude: origin.longitude,
      );

      final assessment = ActivityScoreCalculator.evaluate(
        species: redDeer,
        weather: dawnWeather,
        astro: astro,
        hidePosition: origin,
        habitatZones: analysis.habitatZones,
      );

      expect(assessment.activityScorePercent, inInclusiveRange(8, 99));
      expect(assessment.ratingLabel, isNotEmpty);
    });

    test('Rehwild (roe_deer) keeps valid habitats even when trails and tracks border forest edges and meadows', () {
      final roeDeer = SpeciesProfile.fromJson({
        'id': 'roe_deer',
        'name': 'Rehwild',
        'scientificName': 'Capreolus capreolus',
        'category': 'ungulate',
        'shortDescription': 'Konzentratselektierer',
        'accentColorHex': '#10B981',
        'behavior': {
          'scentSensitivityMeters': 250,
          'scentConeAngleDegrees': 45,
          'primaryActivityPeriods': ['dawn', 'dusk'],
          'barometerDropSensitivity': 0.75,
          'maxToleratedWindSpeedKmh': 40,
          'flightDistanceMeters': 80,
        },
        'habitatRules': {
          'edgePreferences': [],
          'landuseWeights': [],
          'disturbancePenalties': [
            {
              'osmTag': 'highway=path',
              'radiusMeters': 45,
              'penaltyScore': -2.5,
              'label': 'Wanderpfad',
            },
            {
              'osmTag': 'highway=track',
              'radiusMeters': 25,
              'penaltyScore': -1.0,
              'label': 'Forstweg',
            },
          ],
          'waterProximity': {'maxDistanceMeters': 350, 'scoreBoost': 1.5},
          'minContiguousAreaHectares': 2.0,
        },
        'fieldTips': ['Tipp 1'],
      });

      // Typisches mitteleuropäisches Revier: Wald + Wiese + Hecke, durchzogen von
      // mehreren Forstwegen (highway=track) und Wanderpfaden (highway=path) direkt am Waldrand
      final osmWithDenseTrails = [
        {
          'type': 'way',
          'id': 1001,
          'tags': {'landuse': 'forest'},
          'geometry': [
            {'lat': 52.9720, 'lon': 13.7520},
            {'lat': 52.9742, 'lon': 13.7520},
            {'lat': 52.9742, 'lon': 13.7565},
            {'lat': 52.9720, 'lon': 13.7565},
            {'lat': 52.9720, 'lon': 13.7520},
          ],
        },
        {
          'type': 'way',
          'id': 1002,
          'tags': {'landuse': 'meadow'},
          'geometry': [
            {'lat': 52.9742, 'lon': 13.7520},
            {'lat': 52.9756, 'lon': 13.7520},
            {'lat': 52.9756, 'lon': 13.7565},
            {'lat': 52.9742, 'lon': 13.7565},
            {'lat': 52.9742, 'lon': 13.7520},
          ],
        },
        // Mehrere Forst- und Wanderwege unmittelbar entlang der Wald-Wiesen-Kante (< 15m)
        {
          'type': 'way',
          'id': 2001,
          'tags': {'highway': 'track'},
          'geometry': [
            {'lat': 52.9742, 'lon': 13.7515},
            {'lat': 52.9742, 'lon': 13.7540},
          ],
        },
        {
          'type': 'way',
          'id': 2002,
          'tags': {'highway': 'track'},
          'geometry': [
            {'lat': 52.9742, 'lon': 13.7540},
            {'lat': 52.9742, 'lon': 13.7570},
          ],
        },
        {
          'type': 'way',
          'id': 2003,
          'tags': {'highway': 'path'},
          'geometry': [
            {'lat': 52.9720, 'lon': 13.7540},
            {'lat': 52.9756, 'lon': 13.7540},
          ],
        },
      ];

      const origin = LatLng(52.9740, 13.7540);
      final result = HabitatSuitabilityEngine.evaluateRealOsmElements(
        rawElements: osmWithDenseTrails,
        origin: origin,
        species: roeDeer,
        sourceLabel: 'Test Rehwild OSM',
      );

      expect(result.habitatZones, isNotEmpty);
      expect(
        result.habitatZones.every((z) => z.speciesId == 'roe_deer'),
        isTrue,
      );
      for (final zone in result.habitatZones) {
        expect(zone.polygonPoints.length, greaterThanOrEqualTo(4));
      }
    });

    test('WeatherFrame provides directional cardinal labels and telemetry', () {
      final forecast = OpenMeteoClient.buildOfflineFallbackForecast();
      expect(forecast, hasLength(24 * 7));
      final frame = forecast.first;
      expect(frame.windCardinalLabel, isNotEmpty);
      expect(frame.temperatureCelsius, isNotNull);
      expect(frame.surfacePressureHpa, greaterThan(900));
      expect(frame.scentBlowDirectionDegrees, inInclusiveRange(0.0, 360.0));
    });

    test('Dachs (badger) favors dry forest slopes, embankments, and meadows while excluding waterlogged wetlands', () {
      final badger = SpeciesProfile.fromJson({
        'id': 'badger',
        'name': 'Dachs',
        'scientificName': 'Meles meles',
        'category': 'carnivore',
        'shortDescription': 'Baumeister des Waldes',
        'accentColorHex': '#A3E635',
        'behavior': {
          'scentSensitivityMeters': 220,
          'scentConeAngleDegrees': 45,
          'primaryActivityPeriods': ['dusk', 'night', 'dawn'],
          'barometerDropSensitivity': 0.80,
          'maxToleratedWindSpeedKmh': 38,
          'flightDistanceMeters': 55,
        },
        'habitatRules': {
          'edgePreferences': [],
          'landuseWeights': [],
          'disturbancePenalties': [
            {
              'osmTag': 'highway=path',
              'radiusMeters': 75,
              'penaltyScore': -5.5,
              'label': 'Wanderpfad',
            },
          ],
          'waterProximity': {'maxDistanceMeters': 280, 'scoreBoost': 2.2},
          'minContiguousAreaHectares': 1.5,
        },
        'fieldTips': ['Tipp'],
      });

      final osmBadgerElements = [
        {
          'type': 'way',
          'id': 5001,
          'tags': {'landuse': 'forest', 'leaf_type': 'broadleaved'},
          'geometry': [
            {'lat': 52.9720, 'lon': 13.7520},
            {'lat': 52.9742, 'lon': 13.7520},
            {'lat': 52.9742, 'lon': 13.7565},
            {'lat': 52.9720, 'lon': 13.7565},
            {'lat': 52.9720, 'lon': 13.7520},
          ],
        },
        {
          'type': 'way',
          'id': 5002,
          'tags': {'landuse': 'meadow'},
          'geometry': [
            {'lat': 52.9742, 'lon': 13.7520},
            {'lat': 52.9756, 'lon': 13.7520},
            {'lat': 52.9756, 'lon': 13.7565},
            {'lat': 52.9742, 'lon': 13.7565},
            {'lat': 52.9742, 'lon': 13.7520},
          ],
        },
        {
          'type': 'way',
          'id': 5003,
          'tags': {'man_made': 'embankment'},
          'geometry': [
            {'lat': 52.9710, 'lon': 13.7510},
            {'lat': 52.9718, 'lon': 13.7535},
          ],
        },
        {
          'type': 'way',
          'id': 5004,
          'tags': {'natural': 'wetland'},
          'geometry': [
            {'lat': 52.9770, 'lon': 13.7600},
            {'lat': 52.9785, 'lon': 13.7600},
            {'lat': 52.9785, 'lon': 13.7630},
            {'lat': 52.9770, 'lon': 13.7630},
            {'lat': 52.9770, 'lon': 13.7600},
          ],
        },
      ];

      const origin = LatLng(52.9735, 13.7540);
      final result = HabitatSuitabilityEngine.evaluateRealOsmElements(
        rawElements: osmBadgerElements,
        origin: origin,
        species: badger,
        sourceLabel: 'Test Dachs OSM',
      );

      expect(result.habitatZones, isNotEmpty);
      expect(
        result.habitatZones.every((z) => z.speciesId == 'badger'),
        isTrue,
      );
      // Staunasse Feuchtgebiete (wetland) dürfen niemals als Dachsbau auftauchen
      expect(
        result.habitatZones.any((z) => z.osmTag == 'natural=wetland'),
        isFalse,
      );

      // Prüfe BGR BÜK200 Bodenuntergrund-Klassifikation (Grabfähigkeit vs. Staunässe)
      final drySandSoil = SoilAndTerrainClient.parseBgrLegendText(
        'Vorherrschend podsolige Braunerden aus Geschiebedecksand über Schmelzwassersand',
      );
      expect(drySandSoil.diggability, SoilDiggability.optimalDryDiggable);
      expect(
        drySandSoil.scoreAdjustmentForSpecies('badger', isBurrowRefuge: true),
        greaterThan(0),
      );

      final wetPeatSoil = SoilAndTerrainClient.parseBgrLegendText(
        'Vorherrschend Niedermoor aus Torf über Flusssand',
      );
      expect(wetPeatSoil.diggability, SoilDiggability.waterloggedOrPeat);
      expect(
        wetPeatSoil.scoreAdjustmentForSpecies('badger', isBurrowRefuge: true),
        lessThan(0),
      );
    });

    test('All 6 species profiles provide license-free Unsplash photos, open biology data, behaviors, and field tips', () async {
      final repo = SpeciesRepository();
      final speciesList = await repo.loadAllSpecies();
      expect(speciesList, hasLength(6));

      for (final sp in speciesList) {
        // 1. Lizenzfreie Unsplash-Fotos (keine Unsplash+ / plus.unsplash.com)
        expect(sp.imageAssetPath, 'assets/species/images/${sp.id}.jpg');
        expect(sp.imageUrl, startsWith('https://images.unsplash.com/photo-'));
        expect(sp.imageUrl.contains('plus.unsplash.com'), isFalse);
        expect(sp.imageLicense, contains('Lizenzfrei'));
        expect(sp.imageAuthor, isNotEmpty);
        expect(sp.imageSourceUrl, startsWith('https://unsplash.com/photos/'));

        // 2. Offene Wildbiologie-Daten
        expect(sp.openData.taxonomy, isNotEmpty);
        expect(sp.openData.conservationStatus, isNotEmpty);
        expect(sp.openData.bodyWeight, isNotEmpty);
        expect(sp.openData.bodySize, isNotEmpty);
        expect(sp.openData.homeRange, isNotEmpty);
        expect(sp.openData.peakSeason, isNotEmpty);
        expect(sp.openData.diet, isNotEmpty);
        expect(sp.openData.tracksAndSigns, isNotEmpty);
        expect(sp.openData.vocalizations, isNotEmpty);
        expect(sp.openData.sensoryStrengths, isNotEmpty);
        expect(sp.openData.recommendedLens, isNotEmpty);

        // 3. Charakteristische Verhaltensweisen & wertvolle Praxis-Tipps
        expect(sp.behaviorTraits.length, greaterThanOrEqualTo(3));
        expect(sp.fieldTips.length, greaterThanOrEqualTo(5));
      }
    });
  });
}
