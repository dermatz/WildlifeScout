import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wildlifescout/data/services/app_settings_service.dart';
import 'package:wildlifescout/domain/models/weather_frame.dart';
import 'package:wildlifescout/presentation/widgets/hud_compass_tape.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HudCompassTape Unit & Widget Tests', () {
    test('Calculates correct German cardinal labels', () {
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(0.0), 'N');
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(44.0), 'NO');
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(45.0), 'NO');
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(90.0), 'O');
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(135.0), 'SO');
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(180.0), 'S');
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(225.0), 'SW');
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(270.0), 'W');
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(315.0), 'NW');
      expect(HudCompassTapeStateTestHelper.cardinalForHeading(359.0), 'N');
    });

    testWidgets('Renders HudCompassTape with initial heading and digital badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              height: 100,
              child: HudCompassTape(
                initialHeading: 45.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Digitaler Badge muss 045° NO anzeigen
      expect(find.text('045° NO'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Renders North 000° N correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              height: 100,
              child: HudCompassTape(
                initialHeading: 0.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('000° N'), findsOneWidget);
    });

    testWidgets('Tapping on HudCompassTape triggers onTap callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              height: 100,
              child: HudCompassTape(
                initialHeading: 180.0,
                onTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('180° S'), findsOneWidget);

      await tester.tap(find.byType(HudCompassTape));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('Horizontal drag updates the compass heading smoothly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              height: 100,
              child: HudCompassTape(
                initialHeading: 90.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('090° O'), findsOneWidget);

      // Drag nach links simuliert Drehung nach rechts (Osten wandert nach links)
      await tester.drag(find.byType(HudCompassTape), const Offset(-70, 0));
      await tester.pumpAndSettle();

      // Heading muss sich verändert haben (größer als 90°)
      expect(find.text('090° O'), findsNothing);
    });

    testWidgets('Renders with WeatherFrame wind direction without error', (tester) async {
      final weather = WeatherFrame(
        time: DateTime.now(),
        temperatureCelsius: 12.0,
        windSpeedKmh: 14.0,
        windGustsKmh: 22.0,
        windDirectionDegrees: 45.0, // Nordost
        surfacePressureHpa: 1015.0,
        pressureDelta6hHpa: 0.2,
        cloudCoverPercent: 20,
        precipitationMm: 0.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              height: 100,
              child: HudCompassTape(
                currentWeather: weather,
                initialHeading: 45.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(HudCompassTape), findsOneWidget);
    });

    test('AppSettings includes showHudCompassTape defaulting to true', () {
      const settings = AppSettings();
      expect(settings.showHudCompassTape, isTrue);

      final modified = settings.copyWith(showHudCompassTape: false);
      expect(modified.showHudCompassTape, isFalse);
    });
  });
}

/// Helper zum Testen statischer Logik
class HudCompassTapeStateTestHelper {
  static String cardinalForHeading(double deg) {
    return HudCompassTape.cardinalForHeading(deg);
  }
}
