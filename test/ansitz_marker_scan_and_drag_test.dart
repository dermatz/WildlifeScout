import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildlifescout/core/theme/wildlifescout_theme.dart';
import 'package:wildlifescout/presentation/screens/field_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ansitz Marker Scan Symbol & Drag Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'wildlifescout_last_user_lat_v1': 51.1657,
        'wildlifescout_last_user_lon_v1': 10.4515,
        'wildlifescout_last_user_title_v1': 'Test Revier',
        'wildlifescout_auto_center_gps': false,
        'wildscout_warn_severe_weather_v1': false,
      });
    });

    testWidgets(
        'Ansitz marker renders radar scan symbol instead of camera icon and tapping initiates scan',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: WildlifeScoutTheme.buildDarkTheme(),
          home: const Scaffold(
            body: FieldMapScreen(),
          ),
        ),
      );

      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('WILDLIFESCOUT').evaluate().isNotEmpty) break;
      }

      // Das Kamera-Symbol darf auf dem Ansitzmarker nicht mehr existieren
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);

      // Stattdessen wird das Radar-Scan-Symbol gerendert
      final radarFinder = find.byIcon(Icons.radar_rounded);
      expect(radarFinder, findsWidgets);

      // Antippen des Pins mit dem Radar-Scan-Symbol löst Neuscan aus
      await tester.tap(radarFinder.first);
      await tester.pump();

      // "SCANNT..." Badge ist aktiv
      expect(find.text('SCANNT...'), findsOneWidget);

      // Radar-Sweep-Timer von 1,5s ablaufen lassen
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets(
        'Moving/tapping within calculated territory moves marker without triggering reload',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: WildlifeScoutTheme.buildDarkTheme(),
          home: const Scaffold(
            body: FieldMapScreen(),
          ),
        ),
      );

      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('WILDLIFESCOUT').evaluate().isNotEmpty) break;
      }

      // Initialen Scan abschließen lassen
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('SCANNT...'), findsNothing);

      // Tippe auf die Karte in der Nähe des Zentrums (innerhalb des berechneten Sektors)
      await tester.tapAt(const Offset(220, 420));
      await tester.pump();

      // Es darf KEIN neuer Scan ausgelöst werden (kein "SCANNT...")
      expect(find.text('SCANNT...'), findsNothing);
    });
  });
}
