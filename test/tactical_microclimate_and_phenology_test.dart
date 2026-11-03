import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildlifescout/domain/models/habitat_zone.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/domain/models/weather_frame.dart';
import 'package:wildlifescout/domain/services/habitat_suitability_engine.dart';
import 'package:wildlifescout/domain/services/sun_moon_calculator.dart';
import 'package:wildlifescout/domain/services/wildlife_phenology_service.dart';
import 'package:wildlifescout/domain/services/wildlife_tactical_engine.dart';

void main() {
  final defaultSpecies = SpeciesProfile.fromJson({
    'id': 'roe_deer',
    'name': 'Rehwild (Capreolus capreolus)',
    'scientificName': 'Capreolus capreolus',
    'category': 'ungulate',
    'shortDescription': 'Scheuer Paarhufer mit extrem feinem Wind- & Witterungssinn.',
    'accentColorHex': '#F59E0B',
    'behavior': {
      'scentSensitivityMeters': 350.0,
      'scentConeAngleDegrees': 45.0,
      'primaryActivityPeriods': ['dawn', 'dusk'],
      'barometerDropSensitivity': 0.8,
      'maxToleratedWindSpeedKmh': 35.0,
      'flightDistanceMeters': 100.0,
    },
  });

  group('Factor 1: Waldkanten-Mikroklima (Luv vs. Lee / Windschatten)', () {
    final southFacingEdge = HabitatZone(
      id: 'south_edge',
      osmId: 'edge_1',
      osmTag: 'natural=wood',
      title: 'Waldkante Süd',
      subtitle: 'Waldrand zur Wiese',
      type: HabitatZoneType.optimalEdge,
      suitabilityScore: 80.0,
      distanceToNearestTrailMeters: 200.0,
      distanceToWaterMeters: 300.0,
      distanceToForestMeters: 5.0,
      polygonPoints: const [LatLng(52.0, 13.0), LatLng(52.001, 13.0)],
      center: const LatLng(52.0, 13.0),
      facingBearingDegrees: 180.0, // Zeigt nach Süden
    );

    final northFacingEdge = HabitatZone(
      id: 'north_edge',
      osmId: 'edge_2',
      osmTag: 'natural=wood',
      title: 'Waldkante Nord',
      subtitle: 'Waldrand zur Wiese',
      type: HabitatZoneType.optimalEdge,
      suitabilityScore: 80.0,
      distanceToNearestTrailMeters: 200.0,
      distanceToWaterMeters: 300.0,
      distanceToForestMeters: 5.0,
      polygonPoints: const [LatLng(52.0, 13.0), LatLng(52.001, 13.0)],
      center: const LatLng(52.0, 13.0),
      facingBearingDegrees: 0.0, // Zeigt nach Norden
    );

    test('Wind from North creates protected Lee (Windschatten) on South-facing edge', () {
      final weather = WeatherFrame(
        time: DateTime(2026, 5, 10, 18, 0),
        temperatureCelsius: 16.0,
        windSpeedKmh: 16.0,
        windGustsKmh: 24.0,
        windDirectionDegrees: 0.0, // Nordwind -> weht nach Süden (180°)
        surfacePressureHpa: 1013.0,
        pressureDelta6hHpa: 0.0,
        precipitationMm: 0.0,
        cloudCoverPercent: 20,
      );

      final astro = SunMoonCalculator.calculate(
        dateTime: weather.time,
        latitude: 52.0,
        longitude: 13.0,
      );

      final tactical = WildlifeTacticalEngine.assessZone(
        zone: southFacingEdge,
        species: defaultSpecies,
        weather: weather,
        astro: astro,
        baseActivityScore: 70,
      );

      // Muss Lee-Bonus erhalten
      expect(tactical.badges.any((b) => b.title.contains('Lee')), isTrue);
      final leeBadge = tactical.badges.firstWhere((b) => b.title.contains('Lee'));
      expect(leeBadge.isPositive, isTrue);
      expect(leeBadge.scoreDelta, greaterThan(0));
      expect(tactical.effectiveSuitabilityScore, greaterThan(southFacingEdge.suitabilityScore));
    });

    test('Wind from North creates exposed Luv (Winddruck) on North-facing edge', () {
      final weather = WeatherFrame(
        time: DateTime(2026, 3, 10, 18, 0), // März (Reguläre Äsungsperiode ohne Brunft/Fege-Sonderbonus)
        temperatureCelsius: 16.0,
        windSpeedKmh: 18.0,
        windGustsKmh: 26.0,
        windDirectionDegrees: 0.0, // Nordwind bläst frontal auf die Nordkante
        surfacePressureHpa: 1013.0,
        pressureDelta6hHpa: 0.0,
        precipitationMm: 0.0,
        cloudCoverPercent: 20,
      );

      final astro = SunMoonCalculator.calculate(
        dateTime: weather.time,
        latitude: 52.0,
        longitude: 13.0,
      );

      final tactical = WildlifeTacticalEngine.assessZone(
        zone: northFacingEdge,
        species: defaultSpecies,
        weather: weather,
        astro: astro,
        baseActivityScore: 70,
      );

      // Muss Luv-Abzug erhalten
      expect(tactical.badges.any((b) => b.title.contains('Luv')), isTrue);
      final luvBadge = tactical.badges.firstWhere((b) => b.title.contains('Luv'));
      expect(luvBadge.isPositive, isFalse);
      expect(luvBadge.scoreDelta, lessThan(0));
      expect(tactical.effectiveSuitabilityScore, lessThan(northFacingEdge.suitabilityScore));
    });

    test('Low wind (< 8 km/h) triggers neither Luv nor Lee', () {
      final weather = WeatherFrame(
        time: DateTime(2026, 5, 10, 18, 0),
        temperatureCelsius: 16.0,
        windSpeedKmh: 4.0, // Sanfter Wind
        windGustsKmh: 6.0,
        windDirectionDegrees: 0.0,
        surfacePressureHpa: 1013.0,
        pressureDelta6hHpa: 0.0,
        precipitationMm: 0.0,
        cloudCoverPercent: 20,
      );

      final astro = SunMoonCalculator.calculate(
        dateTime: weather.time,
        latitude: 52.0,
        longitude: 13.0,
      );

      final tactical = WildlifeTacticalEngine.assessZone(
        zone: southFacingEdge,
        species: defaultSpecies,
        weather: weather,
        astro: astro,
        baseActivityScore: 70,
      );

      expect(tactical.badges.any((b) => b.title.contains('Lee')), isFalse);
      expect(tactical.badges.any((b) => b.title.contains('Luv')), isFalse);
    });
  });

  group('Factor 2: Sonnenwärme & Hangexposition', () {
    test('Morning sun rewards East-facing forest edge after cold night', () {
      final eastFacingEdge = HabitatZone(
        id: 'east_edge',
        osmId: 'edge_east',
        osmTag: 'natural=wood',
        title: 'Waldkante Ost',
        subtitle: 'Waldrand zur Wiese',
        type: HabitatZoneType.optimalEdge,
        suitabilityScore: 75.0,
        distanceToNearestTrailMeters: 200.0,
        distanceToWaterMeters: 300.0,
        distanceToForestMeters: 5.0,
        polygonPoints: const [LatLng(52.0, 13.0), LatLng(52.001, 13.0)],
        center: const LatLng(52.0, 13.0),
        facingBearingDegrees: 85.0, // Zeigt nach Osten
      );

      final weather = WeatherFrame(
        time: DateTime(2026, 5, 10, 7, 0), // 07:00 Uhr morgens
        temperatureCelsius: 11.0,
        windSpeedKmh: 5.0,
        windGustsKmh: 8.0,
        windDirectionDegrees: 180.0,
        surfacePressureHpa: 1013.0,
        pressureDelta6hHpa: 0.0,
        precipitationMm: 0.0,
        cloudCoverPercent: 10, // Sonnig
      );

      // Konstruiere manuell Morgensonne mit flacher Sonnenhöhe
      const morningAstro = SunMoonPosition(
        sunAzimuthDegrees: 85.0, // Aus Osten
        sunElevationDegrees: 15.0, // Flach
        moonIlluminationFraction: 0.5,
        moonPhaseName: 'Halbmond',
        currentPeriod: ActivityPeriod.dawn,
        lightPhaseLabel: 'Goldenes Licht',
        isGoldenHour: true,
        isBlueHour: false,
      );

      final tactical = WildlifeTacticalEngine.assessZone(
        zone: eastFacingEdge,
        species: defaultSpecies,
        weather: weather,
        astro: morningAstro,
        baseActivityScore: 65,
      );

      expect(tactical.badges.any((b) => b.title.contains('Morgensonne')), isTrue);
    });

    test('Midday summer heat penalizes exposed open edge and rewards cool refuge', () {
      final openEdge = HabitatZone(
        id: 'open_edge',
        osmId: 'edge_open',
        osmTag: 'landuse=meadow',
        title: 'Offene Wiese',
        subtitle: 'Äsungswiese',
        type: HabitatZoneType.optimalEdge,
        suitabilityScore: 80.0,
        distanceToNearestTrailMeters: 200.0,
        distanceToWaterMeters: 300.0,
        distanceToForestMeters: 40.0,
        polygonPoints: const [LatLng(52.0, 13.0), LatLng(52.001, 13.0)],
        center: const LatLng(52.0, 13.0),
      );

      final coolRefuge = HabitatZone(
        id: 'cool_refuge',
        osmId: 'refuge_1',
        osmTag: 'natural=wood',
        title: 'Dichter Dickungs-Einstand',
        subtitle: 'Kernwald',
        type: HabitatZoneType.coreRefuge,
        suitabilityScore: 80.0,
        distanceToNearestTrailMeters: 300.0,
        distanceToWaterMeters: 100.0,
        distanceToForestMeters: 0.0,
        polygonPoints: const [LatLng(52.0, 13.0), LatLng(52.001, 13.0)],
        center: const LatLng(52.0, 13.0),
      );

      final hotWeather = WeatherFrame(
        time: DateTime(2026, 7, 20, 13, 0), // 13:00 Uhr Hochsommer
        temperatureCelsius: 29.0, // 29°C Hitze
        windSpeedKmh: 6.0,
        windGustsKmh: 9.0,
        windDirectionDegrees: 90.0,
        surfacePressureHpa: 1015.0,
        pressureDelta6hHpa: 0.0,
        precipitationMm: 0.0,
        cloudCoverPercent: 5,
      );

      const highNoonAstro = SunMoonPosition(
        sunAzimuthDegrees: 180.0,
        sunElevationDegrees: 58.0, // Steile pralle Mittagssonne
        moonIlluminationFraction: 0.1,
        moonPhaseName: 'Neumond',
        currentPeriod: ActivityPeriod.day,
        lightPhaseLabel: 'Hartes Tageslicht',
        isGoldenHour: false,
        isBlueHour: false,
      );

      final tacticalEdge = WildlifeTacticalEngine.assessZone(
        zone: openEdge,
        species: defaultSpecies,
        weather: hotWeather,
        astro: highNoonAstro,
        baseActivityScore: 40,
      );

      final tacticalRefuge = WildlifeTacticalEngine.assessZone(
        zone: coolRefuge,
        species: defaultSpecies,
        weather: hotWeather,
        astro: highNoonAstro,
        baseActivityScore: 40,
      );

      // Offene Fläche wird durch Hitze abgewertet
      expect(tacticalEdge.badges.any((b) => b.title.contains('Mittagshitze')), isTrue);
      // Kühle Dickung wird bei Hitze aufgewertet
      expect(tacticalRefuge.badges.any((b) => b.title.contains('Kühler Schatten-Einstand')), isTrue);
    });
  });

  group('Factor 3: Jahreszeitlicher Phänologie- & Brunft-Kalender', () {
    test('Roe deer Blattzeit (end of July) triggers high activity and edge preference', () {
      final date = DateTime(2026, 7, 28, 12, 0); // Ende Juli (Mitten in der Blattzeit)
      final phenology = WildlifePhenologyService.evaluate(
        speciesId: 'roe_deer',
        dateTime: date,
      );

      expect(phenology.phaseName, contains('Blattzeit'));
      expect(phenology.activityBonus, greaterThanOrEqualTo(10.0));
      expect(phenology.relaxesMiddayDip, isTrue);
      expect(phenology.boostEdgesAndMeadows, isTrue);
    });

    test('Red deer Brunft (late September) activates roaring rutting arena boost', () {
      final date = DateTime(2026, 9, 25, 19, 0);
      final phenology = WildlifePhenologyService.evaluate(
        speciesId: 'red_deer',
        dateTime: date,
      );

      expect(phenology.phaseName, contains('Rotwild-Brunft'));
      expect(phenology.activityBonus, greaterThanOrEqualTo(15.0));
      expect(phenology.boostEdgesAndMeadows, isTrue);
    });

    test('Wild boar Milchreife (July) triggers grain edge magnet', () {
      final date = DateTime(2026, 7, 10, 22, 0);
      final phenology = WildlifePhenologyService.evaluate(
        speciesId: 'wild_boar',
        dateTime: date,
      );

      expect(phenology.phaseName, contains('Milchreife'));
      expect(phenology.activityBonus, greaterThan(10.0));
      expect(phenology.boostEdgesAndMeadows, isTrue);
    });

    test('Winterruhe (January) reduces activity across species', () {
      final date = DateTime(2026, 1, 15, 10, 0);
      final roePhenology = WildlifePhenologyService.evaluate(
        speciesId: 'roe_deer',
        dateTime: date,
      );
      final badgerPhenology = WildlifePhenologyService.evaluate(
        speciesId: 'badger',
        dateTime: date,
      );

      expect(roePhenology.phaseName, contains('Winterruhe'));
      expect(roePhenology.activityBonus, lessThan(0));
      expect(badgerPhenology.activityBonus, lessThanOrEqualTo(-15.0));
    });
  });

  group('Factor 4: Zeit- & Wochentags-abhängige Pfadstörung', () {
    final edgeNearPath = HabitatZone(
      id: 'edge_near_path',
      osmId: 'zone_path_1',
      osmTag: 'natural=wood',
      title: 'Waldsaum am Waldweg',
      subtitle: 'Waldrand',
      type: HabitatZoneType.optimalEdge,
      suitabilityScore: 80.0,
      distanceToNearestTrailMeters: 45.0, // Nur 45m vom Pfad entfernt
      distanceToWaterMeters: 200.0,
      distanceToForestMeters: 0.0,
      polygonPoints: const [LatLng(52.0, 13.0), LatLng(52.001, 13.0)],
      center: const LatLng(52.0, 13.0),
    );

    final deepRefuge = HabitatZone(
      id: 'deep_refuge',
      osmId: 'refuge_2',
      osmTag: 'natural=wood',
      title: 'Ruhige Kernzone',
      subtitle: 'Abgeschieden',
      type: HabitatZoneType.coreRefuge,
      suitabilityScore: 82.0,
      distanceToNearestTrailMeters: 220.0, // 220m weg vom Pfad
      distanceToWaterMeters: 200.0,
      distanceToForestMeters: 0.0,
      polygonPoints: const [LatLng(52.0, 13.0), LatLng(52.001, 13.0)],
      center: const LatLng(52.0, 13.0),
    );

    test('Weekday early morning (05:30 Wednesday): empty paths reward edge with peace bonus', () {
      // 2026-05-13 war ein Mittwoch (Wednesday)
      final wednesdayMorning = DateTime(2026, 5, 13, 5, 30);
      expect(wednesdayMorning.weekday, DateTime.wednesday);

      final weather = WeatherFrame(
        time: wednesdayMorning,
        temperatureCelsius: 9.0,
        windSpeedKmh: 4.0,
        windGustsKmh: 6.0,
        windDirectionDegrees: 180.0,
        surfacePressureHpa: 1013.0,
        pressureDelta6hHpa: 0.0,
        precipitationMm: 0.0,
        cloudCoverPercent: 20,
      );

      final astro = SunMoonCalculator.calculate(
        dateTime: weather.time,
        latitude: 52.0,
        longitude: 13.0,
      );

      final tactical = WildlifeTacticalEngine.assessZone(
        zone: edgeNearPath,
        species: defaultSpecies,
        weather: weather,
        astro: astro,
        baseActivityScore: 75,
      );

      expect(tactical.badges.any((b) => b.title.contains('Wochentagsruhe')), isTrue);
      expect(tactical.effectiveSuitabilityScore, greaterThan(edgeNearPath.suitabilityScore));
    });

    test('Weekend afternoon (14:30 Sunday): high recreational traffic penalizes edge near paths and boosts deep refuge', () {
      // 2026-05-17 war ein Sonntag (Sunday)
      final sundayAfternoon = DateTime(2026, 5, 17, 14, 30);
      expect(sundayAfternoon.weekday, DateTime.sunday);

      final weather = WeatherFrame(
        time: sundayAfternoon,
        temperatureCelsius: 20.0,
        windSpeedKmh: 5.0,
        windGustsKmh: 8.0,
        windDirectionDegrees: 180.0,
        surfacePressureHpa: 1013.0,
        pressureDelta6hHpa: 0.0,
        precipitationMm: 0.0,
        cloudCoverPercent: 20,
      );

      final astro = SunMoonCalculator.calculate(
        dateTime: weather.time,
        latitude: 52.0,
        longitude: 13.0,
      );

      final tacticalNearPath = WildlifeTacticalEngine.assessZone(
        zone: edgeNearPath,
        species: defaultSpecies,
        weather: weather,
        astro: astro,
        baseActivityScore: 50,
      );

      final tacticalDeepRefuge = WildlifeTacticalEngine.assessZone(
        zone: deepRefuge,
        species: defaultSpecies,
        weather: weather,
        astro: astro,
        baseActivityScore: 50,
      );

      // Wegnahe Kante erhält deutlichen Wochenend-Freizeitdruck-Abzug
      expect(tacticalNearPath.badges.any((b) => b.title.contains('Wochenend-Freizeitdruck')), isTrue);
      expect(tacticalNearPath.effectiveSuitabilityScore, lessThan(edgeNearPath.suitabilityScore));

      // Tiefes Refugium profitiert als Rückzugsort
      expect(tacticalDeepRefuge.badges.any((b) => b.title.contains('Rückzugsrefugium')), isTrue);
    });
  });

  group('Trampelpfad & Feldweg vs. Störungsweg Differentiation Tests', () {
    test('HabitatSuitabilityEngine excludes agricultural tracks and informal paths from DisturbanceTrails', () {
      final sampleWays = [
        // 1. Waldpolygon
        {
          'type': 'way',
          'id': 100,
          'tags': {'landuse': 'forest'},
          'geometry': [
            {'lat': 52.000, 'lon': 13.000},
            {'lat': 52.005, 'lon': 13.000},
            {'lat': 52.005, 'lon': 13.005},
            {'lat': 52.000, 'lon': 13.005},
            {'lat': 52.000, 'lon': 13.000},
          ],
        },
        // 2. Offizieller benannter Wanderweg (muss in DisturbanceTrails)
        {
          'type': 'way',
          'id': 200,
          'tags': {'highway': 'path', 'name': 'Panoramaweg'},
          'geometry': [
            {'lat': 52.001, 'lon': 13.006},
            {'lat': 52.004, 'lon': 13.006},
          ],
        },
        // 3. Normaler Feldweg / Wirtschaftsweg im Acker (DARF NICHT in DisturbanceTrails)
        {
          'type': 'way',
          'id': 300,
          'tags': {'highway': 'track', 'tracktype': 'grade3'},
          'geometry': [
            {'lat': 51.998, 'lon': 13.001},
            {'lat': 51.998, 'lon': 13.004},
          ],
        },
        // 4. Einfacher Trampelpfad / unbefestigter Pfad (DARF NICHT in DisturbanceTrails)
        {
          'type': 'way',
          'id': 400,
          'tags': {'highway': 'path', 'surface': 'ground', 'informal': 'yes'},
          'geometry': [
            {'lat': 51.997, 'lon': 13.001},
            {'lat': 51.997, 'lon': 13.004},
          ],
        },
        // 5. Benannter Wirtschaftsweg mit Fahrradverkehr (z.B. Esslinger Weg / Kurzwiesenäcker) (MUSS in DisturbanceTrails)
        {
          'type': 'way',
          'id': 500,
          'tags': {'highway': 'track', 'name': 'Esslinger Weg', 'tracktype': 'grade1'},
          'geometry': [
            {'lat': 52.000, 'lon': 13.001},
            {'lat': 52.000, 'lon': 13.004},
          ],
        },
      ];

      final analysis = HabitatSuitabilityEngine.evaluateRealOsmElements(
        rawElements: sampleWays,
        origin: const LatLng(52.002, 13.002),
        species: defaultSpecies,
        sourceLabel: 'Test',
      );

      // Panoramaweg und der benannte Esslinger Weg landen als Störungsweg auf der Karte!
      expect(analysis.disturbanceTrails.any((t) => t.osmId == '200'), isTrue);
      expect(analysis.disturbanceTrails.any((t) => t.osmId == '500'), isTrue);
      // Namenloser unbefestigter Feldweg und Trampelpfad dürfen NICHT als Störungsweg rot gezeichnet werden!
      expect(analysis.disturbanceTrails.any((t) => t.osmId == '300'), isFalse);
      expect(analysis.disturbanceTrails.any((t) => t.osmId == '400'), isFalse);
    });
  });
}
