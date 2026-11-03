import 'package:flutter_test/flutter_test.dart';
import 'package:wildlifescout/domain/services/disturbance_matrix_service.dart';

void main() {
  group('DisturbanceMatrixService & YAML Config Tests', () {
    const sampleYaml = '''
version: "1.0"
source: "FVA Baden-Württemberg"

ways:
  "highway=motorway":
    label: "Autobahn"
    description: "Permanenter Schallteppich"
    radius_meters: 150
    max_penalty_percent: -25.0
    quiet_bonus_distance: 350
    renders_red_line: true

  "highway=cycleway":
    label: "Ausgewiesener Radweg (asphaltiert)"
    description: "Schneller Rad- & E-Bike-Verkehr"
    radius_meters: 65
    max_penalty_percent: -9.0
    quiet_bonus_distance: 160
    renders_red_line: true

  "highway=track;frequented=yes":
    label: "Befestigter / Benannter Wirtschaftsweg"
    description: "Asphaltierte/benannte Flurwege mit Radverkehr"
    radius_meters: 28
    max_penalty_percent: -4.5
    quiet_bonus_distance: 85
    renders_red_line: true

  "highway=track":
    label: "Ruhiger Feldrain / Unbefestigte Ackerfahrspur"
    description: "Reine Traktorspuren ohne Freizeitverkehr"
    radius_meters: 0
    max_penalty_percent: 0.0
    quiet_bonus_distance: 20
    renders_red_line: false

species_sensitivity:
  red_deer:
    name: "Rotwild"
    sensitivity_multiplier: 1.85
    hard_avoidance_distance_meters: 55.0
    note: "Extrem scheues Steppentier"

  roe_deer:
    name: "Rehwild"
    sensitivity_multiplier: 1.0
    hard_avoidance_distance_meters: 18.0
    note: "Schlüpfertyp"

  red_fox:
    name: "Rotfuchs"
    sensitivity_multiplier: 0.65
    hard_avoidance_distance_meters: 12.0
    note: "Kulturfolger"

time_modulation:
  weekend_afternoon: 1.45
  weekday_daytime: 0.90
  weekday_rushhour: 1.15
  dawn_and_dusk: 0.25
  nighttime: 0.08

map_display:
  display_distance_meters: 3500.0
  max_render_ways: 450
''';

    setUp(() {
      DisturbanceMatrixService.loadFromYamlString(sampleYaml);
    });

    test('Parses ways correctly from YAML', () {
      final cycleway = DisturbanceMatrixService.getRule('highway=cycleway');
      expect(cycleway.label, 'Ausgewiesener Radweg (asphaltiert)');
      expect(cycleway.radiusMeters, 65.0);
      expect(cycleway.maxPenaltyPercent, -9.0);
      expect(cycleway.rendersRedLine, isTrue);

      final trackFrequented = DisturbanceMatrixService.getRule(
        'highway=track;frequented=yes',
      );
      expect(trackFrequented.radiusMeters, 28.0);
      expect(trackFrequented.rendersRedLine, isTrue);

      final calmTrack = DisturbanceMatrixService.getRule('highway=track');
      expect(calmTrack.radiusMeters, 0.0);
      expect(calmTrack.maxPenaltyPercent, 0.0);
      expect(calmTrack.rendersRedLine, isFalse);
    });

    test('Calculates species-specific adjusted radii', () {
      // Rotwild (sensitivity 1.85) vs. Normal (1.0) vs. Rotfuchs (0.65)
      final roeRadius = DisturbanceMatrixService.getRadius(
        'highway=cycleway',
        speciesId: 'roe_deer',
      );
      final redDeerRadius = DisturbanceMatrixService.getRadius(
        'highway=cycleway',
        speciesId: 'red_deer',
      );
      final foxRadius = DisturbanceMatrixService.getRadius(
        'highway=cycleway',
        speciesId: 'red_fox',
      );

      expect(roeRadius, 65.0);
      expect(redDeerRadius, greaterThan(roeRadius));
      expect(foxRadius, lessThan(roeRadius));
    });

    test('Evaluates time modulation correctly', () {
      // Sonntag 14:00 (Weekend Afternoon Rush)
      final sundayAfternoon = DateTime(2026, 11, 8, 14, 0); // Sunday
      final weekendFactor = DisturbanceMatrixService.getTimeModulationFactor(
        sundayAfternoon,
      );
      expect(weekendFactor, closeTo(1.45, 0.01));

      // Mittwoch 05:30 (Morgendämmerung)
      final wednesdayDawn = DateTime(2026, 11, 4, 5, 30); // Wednesday
      final dawnFactor = DisturbanceMatrixService.getTimeModulationFactor(
        wednesdayDawn,
      );
      expect(dawnFactor, closeTo(0.25, 0.01));

      // Mittwoch 23:00 (Nacht)
      final wednesdayNight = DateTime(2026, 11, 4, 23, 0);
      final nightFactor = DisturbanceMatrixService.getTimeModulationFactor(
        wednesdayNight,
      );
      expect(nightFactor, closeTo(0.08, 0.01));
    });

    test('Effective penalty takes species and time into account', () {
      final penaltySunday =
          DisturbanceMatrixService.getEffectivePenaltyPercent(
        'highway=cycleway',
        speciesId: 'red_deer',
        time: DateTime(2026, 11, 8, 14, 0), // Sunday afternoon
      );

      final penaltyNight = DisturbanceMatrixService.getEffectivePenaltyPercent(
        'highway=cycleway',
        speciesId: 'red_fox',
        time: DateTime(2026, 11, 4, 23, 0), // Nighttime
      );

      // Red deer on Sunday afternoon should have a much heavier penalty than fox at night
      expect(penaltySunday, lessThan(-15.0)); // more negative
      expect(penaltyNight.abs(), lessThan(1.0)); // nearly 0 at night
    });

    test('Red line rendering logic distinguishes paths and tracks', () {
      expect(
        DisturbanceMatrixService.shouldRenderRedLine('highway=motorway'),
        isTrue,
      );
      expect(
        DisturbanceMatrixService.shouldRenderRedLine('highway=cycleway'),
        isTrue,
      );
      expect(
        DisturbanceMatrixService.shouldRenderRedLine(
          'highway=track;frequented=yes',
        ),
        isTrue,
      );
      expect(
        DisturbanceMatrixService.shouldRenderRedLine('highway=track'),
        isFalse,
      );
    });

    test('Hard avoidance distance is mapped properly for species', () {
      expect(
        DisturbanceMatrixService.getHardAvoidanceDistance('red_deer'),
        55.0,
      );
      expect(
        DisturbanceMatrixService.getHardAvoidanceDistance('roe_deer'),
        18.0,
      );
    });

    test('Parses map display distance and max ways properly', () {
      expect(DisturbanceMatrixService.displayDistanceMeters, 3500.0);
      expect(DisturbanceMatrixService.maxRenderWays, 450);
    });
  });
}
