import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildlifescout/data/services/app_settings_service.dart';
import 'package:wildlifescout/presentation/widgets/app_settings_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettingsSheet Modern Accordion UX Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Renders all 5 accordion list points with summary badges', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSettingsSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check all 5 accordion titles are present
      expect(find.text('Fotogebiet & Umkreissuche'), findsOneWidget);
      expect(find.text('Unwetter-Warnung am Fotospot'), findsOneWidget);
      expect(find.text('Karten & Sensoren'), findsOneWidget);
      expect(find.text('Einheiten & Taktik-Format'), findsOneWidget);
      expect(find.text('Datenschutz & Speicher'), findsOneWidget);

      // Check "Alle aufklappen / zuklappen" control is present
      expect(find.text('Alle aufklappen'), findsOneWidget);
    });

    testWidgets('Tapping accordion headers expands and collapses cards smoothly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSettingsSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially, Karten & Sensoren (index 2) is collapsed
      expect(find.text('Blickrichtung & Peilstrahl'), findsNothing);

      // Tap on Karten & Sensoren header
      await tester.tap(find.text('Karten & Sensoren'));
      await tester.pumpAndSettle();

      // Now it is expanded
      expect(find.text('Blickrichtung & Peilstrahl'), findsOneWidget);
      expect(find.text('Witterungs- & Windkegel'), findsOneWidget);

      // Tap again to collapse it
      await tester.tap(find.text('Karten & Sensoren'));
      await tester.pumpAndSettle();

      expect(find.text('Blickrichtung & Peilstrahl'), findsNothing);
    });

    testWidgets('Toggle all sections button opens and closes all 5 accordions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSettingsSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Alle aufklappen"
      await tester.tap(find.text('Alle aufklappen'));
      await tester.pumpAndSettle();

      // All 5 sections must be expanded now
      expect(find.text('Blickrichtung & Peilstrahl'), findsOneWidget);
      expect(find.text('Wind-Geschwindigkeitseinheit'), findsOneWidget);
      expect(find.text('Spot-Tresor (SpotVault)'), findsOneWidget);
      expect(find.text('Alle zuklappen'), findsOneWidget);

      // Tap "Alle zuklappen"
      await tester.tap(find.text('Alle zuklappen'));
      await tester.pumpAndSettle();

      // All sections collapsed
      expect(find.text('Blickrichtung & Peilstrahl'), findsNothing);
      expect(find.text('Wind-Geschwindigkeitseinheit'), findsNothing);
      expect(find.text('Alle aufklappen'), findsOneWidget);
    });

    testWidgets('Updates and persists tactical units (Beaufort & Imperial) in expanded accordion', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSettingsSheet(
              onSettingsChanged: () => changed++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand Einheiten & Taktik-Format
      await tester.tap(find.text('Einheiten & Taktik-Format'));
      await tester.pumpAndSettle();

      // Tap Beaufort unit
      await tester.tap(find.text('Beaufort (Bft)'));
      await tester.pumpAndSettle();

      // Tap Imperial distance unit
      await tester.tap(find.text('Imperial (mi / yd)'));
      await tester.pumpAndSettle();

      expect(changed, greaterThanOrEqualTo(2));

      final settings = await AppSettingsService.loadSettings();
      expect(settings.windSpeedUnit, 'bft');
      expect(settings.distanceUnit, 'imperial');
    });

    testWidgets('Toggles Compass Heading Beam and Wind Scent Cone in expanded accordion', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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

      // Toggle Compass Beam switch
      final compassSwitch = find.widgetWithText(
        SwitchListTile,
        'Blickrichtung & Peilstrahl',
      );
      expect(compassSwitch, findsOneWidget);
      await tester.tap(compassSwitch);
      await tester.pumpAndSettle();

      var settings = await AppSettingsService.loadSettings();
      expect(settings.showCompassHeadingBeam, isFalse);

      // Toggle Wind Scent Cone switch
      final scentSwitch = find.widgetWithText(
        SwitchListTile,
        'Witterungs- & Windkegel',
      );
      expect(scentSwitch, findsOneWidget);
      await tester.tap(scentSwitch);
      await tester.pumpAndSettle();

      settings = await AppSettingsService.loadSettings();
      expect(settings.showWindScentCone, isFalse);
    });

    testWidgets('Reset to defaults restores all original preferences and triggers snackbar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Pre-set customized values
      await AppSettingsService.saveSettings(
        const AppSettings(
          searchRadiusKm: 120.0,
          windSpeedUnit: 'bft',
          showCompassHeadingBeam: false,
          warnSevereWeatherDuringAnsitz: false,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSettingsSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Reset button
      final resetButton = find.text('Auf Standardwerte zurücksetzen (50 km)');
      expect(resetButton, findsOneWidget);
      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      expect(find.text('Einstellungen auf Standardwerte zurückgesetzt.'), findsOneWidget);

      final resetSettings = await AppSettingsService.loadSettings();
      expect(resetSettings.searchRadiusKm, 50.0);
      expect(resetSettings.windSpeedUnit, 'kmh');
      expect(resetSettings.showCompassHeadingBeam, isTrue);
      expect(resetSettings.warnSevereWeatherDuringAnsitz, isTrue);
    });
  });
}
