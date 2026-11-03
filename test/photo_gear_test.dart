import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildlifescout/core/theme/wildlifescout_theme.dart';
import 'package:wildlifescout/data/services/photo_gear_service.dart';
import 'package:wildlifescout/domain/models/photo_gear_profile.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/domain/services/wildlife_photo_calculator.dart';
import 'package:wildlifescout/presentation/widgets/photo_gear_sheet.dart';
import 'package:wildlifescout/presentation/widgets/species_inspector_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PhotoGearProfile Optical Physics Unit Tests', () {
    test('Calculates full-frame 400mm optical values correctly', () {
      const gear = PhotoGearProfile(
        focalLengthMm: 400.0,
        maxAperture: 4.0,
        sensorFormat: CameraSensorFormat.fullFrame,
        teleconverter: Teleconverter.none,
      );

      expect(gear.effectiveFocalLengthMm, 400.0);
      expect(gear.effectiveAperture, 4.0);

      // Horizontaler Bildwinkel bei 400 mm an Vollformat (36 mm Sensorbreite):
      // 2 * atan(36 / (2 * 400)) * (180 / pi) ~= 5.15°
      expect(gear.horizontalFovDeg, closeTo(5.15, 0.05));

      // Sichtbreite bei 50 m: 2 * 50 * tan(5.15° / 2) ~= 4.5 m
      final width50m = gear.fieldWidthAtDistanceMeters(50.0);
      expect(width50m, closeTo(4.5, 0.1));

      // Schärfentiefe bei 30 m Distanz
      final dof30m = gear.depthOfFieldCm(30.0);
      expect(dof30m, greaterThan(50.0));
      expect(dof30m, lessThan(160.0));
    });

    test('Calculates APS-C crop and 1.4x teleconverter multiplication', () {
      const gear = PhotoGearProfile(
        focalLengthMm: 400.0,
        maxAperture: 4.0,
        sensorFormat: CameraSensorFormat.apscSonyNikonFuji, // 1.5x
        teleconverter: Teleconverter.tc14, // 1.4x
      );

      // Physikalische Brennweite: 400 * 1.4 = 560 mm
      expect(gear.opticalFocalLengthMm, 560.0);

      // Kleinbild-Äquivalent: 400 * 1.4 * 1.5 = 840 mm KB!
      expect(gear.effectiveFocalLengthMm, 840.0);

      // Effektive Blende: f/4 * 1.4 = f/5.6
      expect(gear.effectiveAperture, closeTo(5.6, 0.05));

      // Bildwinkel ist spürbar enger (unter 3°)
      expect(gear.horizontalFovDeg, lessThan(3.0));
      expect(gear.horizontalFovDeg, greaterThan(2.0));
    });

    test('Serializes to and from JSON without precision loss', () {
      const original = PhotoGearProfile(
        lensName: 'Sony 200–600 mm',
        focalLengthMm: 600.0,
        maxAperture: 6.3,
        sensorFormat: CameraSensorFormat.microFourThirds,
        teleconverter: Teleconverter.tc20,
        hasOpticalStabilization: false,
      );

      final json = original.toJson();
      final restored = PhotoGearProfile.fromJson(json);

      expect(restored.lensName, 'Sony 200–600 mm');
      expect(restored.focalLengthMm, 600.0);
      expect(restored.maxAperture, 6.3);
      expect(restored.sensorFormat, CameraSensorFormat.microFourThirds);
      expect(restored.teleconverter, Teleconverter.tc20);
      expect(restored.hasOpticalStabilization, isFalse);
    });
  });

  group('WildlifePhotoCalculator Domain Logic Tests', () {
    late SpeciesProfile roeDeer;
    late SpeciesProfile kingfisher;

    setUp(() {
      roeDeer = SpeciesProfile.fromJson({
        'id': 'roe_deer',
        'name': 'Rehwild',
        'scientificName': 'Capreolus capreolus',
        'category': 'ungulate',
        'shortDescription': 'Standorttreuer Paarhufer.',
        'accentColorHex': '#10B981',
        'behavior': {
          'scentSensitivityMeters': 250,
          'scentConeAngleDegrees': 45,
          'primaryActivityPeriods': ['dawn', 'dusk'],
          'barometerDropSensitivity': 0.75,
          'maxToleratedWindSpeedKmh': 40,
          'flightDistanceMeters': 80,
        },
        'openData': {
          'bodySize': 'Schulterhöhe 65–75 cm',
        },
      });

      kingfisher = SpeciesProfile.fromJson({
        'id': 'kingfisher',
        'name': 'Eisvogel',
        'scientificName': 'Alcedo atthis',
        'category': 'waterfowl',
        'shortDescription': 'Fliegender Edelstein am Bach.',
        'accentColorHex': '#06B6D4',
        'behavior': {
          'scentSensitivityMeters': 0,
          'scentConeAngleDegrees': 0,
          'primaryActivityPeriods': ['dawn', 'day'],
          'barometerDropSensitivity': 0.35,
          'maxToleratedWindSpeedKmh': 30,
          'flightDistanceMeters': 35,
        },
        'openData': {
          'bodySize': 'Körperlänge 16–18 cm',
        },
      });
    });

    test('Roe deer framing analysis identifies safe vs hide recommendations', () {
      // Setup mit kurzem 200 mm Tele an Vollformat:
      // Für ein Reh muss man sehr nah ran -> unterschreitet Fluchtdistanz (80 m)
      const shortGear = PhotoGearProfile(
        focalLengthMm: 200.0,
        maxAperture: 2.8,
        sensorFormat: CameraSensorFormat.fullFrame,
      );

      final shortAnalysis = WildlifePhotoCalculator.calculateFramingAnalysis(
        species: roeDeer,
        gear: shortGear,
      );

      expect(shortAnalysis.flightDistanceMeters, 80.0);
      // Ganzkörperdistanz bei 200mm ist ca. 17-20 m -> weit unter Fluchtdistanz von 80m!
      expect(shortAnalysis.fullBodyDistanceMeters, lessThan(30.0));
      expect(
        shortAnalysis.fullBodyStatus,
        FlightDistanceStatus.hideRecommended,
      );

      // Setup mit 800 mm Supertele an APS-C (1200 mm KB):
      const superTele = PhotoGearProfile(
        focalLengthMm: 800.0,
        maxAperture: 5.6,
        sensorFormat: CameraSensorFormat.apscSonyNikonFuji,
      );

      final superAnalysis = WildlifePhotoCalculator.calculateFramingAnalysis(
        species: roeDeer,
        gear: superTele,
      );

      // Jetzt kann man aus ca. 100 m fotografieren -> außerhalb der 80 m Fluchtdistanz!
      expect(superAnalysis.fullBodyDistanceMeters, greaterThan(80.0));
      expect(superAnalysis.fullBodyStatus, FlightDistanceStatus.safe);
    });

    test('Kingfisher analysis warns that small birds require hides without extreme supertele', () {
      const standardGear = PhotoGearProfile(
        focalLengthMm: 400.0,
        maxAperture: 4.0,
        sensorFormat: CameraSensorFormat.fullFrame,
      );

      final analysis = WildlifePhotoCalculator.calculateFramingAnalysis(
        species: kingfisher,
        gear: standardGear,
      );

      expect(analysis.flightDistanceMeters, 35.0);
      // Für einen 17 cm Eisvogel muss man auf unter 15 m heran
      expect(analysis.fullBodyDistanceMeters, lessThan(35.0));
      expect(analysis.fullBodyStatus, FlightDistanceStatus.hideRecommended);
      expect(analysis.practicalRecommendation, contains('Tarnzelt'));
    });

    test('Shutter guide returns species-adapted recommendations', () {
      const gear = PhotoGearProfile(
        focalLengthMm: 500.0,
        maxAperture: 4.0,
      );

      final birdGuide = WildlifePhotoCalculator.calculateShutterGuide(
        species: kingfisher,
        gear: gear,
      );

      // Eisvogel-Sturztauchgang erfordert 1/3200 – 1/4000s
      expect(birdGuide.actionShutter, contains('1/4000'));
      expect(birdGuide.duskLightAdvice, contains('Lichtstärke'));

      final deerGuide = WildlifePhotoCalculator.calculateShutterGuide(
        species: roeDeer,
        gear: gear,
      );

      expect(deerGuide.restingShutter, contains('1/250'));
    });
  });

  group('PhotoGearService Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Loads default gear when no preferences exist', () async {
      final gear = await PhotoGearService.loadGear();
      expect(gear.focalLengthMm, 400.0);
      expect(gear.maxAperture, 4.0);
      expect(gear.sensorFormat, CameraSensorFormat.fullFrame);
    });

    test('Saves and restores updated gear via ValueNotifier', () async {
      const customGear = PhotoGearProfile(
        lensName: 'Canon 100–500 mm L',
        focalLengthMm: 500.0,
        maxAperture: 7.1,
        sensorFormat: CameraSensorFormat.apscCanon,
        teleconverter: Teleconverter.tc14,
      );

      await PhotoGearService.saveGear(customGear);
      expect(PhotoGearService.gearNotifier.value.focalLengthMm, 500.0);

      final reloaded = await PhotoGearService.loadGear();
      expect(reloaded.lensName, 'Canon 100–500 mm L');
      expect(reloaded.sensorFormat, CameraSensorFormat.apscCanon);
      expect(reloaded.teleconverter, Teleconverter.tc14);
    });
  });

  group('PhotoGearSheet & SpeciesInspectorSheet UX Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PhotoGearService.resetToDefaults();
    });

    testWidgets('PhotoGearSheet renders optical physics summary, presets and switches', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PhotoGearSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header & Physik-Zusammenfassung
      expect(find.text('Foto-Ausrüstung & Optik'), findsOneWidget);
      expect(find.text('Errechnete optische Physik im Feld'), findsOneWidget);
      expect(find.text('KB-Äquivalent'), findsOneWidget);
      expect(find.text('Effektive Blende'), findsOneWidget);

      // Beliebte Presets
      expect(find.text('200–600 mm f/5.6–6.3'), findsOneWidget);
      expect(find.text('100–500 mm f/4.5–7.1'), findsOneWidget);

      // Sensorformate
      expect(find.text('Vollformat / Kleinbild'), findsOneWidget);
      expect(find.text('APS-C (Sony / Nikon / Fuji 1.5x)'), findsOneWidget);

      // Tap Preset 200–600mm
      await tester.tap(find.text('200–600 mm f/5.6–6.3'));
      await tester.pumpAndSettle();

      expect(PhotoGearService.gearNotifier.value.focalLengthMm, 600.0);
    });

    testWidgets('SpeciesInspectorSheet renders Foto-Praxis card with flight distance check', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final species = SpeciesProfile.fromJson({
        'id': 'roe_deer',
        'name': 'Rehwild',
        'scientificName': 'Capreolus capreolus',
        'category': 'ungulate',
        'shortDescription': 'Konzentratselektierer.',
        'accentColorHex': '#10B981',
        'behavior': {
          'scentSensitivityMeters': 250,
          'scentConeAngleDegrees': 45,
          'primaryActivityPeriods': ['dawn', 'dusk'],
          'barometerDropSensitivity': 0.75,
          'maxToleratedWindSpeedKmh': 40,
          'flightDistanceMeters': 80,
        },
        'openData': {
          'bodySize': 'Schulterhöhe 65–75 cm',
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: WildlifeScoutTheme.buildDarkTheme(),
          home: Scaffold(
            body: SpeciesInspectorSheet(
              species: species,
              obfuscatedLat: 51.16,
              obfuscatedLon: 10.45,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Foto-Praxis Bereich muss prominent gerendert sein
      expect(find.text('Foto-Praxis: Fluchtdistanz vs. Fotodistanz'), findsOneWidget);
      expect(find.text('Fluchtdistanz'), findsWidgets);
      expect(find.text('Ganzkörper-Foto'), findsOneWidget);
      expect(find.text('Nahporträt'), findsOneWidget);
      expect(find.text('Optik anpassen'), findsOneWidget);

      // Prüfe Verschlusszeiten für diese Art
      expect(find.text('Empfohlene Verschlusszeiten für diese Art'), findsOneWidget);
      expect(find.text('Ruhend / Äsend'), findsOneWidget);
      expect(find.text('In Bewegung / Ziehend'), findsOneWidget);

      // Verifiziere strikt: Kein Wort "taktisch" in der gesamten neuen Karte!
      expect(find.textContaining('taktisch'), findsNothing);
      expect(find.textContaining('Taktisch'), findsNothing);
    });

    testWidgets('SpeciesInspectorSheet does not render raw OSM tags or engine keywords', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final species = SpeciesProfile.fromJson({
        'id': 'roe_deer',
        'name': 'Rehwild',
        'scientificName': 'Capreolus capreolus',
        'category': 'ungulate',
        'shortDescription': 'Konzentratselektierer.',
        'accentColorHex': '#10B981',
        'behavior': {
          'flightDistanceMeters': 80,
        },
        'habitatRules': {
          'landuseWeights': [
            {'osmTag': 'natural=scrub', 'score': 4.2, 'label': 'Verjüngung & Hecken'},
            {'osmTag': 'landuse=meadow', 'score': 3.5, 'label': 'Kräuterreiche Waldwiese'},
          ],
          'disturbancePenalties': [
            {'osmTag': 'highway=path', 'radiusMeters': 45, 'penaltyScore': -2.5, 'label': 'Spazier-/Wanderpfad'},
            {'osmTag': 'highway=cycleway', 'radiusMeters': 65, 'penaltyScore': -4.0, 'label': 'Radweg'},
          ],
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: WildlifeScoutTheme.buildDarkTheme(),
          home: Scaffold(
            body: SpeciesInspectorSheet(
              species: species,
              obfuscatedLat: 51.16,
              obfuscatedLon: 10.45,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clean German labels are rendered
      expect(find.text('Verjüngung & Hecken'), findsOneWidget);
      expect(find.text('Kräuterreiche Waldwiese'), findsOneWidget);
      expect(find.textContaining('Spazier-/Wanderpfad • Puffer 45m'), findsOneWidget);
      expect(find.textContaining('Radweg • Puffer 65m'), findsOneWidget);

      // Raw technical OSM tags and engine buzzwords are suppressed
      expect(find.textContaining('natural=scrub'), findsNothing);
      expect(find.textContaining('landuse=meadow'), findsNothing);
      expect(find.textContaining('highway=path'), findsNothing);
      expect(find.textContaining('highway=cycleway'), findsNothing);
      expect(find.textContaining('JSON Profile Engine'), findsNothing);
    });
  });
}
