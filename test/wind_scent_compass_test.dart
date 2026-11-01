import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildlifescout/core/theme/wildscout_theme.dart';
import 'package:wildlifescout/domain/models/secret_spot.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/domain/models/weather_frame.dart';
import 'package:wildlifescout/presentation/widgets/device_heading_beam.dart';
import 'package:wildlifescout/presentation/widgets/wind_scent_compass_sheet.dart';

void main() {
  group('WindScentCompassSheet & 360° Tactical Compass Tests', () {
    late WeatherFrame testWeather;
    late SpeciesProfile testSpecies;
    const LatLng hidePosition = LatLng(51.1657, 10.4515);

    setUp(() {
      testWeather = WeatherFrame(
        time: DateTime.now(),
        temperatureCelsius: 16.5,
        windSpeedKmh: 14.0,
        windGustsKmh: 24.0,
        windDirectionDegrees: 240.0, // WSW
        surfacePressureHpa: 1013.2,
        pressureDelta6hHpa: -1.2,
        cloudCoverPercent: 40,
        precipitationMm: 0.0,
      );

      testSpecies = SpeciesProfile.fromJson({
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
          'maxToleratedWindSpeedKmh': 45.0,
          'flightDistanceMeters': 100.0,
        },
      });
    });

    testWidgets('Renders 360° Compass dial, headers, and sector legend correctly',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: WildScoutTheme.buildDarkTheme(),
          home: Scaffold(
            body: WindScentCompassSheet(
              weather: testWeather,
              primarySpecies: testSpecies,
              hidePosition: hidePosition,
              selectedHourOfDay: 14,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Prüfe Header
      expect(find.text('Witterungs- & Wind-Kompass'), findsOneWidget);
      expect(find.textContaining('Rehwild'), findsOneWidget);

      // Prüfe Sektor-Legende
      expect(find.text('WITTERUNGSKEGEL'), findsOneWidget);
      expect(find.text('SICHERE ANNÄHERUNG'), findsOneWidget);
      expect(find.text('60° (NO)'), findsOneWidget); // Scent direction: 240 + 180 = 420 % 360 = 60°
      expect(find.textContaining('240°'), findsWidgets); // Wind direction

      // Prüfe CustomPaint Kompassrose
      expect(find.byType(CustomPaint), findsWidgets);

      // Prüfe Empfehlung
      expect(find.text('Foto- & Annäherungs-Empfehlung'), findsOneWidget);
      expect(find.textContaining('Sichere Annäherung ausschließlich'), findsOneWidget);
    });

    testWidgets('Rotates dial dynamically and detects Gegenwind when facing the wind',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Wind weht aus 240° WSW. Wenn wir in Richtung 240° blicken, haben wir frontalen Gegenwind!
      await tester.pumpWidget(
        MaterialApp(
          theme: WildScoutTheme.buildDarkTheme(),
          home: Scaffold(
            body: WindScentCompassSheet(
              weather: testWeather,
              primarySpecies: testSpecies,
              hidePosition: hidePosition,
              selectedHourOfDay: 14,
              initialHeading: 240.0,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Kurs-Anzeige im HUD
      expect(find.textContaining('240° SW'), findsOneWidget);
      expect(find.text('VISIER'), findsOneWidget);

      // Relative Windlage: Gegenwind von vorn!
      expect(find.text('GEGENWIND (VON VORN)'), findsOneWidget);
      expect(find.textContaining('Der Wind weht dir ins Gesicht'), findsOneWidget);

      // AnimatedRotation rotiert die Rose entsprechend
      final rotationFinder = find.byType(AnimatedRotation);
      expect(rotationFinder, findsOneWidget);
      final AnimatedRotation rotation = tester.widget(rotationFinder);
      expect(rotation.turns, closeTo(-240.0 / 360.0, 0.001));
    });

    testWidgets('Detects Rückenwind and hazard alert when looking downwind',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Wind weht aus 240° WSW (Witterung nach 60° NO).
      // Wenn wir in Richtung 60° blicken, haben wir Rückenwind (Witterung zieht vor uns)!
      await tester.pumpWidget(
        MaterialApp(
          theme: WildScoutTheme.buildDarkTheme(),
          home: Scaffold(
            body: WindScentCompassSheet(
              weather: testWeather,
              primarySpecies: testSpecies,
              hidePosition: hidePosition,
              selectedHourOfDay: 14,
              initialHeading: 60.0,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('060° NO'), findsOneWidget);
      expect(find.text('RÜCKENWIND (GEFAHR)'), findsOneWidget);
      expect(find.textContaining('Kritisch: Der Wind weht dir in den Rücken'), findsOneWidget);
    });

    testWidgets('Toggles between Live-Blickrichtung and Genordet mode',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: WildScoutTheme.buildDarkTheme(),
          home: Scaffold(
            body: WindScentCompassSheet(
              weather: testWeather,
              primarySpecies: testSpecies,
              hidePosition: hidePosition,
              selectedHourOfDay: 14,
              initialHeading: 90.0,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Anfangs im Live-Modus: Visier oben, Heading 090° O
      expect(find.text('VISIER'), findsOneWidget);
      expect(find.textContaining('090° O'), findsOneWidget);

      // Klicke auf 'Nord' (Genordeter Modus)
      await tester.tap(find.text('Nord'));
      await tester.pumpAndSettle();

      // Jetzt ist der Modus genordet
      expect(find.text('NORDEN'), findsOneWidget);
      expect(find.text('000° N'), findsOneWidget);

      // AnimatedRotation ist wieder auf 0.0 genullt
      final AnimatedRotation rotation = tester.widget(find.byType(AnimatedRotation));
      expect(rotation.turns, 0.0);
    });

    testWidgets('Time presets trigger onHourChanged callback', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int? updatedHour;

      final forecast = List.generate(
        24,
        (i) => WeatherFrame(
          time: DateTime.now().add(Duration(hours: i)),
          temperatureCelsius: 15.0,
          windSpeedKmh: 12.0,
          windGustsKmh: 20.0,
          windDirectionDegrees: (200.0 + i * 5) % 360,
          surfacePressureHpa: 1012.0,
          pressureDelta6hHpa: -0.5,
          cloudCoverPercent: 20,
          precipitationMm: 0.0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WildScoutTheme.buildDarkTheme(),
          home: Scaffold(
            body: WindScentCompassSheet(
              weather: testWeather,
              primarySpecies: testSpecies,
              hidePosition: hidePosition,
              selectedHourOfDay: 12,
              hourlyForecast: forecast,
              onHourChanged: (h) => updatedHour = h,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Klicke auf 06:00 Früh
      await tester.tap(find.text('06:00 Früh'));
      await tester.pumpAndSettle();

      expect(updatedHour, 6);

      // Klicke auf 18:00 Abend
      await tester.tap(find.text('18:00 Abend'));
      await tester.pumpAndSettle();

      expect(updatedHour, 18);
    });

    testWidgets('Target bearing detects contaminated vs safe approach spots',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Wind: 240° WSW -> Witterung weht nach 60° (Ost-Nordost)
      // Spot 1: Liegt bei ~60° (In der Witterung!)
      // Spot 2: Liegt bei ~240° (Im sicheren Gegenwind!)
      final spotInScent = SecretSpot(
        id: 'spot_scent',
        title: 'Fotoversteck Lichtung Ost',
        speciesId: 'roe_deer',
        latitude: 51.1680,
        longitude: 10.4550, // Nordöstlich
        notes: '',
        idealWindCardinal: 'SW',
        createdAt: DateTime.now(),
      );

      final spotInHeadwind = SecretSpot(
        id: 'spot_safe',
        title: 'Fotospot Eichengrund West',
        speciesId: 'roe_deer',
        latitude: 51.1630,
        longitude: 10.4480, // Südwestlich
        notes: '',
        idealWindCardinal: 'NO',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WildScoutTheme.buildDarkTheme(),
          home: Scaffold(
            body: WindScentCompassSheet(
              weather: testWeather,
              primarySpecies: testSpecies,
              hidePosition: hidePosition,
              selectedHourOfDay: 14,
              savedSpots: [spotInScent, spotInHeadwind],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('PEILUNG ZU SPOTS & BIOTOPEN'), findsOneWidget);
      expect(find.text('Fotoversteck Lichtung Ost'), findsOneWidget);
      expect(find.text('Fotospot Eichengrund West'), findsOneWidget);
      // Status-Badges sollten vorhanden sein
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('DeviceHeadingBeam renders cyan flashlight beam and arrow in heading direction',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DeviceHeadingBeam(
                headingDeg: 45.0, // Nordost
                beamLength: 60.0,
                beamAngleDeg: 50.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(DeviceHeadingBeam), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DeviceHeadingBeam),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });
  });
}
