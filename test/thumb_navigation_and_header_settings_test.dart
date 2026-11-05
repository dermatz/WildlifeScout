import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildlifescout/domain/models/weather_frame.dart';
import 'package:wildlifescout/presentation/screens/field_map_screen.dart';
import 'package:wildlifescout/presentation/widgets/app_settings_sheet.dart';
import 'package:wildlifescout/presentation/widgets/photo_gear_sheet.dart';
import 'package:wildlifescout/presentation/widgets/field_map/field_thumb_island.dart';
import 'package:wildlifescout/presentation/widgets/location_search_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Header Settings & Thumb Navigation Cluster UX Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'wildlifescout_last_user_lat_v1': 51.1657,
        'wildlifescout_last_user_lon_v1': 10.4515,
        'wildlifescout_last_user_title_v1': 'Test Revier',
        'wildlifescout_auto_center_gps': false,
      });
    });

    testWidgets(
        'Header settings button and thumb navigation accordion clusters function smoothly without overflow',
        (tester) async {
      FlutterErrorDetails? caughtDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caughtDetails = details;
        originalOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FieldMapScreen(),
          ),
        ),
      );

      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('WILDLIFESCOUT').evaluate().isNotEmpty) break;
      }

      expect(caughtDetails, isNull);

      // 1. Header: Settings button right next to species selector
      final settingsFinder = find.byTooltip('App-Einstellungen & Suchradius');
      expect(settingsFinder, findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      await tester.tap(settingsFinder);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(AppSettingsSheet), findsOneWidget);

      // Close settings sheet via Navigator pop
      Navigator.of(tester.element(find.byType(AppSettingsSheet))).pop();
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(AppSettingsSheet), findsNothing);

      // 2. Thumb Dock initial state: Sub-buttons collapsed
      expect(find.byTooltip('Zum aktuellen Standort springen'), findsNothing);
      expect(find.byTooltip('Ort, Waldgebiet oder Koordinaten suchen'), findsNothing);

      final navTriggerFinder =
          find.byTooltip('Navigation & Orte (Standort, Suche, Spots)');
      expect(navTriggerFinder, findsOneWidget);

      final gearTriggerFinder = find.byWidgetPredicate(
        (w) =>
            w is Tooltip &&
            (w.message?.contains('Kamera- & Optik-Setup') ?? false),
      );
      expect(gearTriggerFinder, findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.settings_rounded), findsOneWidget);

      // Beste Chance icon is Stars badge (instead of auto_awesome sparkles)
      expect(find.byIcon(Icons.stars_rounded), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);

      // 3. Tap Navigation cluster: Expands to left with GPS, Suche, Spot-Tresor
      await tester.tap(navTriggerFinder);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final gpsFinder = find.byTooltip('Zum aktuellen Standort springen');
      final searchFinder =
          find.byTooltip('Ort, Waldgebiet oder Koordinaten suchen');
      final vaultFinder = find.byWidgetPredicate((w) =>
          w is Tooltip && (w.message?.contains('Geheimer Spot-Tresor') ?? false));

      expect(gpsFinder, findsOneWidget);
      expect(searchFinder, findsOneWidget);
      expect(vaultFinder, findsOneWidget);

      // Tap search sub-button: opens location search
      await tester.tap(searchFinder);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(LocationSearchSheet), findsOneWidget);

      // Close search sheet via Navigator pop
      Navigator.of(tester.element(find.byType(LocationSearchSheet))).pop();
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(LocationSearchSheet), findsNothing);

      // 4. Tap Camera Gear trigger: Verifies tooltip and camera & settings badge icons
      expect(find.byType(FieldThumbIsland), findsOneWidget);
      expect(gearTriggerFinder, findsOneWidget);

      // 5. Accordion / Navigation toggle
      await tester.tap(navTriggerFinder);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Navigation sub-buttons are visible
      expect(find.byTooltip('Zum aktuellen Standort springen'), findsOneWidget);

      // Tap close trigger
      final navCloseFinder = find.byTooltip('Navigation schließen');
      expect(navCloseFinder, findsOneWidget);
      await tester.tap(navCloseFinder);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byTooltip('Zum aktuellen Standort springen'), findsNothing);

      // 6. Responsive narrow check (320px width)
      tester.view.physicalSize = const Size(320, 640);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(caughtDetails, isNull);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    });

    testWidgets('Map rotation exposes North-reset button when rotated', (tester) async {
      bool resetNorthCalled = false;
      double rotation = 45.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return FieldThumbIsland(
                  activeCluster: ThumbCluster.navigation,
                  onClusterChanged: (_) {},
                  hasHabitatZones: true,
                  savedSpotCount: 2,
                  isLocatingUser: false,
                  isNightVisionRedMode: false,
                  showRainRadarLayer: false,
                  useSatelliteLayer: true,
                  currentWeather: WeatherFrame(
                    time: DateTime.now(),
                    temperatureCelsius: 15.0,
                    precipitationMm: 0.0,
                    windSpeedKmh: 10.0,
                    windGustsKmh: 15.0,
                    windDirectionDegrees: 180,
                    surfacePressureHpa: 1013.2,
                    pressureDelta6hHpa: 0.1,
                    cloudCoverPercent: 20,
                  ),
                  effectiveFocalLengthMm: 400.0,
                  mapRotation: rotation,
                  onResetNorth: () {
                    resetNorthCalled = true;
                    setState(() {
                      rotation = 0.0;
                    });
                  },
                  onApplyBestChance: () {},
                  onOpenLayers: () {},
                  onOpenSpotVault: () {},
                  onOpenLocationSearch: () {},
                  onLocateUser: () {},
                  onOpenPhotoGear: () {},
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final resetNorthFinder = find.byTooltip('Karte nach Norden ausrichten & zentrieren');
      expect(resetNorthFinder, findsOneWidget);

      await tester.tap(resetNorthFinder);
      await tester.pumpAndSettle();

      expect(resetNorthCalled, isTrue);
      expect(find.byTooltip('Karte nach Norden ausrichten & zentrieren'), findsNothing);
    });
  });
}
