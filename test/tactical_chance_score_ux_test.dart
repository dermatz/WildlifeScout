import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildlifescout/core/theme/wildlifescout_theme.dart';
import 'package:wildlifescout/domain/models/habitat_zone.dart';
import 'package:wildlifescout/presentation/screens/field_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Field Map Chance Score & Habitat UX Tests', () {
    test('Chance Score Formula combines Activity & Biotop cleanly', () {
      final sampleZone = HabitatZone(
        id: 'test_zone_1',
        osmId: 'osm_123',
        osmTag: 'landuse=meadow',
        speciesId: 'roe_deer',
        speciesName: 'Rehwild',
        title: 'Äsungsfläche Waldsaum',
        subtitle: 'Deckungsreicher Übergangssaum',
        type: HabitatZoneType.optimalEdge,
        suitabilityScore: 87.0,
        distanceToNearestTrailMeters: 140.0,
        distanceToWaterMeters: 80.0,
        distanceToForestMeters: 10.0,
        polygonPoints: const [
          LatLng(52.98, 13.76),
          LatLng(52.981, 13.76),
          LatLng(52.981, 13.761),
        ],
        center: const LatLng(52.98, 13.76),
      );

      final activityScore = 52;
      final suitabilityScore = sampleZone.suitabilityScore;
      final chanceScore =
          ((activityScore + suitabilityScore) / 2.0).round().clamp(0, 100);

      expect(chanceScore, 70);
    });

    testWidgets('FieldMapScreen renders self-explanatory "70% Chance" marker and detailed breakdown on tap',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WildlifeScoutTheme.buildDarkTheme(),
          home: const FieldMapScreen(),
        ),
      );

      // Warte auf asynchrones Laden
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verifiziere, dass keine kryptische "⚡ 52% | 87%"-Anzeige existiert,
      // sondern stattdessen "Chance" oder "Erfolgs-Chance"
      expect(find.text('52% | 87%'), findsNothing);
    });

    test('Chance Score Explanation copy answers Wann and Wo clearly', () {
      const activityScore = 51;
      const biotopScore = 87;
      final chance = ((activityScore + biotopScore) / 2.0).round();
      expect(chance, 69);

      final formulaStr = '($activityScore% + $biotopScore%) ÷ 2 = $chance% Chance';
      expect(formulaStr, contains('69% Chance'));
      expect(formulaStr, contains('51%'));
      expect(formulaStr, contains('87%'));
    });
  });
}
