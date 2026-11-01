import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/presentation/widgets/species_multiselect_sheet.dart';

SpeciesProfile _createDummySpecies({
  required String id,
  required String name,
  required String scientificName,
  required SpeciesCategory category,
  required String description,
  double scent = 250,
  double flight = 80,
  String weight = '15 – 30 kg',
}) {
  return SpeciesProfile(
    id: id,
    name: name,
    scientificName: scientificName,
    category: category,
    shortDescription: description,
    accentColor: const Color(0xFF10B981),
    behavior: BehaviorProfile(
      scentSensitivityMeters: scent,
      scentConeAngleDegrees: 45,
      primaryActivityPeriods: [ActivityPeriod.dawn, ActivityPeriod.dusk],
      barometerDropSensitivity: 0.5,
      maxToleratedWindSpeedKmh: 45,
      flightDistanceMeters: flight,
    ),
    openData: SpeciesOpenData(
      taxonomy: 'Familie Test',
      bodyWeight: weight,
      conservationStatus: 'LC',
    ),
    behaviorTraits: const [],
    habitatRules: const HabitatRules(
      edgePreferences: [],
      landuseWeights: [],
      disturbancePenalties: [],
      minContiguousAreaHectares: 1.0,
    ),
    fieldTips: ['Test-Tipp für Ansitz'],
  );
}

void main() {
  final testSpecies = [
    _createDummySpecies(
      id: 'roe_deer',
      name: 'Rehwild',
      scientificName: 'Capreolus capreolus',
      category: SpeciesCategory.ungulate,
      description: 'Konzentratselektierer der Wald-Feld-Kanten',
      scent: 250,
      flight: 80,
      weight: '15 – 30 kg',
    ),
    _createDummySpecies(
      id: 'red_deer',
      name: 'Rotwild',
      scientificName: 'Cervus elaphus',
      category: SpeciesCategory.ungulate,
      description: 'Extrem störungsempfindliches Großwild',
      scent: 450,
      flight: 250,
      weight: '90 – 220 kg',
    ),
    _createDummySpecies(
      id: 'wild_boar',
      name: 'Schwarzwild',
      scientificName: 'Sus scrofa',
      category: SpeciesCategory.ungulate,
      description: 'Intelligentes, anpassungsfähiges Schalenwild',
      scent: 500,
      flight: 120,
      weight: '50 – 150 kg',
    ),
    _createDummySpecies(
      id: 'red_fox',
      name: 'Rotfuchs',
      scientificName: 'Vulpes vulpes',
      category: SpeciesCategory.carnivore,
      description: 'Kulturfolger und wendiger Jäger',
      scent: 300,
      flight: 60,
      weight: '5 – 9 kg',
    ),
  ];

  Widget buildTestSheet({
    Set<String> selectedIds = const {'roe_deer'},
    ValueChanged<Set<String>>? onSelectionChanged,
    ValueChanged<SpeciesProfile>? onInspectSpecies,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SpeciesMultiSelectSheet(
          allSpecies: testSpecies,
          initialSelectedIds: selectedIds,
          onSelectionChanged: onSelectionChanged ?? (_) {},
          onInspectSpecies: onInspectSpecies ?? (_) {},
        ),
      ),
    );
  }

  testWidgets(
      'SpeciesMultiSelectSheet has clean subtitle and does NOT show "Unsplash • Frei"',
      (tester) async {
    await tester.pumpWidget(buildTestSheet());
    await tester.pumpAndSettle();

    // Verify "Unsplash • Frei" badge overlay is completely absent
    expect(find.text('Unsplash • Frei'), findsNothing);

    // Verify updated clean subtitle without "Lizenzfreie Unsplash-Fotos" and without "Offene"
    expect(find.text('Wilddaten & Tipps'), findsOneWidget);
    expect(find.textContaining('Lizenzfreie Unsplash-Fotos'), findsNothing);
    expect(find.textContaining('Offene Wilddaten'), findsNothing);
  });

  testWidgets('SpeciesMultiSelectSheet renders compact tiles with minHeight 76',
      (tester) async {
    await tester.pumpWidget(buildTestSheet());
    await tester.pumpAndSettle();

    // Verify all 4 species names are visible in the list
    expect(find.text('Rehwild'), findsOneWidget);
    expect(find.text('Rotwild'), findsOneWidget);
    expect(find.text('Schwarzwild'), findsOneWidget);
    expect(find.text('Rotfuchs'), findsOneWidget);

    // Verify card height has at least 76px
    final cardFinder = find.byType(AnimatedContainer).first;
    final cardSize = tester.getSize(cardFinder);
    expect(cardSize.height, greaterThanOrEqualTo(76.0));

    // Verify compact quick fact pills are rendered
    expect(find.text('Witterung 250m'), findsOneWidget);
    expect(find.text('Flucht 80m'), findsOneWidget);
    expect(find.text('15 – 30 kg'), findsOneWidget);

    // Verify counter shows 4 species available
    expect(find.text('4 Wildarten im Revier'), findsOneWidget);
    expect(find.text('1 aktiv'), findsOneWidget);

    // Verify Latin scientific name and category badge are removed from the card
    expect(find.text('Capreolus capreolus'), findsNothing);
    expect(find.text('Schalenwild'), findsNothing);
  });

  testWidgets('Live search filters species by name, category, and science',
      (tester) async {
    await tester.pumpWidget(buildTestSheet());
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);

    // 1. Search by German name
    await tester.enterText(searchField, 'Rotwild');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InkWell, 'Rotwild'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Rehwild'), findsNothing);
    expect(find.widgetWithText(InkWell, 'Rotfuchs'), findsNothing);
    expect(find.text('1 von 4 Wildarten gefunden'), findsOneWidget);

    // 2. Search by scientific name
    await tester.enterText(searchField, 'Vulpes');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InkWell, 'Rotfuchs'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Rotwild'), findsNothing);
    expect(find.text('1 von 4 Wildarten gefunden'), findsOneWidget);

    // 3. Search by category "Raubwild"
    await tester.enterText(searchField, 'Raubwild');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InkWell, 'Rotfuchs'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Rehwild'), findsNothing);

    // 4. Search with no matches -> displays empty state
    await tester.enterText(searchField, 'Eichhörnchen');
    await tester.pumpAndSettle();

    expect(
      find.text('Keine Wildart für "Eichhörnchen" gefunden'),
      findsOneWidget,
    );
    expect(find.text('Suche zurücksetzen'), findsOneWidget);

    // 5. Reset search
    await tester.tap(find.text('Suche zurücksetzen'));
    await tester.pumpAndSettle();

    expect(find.text('Rehwild'), findsOneWidget);
    expect(find.text('Rotwild'), findsOneWidget);
    expect(find.text('Schwarzwild'), findsOneWidget);
    expect(find.text('Rotfuchs'), findsOneWidget);
    expect(find.text('4 Wildarten im Revier'), findsOneWidget);
  });

  testWidgets('Tapping search clear button resets query', (tester) async {
    await tester.pumpWidget(buildTestSheet());
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'Schwein');
    await tester.pumpAndSettle();

    // Clear button should be visible
    final clearButton = find.byTooltip('Suche leeren');
    expect(clearButton, findsOneWidget);

    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(find.text('4 Wildarten im Revier'), findsOneWidget);
  });

  testWidgets('Toggling species updates selection and onSelectionChanged',
      (tester) async {
    Set<String>? updatedSelection;
    await tester.pumpWidget(
      buildTestSheet(
        selectedIds: {'roe_deer'},
        onSelectionChanged: (set) => updatedSelection = set,
      ),
    );
    await tester.pumpAndSettle();

    // Tap on Rotwild to add it
    await tester.tap(find.text('Rotwild'));
    await tester.pumpAndSettle();

    expect(updatedSelection, contains('red_deer'));
    expect(updatedSelection, contains('roe_deer'));
    expect(find.text('2 aktiv'), findsOneWidget);

    // Tap 'Nur Rehwild' to reset
    await tester.tap(find.text('Nur Rehwild'));
    await tester.pumpAndSettle();

    expect(updatedSelection, equals({'roe_deer'}));
    expect(find.text('1 aktiv'), findsOneWidget);
  });

  testWidgets('Tapping info button calls onInspectSpecies', (tester) async {
    SpeciesProfile? inspected;
    await tester.pumpWidget(
      buildTestSheet(
        selectedIds: {'roe_deer'},
        onInspectSpecies: (sp) => inspected = sp,
      ),
    );
    await tester.pumpAndSettle();

    final infoButton = find.byTooltip('Voll-Steckbrief für Rotwild');
    expect(infoButton, findsOneWidget);

    await tester.tap(infoButton);
    await tester.pumpAndSettle();

    expect(inspected, isNotNull);
    expect(inspected?.id, 'red_deer');
  });

  testWidgets('Tapping chevron expands details inline', (tester) async {
    await tester.pumpWidget(buildTestSheet());
    await tester.pumpAndSettle();

    // Initially expanded section is closed
    expect(find.text('OFFENE WILDBIOLOGIE-DATEN (OPEN DATA)'), findsNothing);

    // Tap expand chevron on Rehwild
    final chevron = find.byTooltip('Biologie & Tipps anzeigen').first;
    await tester.tap(chevron);
    await tester.pumpAndSettle();

    // Now expanded details should be visible
    expect(find.text('OFFENE WILDBIOLOGIE-DATEN (OPEN DATA)'), findsOneWidget);
    expect(find.text('Test-Tipp für Ansitz'), findsOneWidget);

    // Tap again to collapse
    final collapseChevron = find.byTooltip('Details verbergen').first;
    await tester.tap(collapseChevron);
    await tester.pumpAndSettle();

    expect(find.text('OFFENE WILDBIOLOGIE-DATEN (OPEN DATA)'), findsNothing);
  });
}
