import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildlifescout/data/services/app_settings_service.dart';
import 'package:wildlifescout/domain/models/severe_weather_alert.dart';
import 'package:wildlifescout/domain/models/weather_frame.dart';
import 'package:wildlifescout/presentation/widgets/app_settings_sheet.dart';
import 'package:wildlifescout/presentation/widgets/severe_weather_alert_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SevereWeatherEvaluator Tests', () {
    final now = DateTime(2026, 11, 1, 14, 0);

    WeatherFrame buildFrame({
      int hourOffset = 0,
      double windSpeed = 15.0,
      double windGusts = 25.0,
      double precip = 0.0,
      int weatherCode = 0,
      double pressureDelta = -0.5,
    }) {
      return WeatherFrame(
        time: now.add(Duration(hours: hourOffset)),
        temperatureCelsius: 12.0,
        windSpeedKmh: windSpeed,
        windGustsKmh: windGusts,
        windDirectionDegrees: 220.0,
        surfacePressureHpa: 1013.0,
        pressureDelta6hHpa: pressureDelta,
        cloudCoverPercent: 50,
        precipitationMm: precip,
        weatherCode: weatherCode,
      );
    }

    test('returns null when warning is disabled in AppSettings', () {
      final forecast = [
        buildFrame(windGusts: 90.0, weatherCode: 95),
      ];

      final alert = SevereWeatherEvaluator.evaluateActiveAnsitz(
        forecast: forecast,
        activeForecastIndex: 0,
        settings: const AppSettings(warnSevereWeatherDuringAnsitz: false),
      );

      expect(alert, isNull);
    });

    test('detects severe thunderstorm (WMO 95) with danger level and safety advice', () {
      final forecast = [
        buildFrame(hourOffset: 0, windGusts: 30.0),
        buildFrame(hourOffset: 1, weatherCode: 95, windGusts: 65.0, precip: 15.0),
      ];

      final alert = SevereWeatherEvaluator.evaluateActiveAnsitz(
        forecast: forecast,
        activeForecastIndex: 0,
        settings: const AppSettings(warnSevereWeatherDuringAnsitz: true),
      );

      expect(alert, isNotNull);
      expect(alert!.type, SevereWeatherType.thunderstorm);
      expect(alert.severity, SevereWeatherSeverity.danger);
      expect(alert.isDanger, isTrue);
      expect(alert.hoursUntilEvent, 1);
      expect(alert.safetyRecommendation, contains('Offenes Gelände sofort verlassen'));
    });

    test('detects extreme storm gusts (>= 75 km/h, Bft 9) with danger level', () {
      final forecast = [
        buildFrame(hourOffset: 0, windGusts: 78.0),
      ];

      final alert = SevereWeatherEvaluator.evaluateActiveAnsitz(
        forecast: forecast,
        activeForecastIndex: 0,
        settings: const AppSettings(warnSevereWeatherDuringAnsitz: true),
      );

      expect(alert, isNotNull);
      expect(alert!.type, SevereWeatherType.stormGusts);
      expect(alert.severity, SevereWeatherSeverity.danger);
      expect(alert.headline, contains('78 km/h'));
      expect(alert.safetyRecommendation, contains('Fotosession unverzüglich abbrechen'));
    });

    test('detects moderate storm gusts according to custom threshold', () {
      final forecast = [
        buildFrame(hourOffset: 0, windGusts: 55.0),
      ];

      // Standard-Schwelle ist 60 km/h -> kein Alarm bei 55 km/h
      final alertDefault = SevereWeatherEvaluator.evaluateActiveAnsitz(
        forecast: forecast,
        activeForecastIndex: 0,
        settings: const AppSettings(
          warnSevereWeatherDuringAnsitz: true,
          severeWeatherWindGustThresholdKmh: 60.0,
        ),
      );
      expect(alertDefault, isNull);

      // Mit sensiblerer Schwelle (50 km/h) -> Alarm wird ausgelöst!
      final alertSensitive = SevereWeatherEvaluator.evaluateActiveAnsitz(
        forecast: forecast,
        activeForecastIndex: 0,
        settings: const AppSettings(
          warnSevereWeatherDuringAnsitz: true,
          severeWeatherWindGustThresholdKmh: 50.0,
        ),
      );
      expect(alertSensitive, isNotNull);
      expect(alertSensitive!.type, SevereWeatherType.stormGusts);
      expect(alertSensitive.severity, SevereWeatherSeverity.warning);
      expect(alertSensitive.headline, contains('55 km/h'));
    });

    test('detects heavy rain (>= 8.0 mm/h)', () {
      final forecast = [
        buildFrame(hourOffset: 0, precip: 11.5),
      ];

      final alert = SevereWeatherEvaluator.evaluateActiveAnsitz(
        forecast: forecast,
        activeForecastIndex: 0,
        settings: const AppSettings(warnSevereWeatherDuringAnsitz: true),
      );

      expect(alert, isNotNull);
      expect(alert!.type, SevereWeatherType.heavyRain);
      expect(alert.severity, SevereWeatherSeverity.warning);
      expect(alert.headline, contains('11.5 mm/h'));
    });

    test('detects rapid barometric pressure drop front with high gusts', () {
      final forecast = [
        buildFrame(hourOffset: 0, pressureDelta: -3.8, windGusts: 48.0),
      ];

      final alert = SevereWeatherEvaluator.evaluateActiveAnsitz(
        forecast: forecast,
        activeForecastIndex: 0,
        settings: const AppSettings(warnSevereWeatherDuringAnsitz: true),
      );

      expect(alert, isNotNull);
      expect(alert!.type, SevereWeatherType.squallFront);
    });
  });

  group('AppSettings Severe Weather Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Loads default severe weather settings', () async {
      final settings = await AppSettingsService.loadSettings();

      expect(settings.warnSevereWeatherDuringAnsitz, isTrue);
      expect(settings.severeWeatherWindGustThresholdKmh, 60.0);
      expect(settings.severeWeatherSoundAndHaptics, isTrue);
      expect(settings.showRainRadarLayer, isFalse);
    });

    test('Persists updated severe weather and rain radar settings', () async {
      await AppSettingsService.saveSettings(
        const AppSettings(
          warnSevereWeatherDuringAnsitz: false,
          severeWeatherWindGustThresholdKmh: 75.0,
          severeWeatherSoundAndHaptics: false,
          showRainRadarLayer: true,
        ),
      );

      final loaded = await AppSettingsService.loadSettings();
      expect(loaded.warnSevereWeatherDuringAnsitz, isFalse);
      expect(loaded.severeWeatherWindGustThresholdKmh, 75.0);
      expect(loaded.severeWeatherSoundAndHaptics, isFalse);
      expect(loaded.showRainRadarLayer, isTrue);
    });

    test('setWarnSevereWeather helper persists toggle', () async {
      await AppSettingsService.setWarnSevereWeather(false);
      final loaded = await AppSettingsService.loadSettings();
      expect(loaded.warnSevereWeatherDuringAnsitz, isFalse);

      await AppSettingsService.setWarnSevereWeather(true);
      final reloaded = await AppSettingsService.loadSettings();
      expect(reloaded.warnSevereWeatherDuringAnsitz, isTrue);
    });

    test('setSevereWeatherWindGustThresholdKmh clamps and persists', () async {
      await AppSettingsService.setSevereWeatherWindGustThresholdKmh(50.0);
      final loaded = await AppSettingsService.loadSettings();
      expect(loaded.severeWeatherWindGustThresholdKmh, 50.0);
    });
  });

  group('AppSettingsSheet & SevereWeatherAlertSheet UX Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders Unwetter-Warnsystem section and controls in AppSettingsSheet', (tester) async {
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

      expect(find.text('Unwetter-Warnung am Fotospot'), findsOneWidget);
      // Accordion öffnen
      await tester.tap(find.text('Unwetter-Warnung am Fotospot'));
      await tester.pumpAndSettle();

      expect(find.text('Vor Unwetter bei aktiver Fotosession warnen'), findsOneWidget);
      expect(find.text('Böenschwelle für Sturmwarnung'), findsOneWidget);
      expect(find.text('Probe-Alarm testen'), findsOneWidget);

      // Preset chip auswählen (75 km/h)
      final chip75 = find.widgetWithText(ChoiceChip, '75 km/h (Bft 9 Sturm)');
      expect(chip75, findsOneWidget);
      await tester.tap(chip75);
      await tester.pumpAndSettle();

      final settings = await AppSettingsService.loadSettings();
      expect(settings.severeWeatherWindGustThresholdKmh, 75.0);
    });

    testWidgets('Probe-Alarm button opens SevereWeatherAlertSheet with safety protocol', (tester) async {
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

      // Accordion öffnen
      await tester.tap(find.text('Unwetter-Warnung am Fotospot'));
      await tester.pumpAndSettle();

      // Scrollen zum Probe-Alarm Button
      final testBtn = find.text('Probe-Alarm testen');
      await tester.ensureVisible(testBtn);
      await tester.tap(testBtn);
      await tester.pumpAndSettle();

      // SevereWeatherAlertSheet modal ist geöffnet
      expect(find.byType(SevereWeatherAlertSheet), findsOneWidget);
      expect(find.text('PROBE-ALARM'), findsOneWidget);
      expect(find.text('Sicherheits-Protokoll Wald & Fotospot'), findsOneWidget);
      expect(find.text('Probe-Alarm schließen'), findsOneWidget);

      // Schließen antippen
      await tester.tap(find.text('Probe-Alarm schließen'));
      await tester.pumpAndSettle();

      expect(find.byType(SevereWeatherAlertSheet), findsNothing);
    });
  });
}
