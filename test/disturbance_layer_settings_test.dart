import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildlifescout/data/services/app_settings_service.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/presentation/widgets/app_settings_sheet.dart';
import 'package:wildlifescout/presentation/widgets/map_layers_sheet.dart';

SpeciesProfile _makeTestSpecies() {
  return const SpeciesProfile(
    id: 'roe_deer',
    name: 'Rehwild',
    scientificName: 'Capreolus capreolus',
    category: SpeciesCategory.ungulate,
    shortDescription: 'Schalenwild des Waldrandes',
    accentColor: Color(0xFF10B981),
    behavior: BehaviorProfile(
      scentSensitivityMeters: 250.0,
      scentConeAngleDegrees: 45,
      primaryActivityPeriods: [ActivityPeriod.dawn, ActivityPeriod.dusk],
      barometerDropSensitivity: 0.5,
      maxToleratedWindSpeedKmh: 45,
      flightDistanceMeters: 60.0,
    ),
    openData: SpeciesOpenData(
      taxonomy: 'Familie Test',
      bodyWeight: '20 kg',
      conservationStatus: 'LC',
    ),
    behaviorTraits: [],
    habitatRules: HabitatRules(
      edgePreferences: [],
      landuseWeights: [],
      disturbancePenalties: [],
      minContiguousAreaHectares: 1.0,
    ),
    fieldTips: ['Test-Tipp'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Disturbance Layer (Rot markierte Wege) Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Default setting is false (off by default)', () {
      const defaultSettings = AppSettings();
      expect(defaultSettings.showDisturbanceLayer, isFalse);
      expect(AppSettings.defaultShowDisturbanceLayer, isFalse);
    });

    test('AppSettingsService loads default false and persists true when switched on', () async {
      SharedPreferences.setMockInitialValues({});
      var settings = await AppSettingsService.loadSettings();
      expect(settings.showDisturbanceLayer, isFalse);

      // Persist enabled
      await AppSettingsService.setShowDisturbanceLayer(true);
      settings = await AppSettingsService.loadSettings();
      expect(settings.showDisturbanceLayer, isTrue);

      // Simulates app restart with existing SharedPreferences
      final reloadedSettings = await AppSettingsService.loadSettings();
      expect(reloadedSettings.showDisturbanceLayer, isTrue);

      // Persist disabled
      await AppSettingsService.setShowDisturbanceLayer(false);
      final finalSettings = await AppSettingsService.loadSettings();
      expect(finalSettings.showDisturbanceLayer, isFalse);
    });

    testWidgets('MapLayersSheet shows disturbance toggle and triggers callback', (tester) async {
      bool? toggledVal;
      final dummySpecies = _makeTestSpecies();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapLayersSheet(
              primarySpecies: dummySpecies,
              habitatCount: 5,
              trailCount: 12,
              useSatelliteLayer: true,
              showHabitatLayer: true,
              showDisturbanceLayer: false,
              showRainRadarLayer: false,
              showScentCone: true,
              isNightVisionRedMode: false,
              onChangedSatellite: (_) {},
              onChangedHabitat: (_) {},
              onChangedDisturbance: (val) {
                toggledVal = val;
              },
              onChangedRainRadar: (_) {},
              onChangedScentCone: (_) {},
              onChangedNightVision: (_) {},
              onScanCurrentMapCenter: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('OSM Störwege & Pufferzonen (12)'), findsOneWidget);
      expect(
        find.text('Rot markierte Wanderpfade, Rad- & Forstwege inkl. Störradius'),
        findsOneWidget,
      );

      // Tap row to toggle
      await tester.tap(find.text('OSM Störwege & Pufferzonen (12)'));
      await tester.pumpAndSettle();

      expect(toggledVal, isTrue);
    });

    testWidgets('AppSettingsSheet allows toggling Rot markierte Störwege (OSM) persistently', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSettingsSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand Karten & Sensoren
      await tester.tap(find.text('Karten & Sensoren'));
      await tester.pumpAndSettle();

      expect(find.text('Rot markierte Störwege (OSM)'), findsOneWidget);
      expect(
        find.text('Wanderpfade, Forstwege und Störradien rot auf der Karte hervorheben.'),
        findsOneWidget,
      );

      // Toggle switch
      await tester.tap(find.text('Rot markierte Störwege (OSM)'));
      await tester.pumpAndSettle();

      final reloaded = await AppSettingsService.loadSettings();
      expect(reloaded.showDisturbanceLayer, isTrue);
    });

    testWidgets('MapLayersSheet shows weather rain radar toggle and triggers callback', (tester) async {
      bool? toggledRainRadar;
      final dummySpecies = _makeTestSpecies();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapLayersSheet(
              primarySpecies: dummySpecies,
              habitatCount: 3,
              trailCount: 7,
              useSatelliteLayer: true,
              showHabitatLayer: true,
              showDisturbanceLayer: false,
              showRainRadarLayer: false,
              showScentCone: true,
              isNightVisionRedMode: false,
              onChangedSatellite: (_) {},
              onChangedHabitat: (_) {},
              onChangedDisturbance: (_) {},
              onChangedRainRadar: (val) {
                toggledRainRadar = val;
              },
              onChangedScentCone: (_) {},
              onChangedNightVision: (_) {},
              onScanCurrentMapCenter: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DWD Niederschlags- & Gewitterradar'), findsOneWidget);
      expect(
        find.text('Amtlicher Live-Radarfilm des Deutschen Wetterdienstes (Open Data / WMS)'),
        findsOneWidget,
      );

      // Tap row to toggle
      await tester.tap(find.text('DWD Niederschlags- & Gewitterradar'));
      await tester.pumpAndSettle();

      expect(toggledRainRadar, isTrue);
    });

    test('AppSettingsService persists setShowRainRadarLayer', () async {
      SharedPreferences.setMockInitialValues({});
      var settings = await AppSettingsService.loadSettings();
      expect(settings.showRainRadarLayer, isFalse);

      await AppSettingsService.setShowRainRadarLayer(true);
      settings = await AppSettingsService.loadSettings();
      expect(settings.showRainRadarLayer, isTrue);

      await AppSettingsService.setShowRainRadarLayer(false);
      settings = await AppSettingsService.loadSettings();
      expect(settings.showRainRadarLayer, isFalse);
    });
  });
}
