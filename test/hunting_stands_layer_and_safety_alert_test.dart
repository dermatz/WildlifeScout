import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/domain/services/habitat_suitability_engine.dart';
import 'package:wildlifescout/presentation/widgets/map_layers_sheet.dart';

void main() {
  final roeDeer = SpeciesProfile.fromJson({
    'id': 'roe_deer',
    'name': 'Rehwild',
    'scientificName': 'Capreolus capreolus',
    'category': 'ungulate',
    'shortDescription': 'Test',
    'accentColorHex': '#F59E0B',
    'behavior': {
      'activityPattern': 'crepuscular',
      'windSensitivity': 0.8,
      'scentSensitivityMeters': 250,
      'flightDistanceMeters': 70,
    },
    'habitatRules': {
      'optimalEdgeTypes': ['forest_meadow_edge'],
    },
  });

  test('HabitatAnalysisResult preserves hunting stands from OSM parsing', () {
    final rawOsm = <Map<String, dynamic>>[
      {
        'type': 'node',
        'id': 1001,
        'lat': 52.001,
        'lon': 13.002,
        'tags': <String, dynamic>{'amenity': 'hunting_stand'},
      },
      {
        'type': 'way',
        'id': 2001,
        'tags': <String, dynamic>{'landuse': 'forest'},
        'geometry': [
          {'lat': 52.000, 'lon': 13.000},
          {'lat': 52.005, 'lon': 13.000},
          {'lat': 52.005, 'lon': 13.005},
          {'lat': 52.000, 'lon': 13.005},
          {'lat': 52.000, 'lon': 13.000},
        ],
      },
    ];

    final result = HabitatSuitabilityEngine.evaluateRealOsmElements(
      rawElements: rawOsm,
      origin: const LatLng(52.0, 13.0),
      species: roeDeer,
      sourceLabel: 'Hunting Stand Test',
    );

    expect(result.huntingStands, isNotEmpty);
    expect(result.huntingStands.first.latitude, closeTo(52.001, 0.0001));
    expect(result.huntingStands.first.longitude, closeTo(13.002, 0.0001));
  });

  testWidgets('MapLayersSheet displays Hochsitze & Jägerstände toggle row', (tester) async {
    bool toggledValue = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapLayersSheet(
            primarySpecies: roeDeer,
            habitatCount: 4,
            trailCount: 2,
            huntingStandCount: 3,
            useSatelliteLayer: true,
            showHabitatLayer: true,
            showDisturbanceLayer: false,
            showHuntingStandsLayer: true,
            showRainRadarLayer: false,
            showScentCone: true,
            isNightVisionRedMode: false,
            onChangedSatellite: (_) {},
            onChangedHabitat: (_) {},
            onChangedDisturbance: (_) {},
            onChangedHuntingStands: (val) {
              toggledValue = val;
            },
            onChangedRainRadar: (_) {},
            onChangedScentCone: (_) {},
            onChangedNightVision: (_) {},
            onScanCurrentMapCenter: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('OSM Hochsitze & Jägerstände (3)'), findsOneWidget);
    expect(find.textContaining('Bekannte Ansitzkanzeln & Leitern'), findsOneWidget);

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsWidgets);

    // Tap the switch row for hunting stands
    await tester.tap(find.textContaining('OSM Hochsitze & Jägerstände (3)'));
    await tester.pumpAndSettle();

    expect(toggledValue, isFalse);
  });
}
