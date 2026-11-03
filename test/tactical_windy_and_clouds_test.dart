import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildlifescout/data/api/open_meteo_client.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/domain/models/weather_frame.dart';
import 'package:wildlifescout/presentation/widgets/map_layers_sheet.dart';
import 'package:wildlifescout/presentation/widgets/tactical_windy_weather_sheet.dart';

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

  group('WeatherFrame 3-Layer Cloud Stratification & Photometry Tests', () {
    test('Correctly computes stratification summary and photographic light descriptions', () {
      final cirrusFrame = WeatherFrame(
        time: DateTime.now(),
        temperatureCelsius: 14.0,
        windSpeedKmh: 12.0,
        windGustsKmh: 18.0,
        windDirectionDegrees: 240.0,
        surfacePressureHpa: 1015.0,
        pressureDelta6hHpa: -0.5,
        cloudCoverPercent: 50,
        cloudCoverHighPercent: 65,
        cloudCoverMidPercent: 20,
        cloudCoverLowPercent: 10,
        visibilityMeters: 15000.0,
        precipitationMm: 0.0,
      );

      expect(cirrusFrame.cloudStratificationSummary, 'Hoch: 65% • Mittel: 20% • Tief: 10%');
      expect(cirrusFrame.photographicLightQuality, 'Feines Streulicht (Cirren für Abendrot)');
      expect(cirrusFrame.isMistyOrLowCeiling, isFalse);

      final softboxFrame = WeatherFrame(
        time: DateTime.now(),
        temperatureCelsius: 16.0,
        windSpeedKmh: 8.0,
        windGustsKmh: 12.0,
        windDirectionDegrees: 180.0,
        surfacePressureHpa: 1018.0,
        pressureDelta6hHpa: 0.2,
        cloudCoverPercent: 60,
        cloudCoverHighPercent: 30,
        cloudCoverMidPercent: 55,
        cloudCoverLowPercent: 20,
        visibilityMeters: 10000.0,
        precipitationMm: 0.0,
      );

      expect(softboxFrame.photographicLightQuality, 'Natürliche Riesen-Softbox (ideal für Porträts)');

      final stratusFrame = WeatherFrame(
        time: DateTime.now(),
        temperatureCelsius: 8.0,
        windSpeedKmh: 15.0,
        windGustsKmh: 22.0,
        windDirectionDegrees: 310.0,
        surfacePressureHpa: 1008.0,
        pressureDelta6hHpa: -2.1,
        cloudCoverPercent: 95,
        cloudCoverHighPercent: 80,
        cloudCoverMidPercent: 70,
        cloudCoverLowPercent: 85,
        visibilityMeters: 2000.0,
        precipitationMm: 0.0,
      );

      expect(stratusFrame.photographicLightQuality, 'Diffuses Flachlicht (Tiefe Stratusdecke)');
      expect(stratusFrame.isMistyOrLowCeiling, isTrue);
    });

    test('OpenMeteoClient buildOfflineFallbackForecast populates 3 cloud levels', () {
      final fallback = OpenMeteoClient.buildOfflineFallbackForecast();
      expect(fallback, isNotEmpty);
      final first = fallback.first;
      expect(first.cloudCoverPercent, greaterThan(0));
      expect(first.cloudCoverHighPercent, greaterThan(0));
      expect(first.cloudCoverMidPercent, greaterThan(0));
      expect(first.cloudCoverLowPercent, greaterThan(0));
      expect(first.meteorologicalModel, contains('ECMWF'));
    });
  });

  group('TacticalWindyWeatherSheet Widget Tests', () {
    final testWeather = WeatherFrame(
      time: DateTime.now(),
      temperatureCelsius: 12.5,
      windSpeedKmh: 14.0,
      windGustsKmh: 22.0,
      windDirectionDegrees: 220.0,
      surfacePressureHpa: 1014.0,
      pressureDelta6hHpa: -1.2,
      cloudCoverPercent: 55,
      cloudCoverHighPercent: 50,
      cloudCoverMidPercent: 45,
      cloudCoverLowPercent: 15,
      visibilityMeters: 12000.0,
      precipitationMm: 0.0,
    );

    testWidgets('renders tactical header, ECMWF badge, 2km privacy notice and layer tabs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TacticalWindyWeatherSheet(
              coordinate: const LatLng(51.23841, 7.45192),
              currentWeather: testWeather,
              initialMode: WindyOverlayMode.clouds,
            ),
          ),
        ),
      );

      await tester.pump();

      // Header and Badges
      expect(find.text('Atmosphärischer Wolken- & Windfilm'), findsOneWidget);
      expect(find.text('ECMWF LEITMODELL'), findsOneWidget);
      expect(find.text('• 📍 Spot sichtbar'), findsOneWidget);

      // Layer tabs
      expect(find.text('Wolken & Wind'), findsOneWidget);
      expect(find.text('Windfeld & Böen'), findsOneWidget);
      expect(find.text('Satellit (IR)'), findsOneWidget);
      expect(find.text('Regen & Radar'), findsOneWidget);

      // Zoom & Spot-Pin controls
      expect(find.text('Zoom:'), findsOneWidget);
      expect(find.text('Revier (10)'), findsOneWidget);
      expect(find.text('Nahfeld (11)'), findsOneWidget);
      expect(find.text('Spot: An'), findsOneWidget);

      // Cloud stratification inspector
      expect(find.text('Fotografisches Wolkenprofil (3 Schichten)'), findsOneWidget);
      expect(find.text('Hohe Cirren'), findsOneWidget);
      expect(find.text('Mittlere Wolken'), findsOneWidget);
      expect(find.text('Tiefer Stratus'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget); // High
      expect(find.text('45%'), findsOneWidget); // Mid
      expect(find.text('15%'), findsOneWidget); // Low

      // Light Quality badge
      expect(find.text('Natürliche Riesen-Softbox (ideal für Porträts)'), findsOneWidget);

      // Fullscreen / External launch action
      expect(find.text('Vollbild'), findsOneWidget);
    });

    testWidgets('switching layer mode updates description and selection', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TacticalWindyWeatherSheet(
              coordinate: const LatLng(51.23841, 7.45192),
              currentWeather: testWeather,
              initialMode: WindyOverlayMode.clouds,
            ),
          ),
        ),
      );

      await tester.pump();

      // Tap on "Windfeld & Böen"
      await tester.tap(find.text('Windfeld & Böen'));
      await tester.pump();

      expect(
        find.text('Strömungsvektoren & Windstärken mit Farbgradienten'),
        findsOneWidget,
      );

      // Tap on "Nahfeld (11)" zoom
      await tester.tap(find.text('Nahfeld (11)'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Nahfeld (11)'), findsOneWidget);

      // Toggle Spot-Pin off (DSGVO anonym)
      await tester.tap(find.text('Spot: An'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Spot: Aus'), findsOneWidget);
      expect(find.text('• 🛡️ 2 km DSGVO-Raster'), findsOneWidget);
    });
  });

  group('MapLayersSheet Tactical Großwetter- & Windfilm Card Integration Tests', () {
    testWidgets('renders Großwetter- & Windfilm card and triggers callback on tap', (tester) async {
      bool windyOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapLayersSheet(
              primarySpecies: _makeTestSpecies(),
              habitatCount: 5,
              trailCount: 3,
              useSatelliteLayer: true,
              showHabitatLayer: true,
              showDisturbanceLayer: false,
              showRainRadarLayer: false,
              showScentCone: true,
              isNightVisionRedMode: false,
              onChangedSatellite: (_) {},
              onChangedHabitat: (_) {},
              onChangedDisturbance: (_) {},
              onChangedRainRadar: (_) {},
              onChangedScentCone: (_) {},
              onChangedNightVision: (_) {},
              onScanCurrentMapCenter: () {},
              onOpenTacticalWindy: () {
                windyOpened = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Großwetter- & Windfilm'), findsOneWidget);
      expect(find.text('ECMWF'), findsOneWidget);
      expect(find.text('Wolkenbänder & animierte Windpartikel (Windy)'), findsOneWidget);

      // Tap Öffnen
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();

      expect(windyOpened, isTrue);
    });
  });
}
