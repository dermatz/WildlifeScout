import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildlifescout/presentation/screens/field_map_screen.dart';
import 'package:wildlifescout/presentation/widgets/app_settings_sheet.dart';
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

      final toolsTriggerFinder = find.byTooltip(
          'Ansitz-Tools (Witterungs-Kompass & Sensor-Optik)');
      expect(toolsTriggerFinder, findsOneWidget);
      expect(find.byIcon(Icons.sensors_rounded), findsOneWidget);

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

      // 4. Tap Tools trigger: Expands tools cluster
      await tester.tap(toolsTriggerFinder);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Tools sub-buttons are visible (with official compass icon and optics reticle icon)
      expect(
        find.descendant(
          of: find.byType(AnimatedSize),
          matching: find.byIcon(Icons.explore_rounded),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.center_focus_strong_rounded), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) =>
            w is Tooltip &&
            (w.message?.contains('Witterungs- & Wind-Kompass') ?? false)),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) =>
            w is Tooltip && (w.message?.contains('Optik- & Sensor-Setup') ?? false)),
        findsOneWidget,
      );

      // 5. Accordion: Tapping Navigation trigger toggles away Tools and opens Navigation
      await tester.tap(navTriggerFinder);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Tools sub-buttons are collapsed
      expect(
        find.byWidgetPredicate((w) =>
            w is Tooltip &&
            (w.message?.contains('Witterungs- & Wind-Kompass') ?? false)),
        findsNothing,
      );
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
  });
}
