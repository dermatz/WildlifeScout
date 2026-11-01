import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildlifescout/data/api/location_search_client.dart';
import 'package:wildlifescout/data/services/app_settings_service.dart';
import 'package:wildlifescout/data/services/nearby_nature_regions_service.dart';
import 'package:wildlifescout/data/services/voice_search_service.dart';
import 'package:wildlifescout/presentation/widgets/app_settings_sheet.dart';
import 'package:wildlifescout/presentation/widgets/location_search_sheet.dart';

class FakeVoiceSearchService extends VoiceSearchService {
  bool fakeAvailable;
  ValueChanged<String>? capturedOnResult;
  VoidCallback? capturedOnListeningFinished;
  ValueChanged<String>? capturedOnError;
  bool isListeningState = false;

  FakeVoiceSearchService({this.fakeAvailable = true});

  @override
  bool get isAvailable => fakeAvailable;

  @override
  bool get isListening => isListeningState;

  @override
  Future<bool> initialize({
    ValueChanged<String>? onError,
    ValueChanged<String>? onStatus,
    bool force = false,
  }) async {
    capturedOnError = onError;
    if (!fakeAvailable) {
      onError?.call('Mikrofon-Berechtigung verweigert.');
    }
    return fakeAvailable;
  }

  @override
  Future<void> startListening({
    required ValueChanged<String> onResult,
    VoidCallback? onListeningFinished,
    ValueChanged<String>? onError,
  }) async {
    capturedOnError = onError;
    if (!fakeAvailable) {
      onError?.call('Mikrofon-Berechtigung verweigert.');
      return;
    }
    isListeningState = true;
    capturedOnResult = onResult;
    capturedOnListeningFinished = onListeningFinished;
  }

  @override
  Future<void> stopListening() async {
    isListeningState = false;
    capturedOnListeningFinished?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationSearchClient & Coordinate Parsing Tests', () {
    late LocationSearchClient client;

    setUp(() {
      client = LocationSearchClient();
    });

    test('parseDirectCoordinates parses various valid GPS formats', () {
      // Standard comma-separated
      final c1 = client.parseDirectCoordinates('51.234, 9.876');
      expect(c1, isNotNull);
      expect(c1!.latitude, closeTo(51.234, 0.0001));
      expect(c1.longitude, closeTo(9.876, 0.0001));

      // German comma decimal separator with space
      final c2 = client.parseDirectCoordinates('51,234 9,876');
      expect(c2, isNotNull);
      expect(c2!.latitude, closeTo(51.234, 0.0001));
      expect(c2.longitude, closeTo(9.876, 0.0001));

      // Semicolon separated
      final c3 = client.parseDirectCoordinates('51.234; 9.876');
      expect(c3, isNotNull);
      expect(c3!.latitude, closeTo(51.234, 0.0001));
      expect(c3.longitude, closeTo(9.876, 0.0001));

      // Cardinal letters
      final c4 = client.parseDirectCoordinates('N 51.234, E 9.876');
      expect(c4, isNotNull);
      expect(c4!.latitude, closeTo(51.234, 0.0001));
      expect(c4.longitude, closeTo(9.876, 0.0001));
    });

    test('parseDirectCoordinates returns null for normal text queries', () {
      expect(client.parseDirectCoordinates('Berlin'), isNull);
      expect(client.parseDirectCoordinates('Schwarzwald Nationalpark'), isNull);
      expect(client.parseDirectCoordinates('Harz'), isNull);
      expect(client.parseDirectCoordinates(''), isNull);
      expect(client.parseDirectCoordinates('123'), isNull);
    });

    test('Direct coordinate search returns immediate GPS-Direkt result',
        () async {
      final results = await client.search('51.500, 10.200');
      expect(results.length, 1);
      expect(results.first.title, 'Direkte GPS-Koordinate');
      expect(results.first.categoryLabel, 'GPS-Direkt');
      expect(results.first.coordinate.latitude, closeTo(51.5, 0.001));
      expect(results.first.coordinate.longitude, closeTo(10.2, 0.001));
    });

    test('Empty search query returns empty list', () async {
      final results = await client.search('   ');
      expect(results, isEmpty);
    });
  });

  group('LocationSearchSheet Widget & UX Tests', () {
    testWidgets(
        'Renders initial suggestions, current location button, and search input',
        (tester) async {
      var usedCurrentLocation = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationSearchSheet(
              onLocationSelected: (_) {},
              onUseCurrentLocation: () => usedCurrentLocation = true,
            ),
          ),
        ),
      );

      // Verify title and input
      expect(find.text('Ort, Wald oder Naturgebiet suchen'), findsOneWidget);
      expect(find.text('Eigenen GPS-Standort laden'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify voice input microphone button
      expect(find.byTooltip('Per Sprache suchen'), findsOneWidget);

      // Verify popular suggestion chips
      expect(find.text('Schwarzwald'), findsOneWidget);
      expect(find.text('Harz'), findsOneWidget);
      expect(find.text('Bayerischer Wald'), findsOneWidget);

      // Verify Apple HIG close button with tooltip
      expect(find.byTooltip('Schließen'), findsOneWidget);

      // Tap current location button
      await tester.tap(find.text('Eigenen GPS-Standort laden'));
      await tester.pumpAndSettle();
      expect(usedCurrentLocation, isTrue);
    });

    testWidgets('Live autocomplete immediately parses direct GPS coordinates',
        (tester) async {
      LocationSearchResult? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationSearchSheet(
              onLocationSelected: (loc) => selectedResult = loc,
              onUseCurrentLocation: () {},
            ),
          ),
        ),
      );

      // Enter GPS coordinates in search field
      final textField = find.byType(TextField);
      await tester.enterText(textField, '52.52, 13.405');
      await tester.pump();
      await tester.pumpAndSettle();

      // Check that direct coordinate result is shown immediately
      expect(find.text('Direkte GPS-Koordinate'), findsOneWidget);
      expect(find.text('GPS-Direkt'), findsOneWidget);
      expect(find.byIcon(Icons.gps_fixed), findsWidgets);

      // Tap the result item
      await tester.tap(find.text('Direkte GPS-Koordinate'));
      await tester.pumpAndSettle();

      expect(selectedResult, isNotNull);
      expect(selectedResult!.coordinate.latitude, closeTo(52.52, 0.001));
      expect(selectedResult!.coordinate.longitude, closeTo(13.405, 0.001));
    });

    testWidgets('Clear button clears search input and resets suggestions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationSearchSheet(
              onLocationSelected: (_) {},
              onUseCurrentLocation: () {},
            ),
          ),
        ),
      );

      // Enter text
      final textField = find.byType(TextField);
      await tester.enterText(textField, '51.12, 10.45');
      await tester.pumpAndSettle();

      expect(find.text('Direkte GPS-Koordinate'), findsOneWidget);
      expect(find.byTooltip('Eingabe löschen'), findsOneWidget);

      // Tap clear button
      await tester.tap(find.byTooltip('Eingabe löschen'));
      await tester.pumpAndSettle();

      // Verify text is cleared and initial suggestions are back
      expect(find.text('Direkte GPS-Koordinate'), findsNothing);
      expect(find.text('Häufige Gebiete & Wälder:'), findsOneWidget);
      expect(find.text('Schwarzwald'), findsOneWidget);
    });

    testWidgets('Voice input activates and inserts recognized speech into search',
        (tester) async {
      final fakeVoice = FakeVoiceSearchService(fakeAvailable: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationSearchSheet(
              onLocationSelected: (_) {},
              onUseCurrentLocation: () {},
              voiceSearchService: fakeVoice,
            ),
          ),
        ),
      );

      // Tap microphone button
      await tester.tap(find.byTooltip('Per Sprache suchen'));
      await tester.pump();

      // Voice recognition active banner should appear
      expect(fakeVoice.isListening, isTrue);
      expect(
        find.text(
          'Ich höre zu... Sprich jetzt (z. B. "Schwarzwald" oder "Harz")',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Aufnahme beenden'), findsOneWidget);

      // Simulate recognized spoken words
      fakeVoice.capturedOnResult!('51.45, 9.75');
      await tester.pump();
      await tester.pumpAndSettle();

      // Search controller updated and direct GPS detected
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '51.45, 9.75');
      expect(find.text('Direkte GPS-Koordinate'), findsOneWidget);

      // Tap "Fertig" on listening banner to stop
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();

      expect(fakeVoice.isListening, isFalse);
    });

    testWidgets(
        'Voice input shows prominent inline warning when permission is denied or service unavailable',
        (tester) async {
      final fakeVoice = FakeVoiceSearchService(fakeAvailable: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationSearchSheet(
              onLocationSelected: (_) {},
              onUseCurrentLocation: () {},
              voiceSearchService: fakeVoice,
            ),
          ),
        ),
      );

      // Tap microphone button
      await tester.tap(find.byTooltip('Per Sprache suchen'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Inline error banner must be visible inside the sheet!
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Erneut'), findsOneWidget);
    });

    testWidgets(
        'Renders "Gebiete in deiner Nähe" section under "Häufige Gebiete" with distance chips',
        (tester) async {
      LocationSearchResult? tappedResult;

      // Coordinates around Berlin (52.5200, 13.4050)
      const berlinCoord = LatLng(52.5200, 13.4050);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationSearchSheet(
              biasCoordinate: berlinCoord,
              onLocationSelected: (loc) => tappedResult = loc,
              onUseCurrentLocation: () {},
            ),
          ),
        ),
      );

      // 1. Verify "Häufige Gebiete & Wälder:" section is present
      expect(find.text('Häufige Gebiete & Wälder:'), findsOneWidget);

      // 2. Verify "Gebiete in deiner Nähe:" section is rendered directly below
      expect(find.text('Gebiete in deiner Nähe:'), findsOneWidget);
      expect(find.textContaining('GPS-Umkreis'), findsOneWidget);

      // 3. For Berlin with 50 km default radius: Barnim, Döberitzer Heide, Dahme-Heideseen are in radius
      expect(find.textContaining('Barnim'), findsWidgets);

      // 4. Tap on a nearby region chip directly selects it and returns proper result
      final barnimFinder = find.ancestor(
        of: find.textContaining('Barnim'),
        matching: find.byType(ActionChip),
      );
      expect(barnimFinder, findsOneWidget);

      await tester.tap(barnimFinder);
      await tester.pumpAndSettle();

      expect(tappedResult, isNotNull);
      expect(tappedResult!.title, 'Naturpark Barnim');
      expect(tappedResult!.categoryLabel, 'Wald');
      expect(tappedResult!.subtitle, contains('Berlin'));
      expect(tappedResult!.subtitle, contains('km entfernt'));
      expect(tappedResult!.coordinate.latitude, closeTo(52.7000, 0.001));
      expect(tappedResult!.coordinate.longitude, closeTo(13.5000, 0.001));
    });

    testWidgets(
        'Nearby regions adapt dynamically to southern coordinates (Munich)',
        (tester) async {
      // Munich coordinates (48.1371, 11.5754)
      const munichCoord = LatLng(48.1371, 11.5754);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationSearchSheet(
              biasCoordinate: munichCoord,
              onLocationSelected: (_) {},
              onUseCurrentLocation: () {},
            ),
          ),
        ),
      );

      // In Munich vicinity within 50 km: Ebersberger Forst and Isarauen should be present
      expect(find.text('Gebiete in deiner Nähe:'), findsOneWidget);
      expect(find.textContaining('Ebersberger Forst'), findsOneWidget);
    });
  });

  group('AppSettingsService & AppSettingsSheet Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Loads default 50 km search radius out of the box', () async {
      final settings = await AppSettingsService.loadSettings();
      expect(settings.searchRadiusKm, 50.0);
      expect(settings.autoCenterGpsOnStart, isTrue);
      expect(settings.showPlaceNamesOnSatellite, isTrue);
    });

    test('Persists and updates search radius and notifies listeners', () async {
      expect(AppSettingsService.searchRadiusNotifier.value, isNotNull);

      await AppSettingsService.setSearchRadiusKm(75.0);
      expect(AppSettingsService.searchRadiusNotifier.value, 75.0);

      final loaded = await AppSettingsService.loadSettings();
      expect(loaded.searchRadiusKm, 75.0);

      // Test reset
      await AppSettingsService.resetToDefaults();
      final reset = await AppSettingsService.loadSettings();
      expect(reset.searchRadiusKm, 50.0);
      expect(AppSettingsService.searchRadiusNotifier.value, 50.0);
    });

    testWidgets('AppSettingsSheet renders slider, preset chips and updates radius',
        (tester) async {
      var changedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSettingsSheet(
              onSettingsChanged: () => changedCount++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title
      expect(find.text('App-Einstellungen'), findsOneWidget);

      // Accordion "Fotogebiet & Umkreissuche" öffnen
      await tester.tap(find.text('Fotogebiet & Umkreissuche'));
      await tester.pumpAndSettle();

      expect(find.text('Suchradius Umkreissuche'), findsOneWidget);
      expect(find.text('50 km'), findsWidgets);

      // Verify preset chips
      expect(find.text('25 km'), findsOneWidget);
      expect(find.text('50 km (Standard)'), findsOneWidget);
      expect(find.text('75 km'), findsOneWidget);
      expect(find.text('100 km'), findsOneWidget);
      expect(find.text('150 km'), findsOneWidget);

      // Tap 100 km chip
      await tester.tap(find.text('100 km'));
      await tester.pumpAndSettle();

      expect(changedCount, greaterThan(0));
      expect(AppSettingsService.searchRadiusNotifier.value, 100.0);

      // Verify close button
      expect(find.byTooltip('Schließen'), findsOneWidget);
    });
  });

  group('NearbyNatureRegionsService Unit Tests', () {
    test('findNearby returns regions sorted by ascending distance', () {
      // Berlin
      const berlin = LatLng(52.5200, 13.4050);
      final nearby = NearbyNatureRegionsService.findNearby(
        userCoordinate: berlin,
        limit: 5,
      );

      expect(nearby.length, 5);
      // Closest should have smaller distance than subsequent
      for (int i = 0; i < nearby.length - 1; i++) {
        expect(
          nearby[i].distanceKm,
          lessThanOrEqualTo(nearby[i + 1].distanceKm),
        );
      }

      // First few should be Brandenburg regions
      expect(
        nearby.any((e) => e.region.name.contains('Schorfheide') || e.region.name.contains('Dahme')),
        isTrue,
      );
    });

    test('findNearby gracefully handles invalid coordinates with fallback', () {
      final invalidCoord = LatLng(double.nan, 999.0);
      final nearby = NearbyNatureRegionsService.findNearby(
        userCoordinate: invalidCoord,
        limit: 4,
      );

      expect(nearby.length, 4);
      expect(nearby.first.region.name, isNotEmpty);
    });

    test('findByNameOrKeyword matches partial and full region names', () {
      final r1 = NearbyNatureRegionsService.findByNameOrKeyword('Schwarzwald');
      expect(r1, isNotNull);
      expect(r1!.name, contains('Schwarzwald'));

      final r2 = NearbyNatureRegionsService.findByNameOrKeyword('Harz');
      expect(r2, isNotNull);
      expect(r2!.name, contains('Harz'));

      final r3 = NearbyNatureRegionsService.findByNameOrKeyword('NonExistentXYZ');
      expect(r3, isNull);
    });
  });
}
