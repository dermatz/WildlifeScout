import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildlifescout/core/geo/geo_geometry_utils.dart';
import 'package:wildlifescout/data/services/osm_element_parser.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/domain/services/habitat_suitability_engine.dart';

/// Regressionstest für den „Baggersee an der A8“-Fall:
/// - Ein See, der als innerer Ring einer Wald-Multipolygon-Relation gemappt
///   ist, wurde fälschlich als „Waldlichtung“ (Äsungswiese) für Rehwild gewertet.
/// - `highway=motorway` wurde vom Parser komplett ignoriert, sodass die beste
///   Chance direkt neben der Autobahn lag.
void main() {
  final roeDeer = SpeciesProfile.fromJson({
    'id': 'roe_deer',
    'name': 'Rehwild',
    'scientificName': 'Capreolus capreolus',
    'category': 'ungulate',
    'shortDescription': 'Test',
    'accentColorHex': '#F59E0B',
    'behavior': {
      'scentSensitivityMeters': 350.0,
      'scentConeAngleDegrees': 45.0,
      'primaryActivityPeriods': ['dawn', 'dusk'],
      'barometerDropSensitivity': 0.8,
      'maxToleratedWindSpeedKmh': 35.0,
      'flightDistanceMeters': 100.0,
    },
  });

  List<Map<String, double>> ring(double s, double w, double n, double e) => [
        {'lat': s, 'lon': w},
        {'lat': s, 'lon': e},
        {'lat': n, 'lon': e},
        {'lat': n, 'lon': w},
        {'lat': s, 'lon': w},
      ];

  final lakeRing = ring(51.9985, 12.998, 52.0015, 13.002);
  final lakePolygon = [
    for (final p in lakeRing) LatLng(p['lat']!, p['lon']!),
  ];
  const motorwayLat = 52.0045;

  final elements = <Map<String, dynamic>>[
    // Wald-Außenring (untagged, Mitglied der Relation)
    {
      'type': 'way',
      'id': 1,
      'tags': <String, dynamic>{},
      'geometry': ring(51.997, 12.995, 52.003, 13.005),
    },
    // Innerer Ring = Baggersee (ohne eigene Tags, typisches Mapping)
    {
      'type': 'way',
      'id': 2,
      'tags': <String, dynamic>{},
      'geometry': lakeRing,
    },
    // Separates Wasser-Polygon mit identischer Geometrie
    {
      'type': 'way',
      'id': 3,
      'tags': <String, dynamic>{
        'natural': 'water',
        'water': 'lake',
        'name': 'Baggersee',
      },
      'geometry': lakeRing,
    },
    // Wiese zwischen Waldrand und Autobahn (~100 m zur A8)
    {
      'type': 'way',
      'id': 4,
      'tags': <String, dynamic>{'landuse': 'meadow'},
      'geometry': ring(52.0031, 12.997, 52.0041, 13.003),
    },
    // Autobahn A8
    {
      'type': 'way',
      'id': 5,
      'tags': <String, dynamic>{'highway': 'motorway', 'ref': 'A 8'},
      'geometry': [
        {'lat': motorwayLat, 'lon': 12.985},
        {'lat': motorwayLat, 'lon': 13.000},
        {'lat': motorwayLat, 'lon': 13.015},
      ],
    },
    {
      'type': 'relation',
      'id': 10,
      'tags': <String, dynamic>{'type': 'multipolygon', 'landuse': 'forest'},
      'members': [
        {'type': 'way', 'ref': 1, 'role': 'outer'},
        {'type': 'way', 'ref': 2, 'role': 'inner'},
      ],
    },
  ];

  final analysis = HabitatSuitabilityEngine.evaluateRealOsmElements(
    rawElements: elements,
    origin: const LatLng(52.0, 13.0),
    species: roeDeer,
    sourceLabel: 'Test',
  );

  test('Kein Rehwild-Habitat auf der Seefläche', () {
    expect(analysis.habitatZones, isNotEmpty);
    for (final z in analysis.habitatZones) {
      expect(
        GeoGeometryUtils.isPointInPolygon(z.center, lakePolygon),
        isFalse,
        reason: '${z.title} liegt im Baggersee',
      );
      expect(z.title, isNot(contains('Lichtung')));
    }
  });

  test('Autobahn wird als Störungskorridor erkannt', () {
    expect(analysis.disturbanceTrails.any((t) => t.osmId == '5'), isTrue);
  });

  test('Kein Rehwild-Habitat im 150-m-Lärmpuffer der Autobahn', () {
    const distance = Distance();
    for (final z in analysis.habitatZones) {
      final dToMotorway = distance.as(
        LengthUnit.Meter,
        z.center,
        LatLng(motorwayLat, z.center.longitude),
      );
      expect(
        dToMotorway,
        greaterThanOrEqualTo(150.0),
        reason: '${z.title} liegt nur ${dToMotorway.round()} m neben der A8',
      );
    }
  });

  group('Bahnlinien', () {
    const railLat = 51.9962;
    List<Map<String, double>> line(double lat) => [
          {'lat': lat, 'lon': 12.985},
          {'lat': lat, 'lon': 13.015},
        ];

    final railElements = <Map<String, dynamic>>[
      ...elements.where((e) => e['id'] != 5), // ohne Autobahn
      // Wiese direkt südlich am Wald, durchschnitten von der Bahn
      {
        'type': 'way',
        'id': 6,
        'tags': <String, dynamic>{'landuse': 'meadow'},
        'geometry': ring(51.9955, 12.997, 51.9969, 13.003),
      },
      // Aktive Hauptstrecke
      {
        'type': 'way',
        'id': 20,
        'tags': <String, dynamic>{'railway': 'rail', 'usage': 'main'},
        'geometry': line(railLat),
      },
      // Tunnel, Abstellgleis & stillgelegte Strecke: dürfen nicht stören
      {
        'type': 'way',
        'id': 21,
        'tags': <String, dynamic>{'railway': 'rail', 'tunnel': 'yes'},
        'geometry': line(52.0),
      },
      {
        'type': 'way',
        'id': 22,
        'tags': <String, dynamic>{'railway': 'rail', 'service': 'siding'},
        'geometry': line(52.001),
      },
      {
        'type': 'way',
        'id': 23,
        'tags': <String, dynamic>{'railway': 'abandoned'},
        'geometry': line(52.002),
      },
    ];

    final railAnalysis = HabitatSuitabilityEngine.evaluateRealOsmElements(
      rawElements: railElements,
      origin: const LatLng(52.0, 13.0),
      species: roeDeer,
      sourceLabel: 'Test',
    );

    test('Aktive Bahnlinie wird als Störungskorridor erkannt', () {
      final ids = railAnalysis.disturbanceTrails.map((t) => t.osmId).toSet();
      expect(ids, contains('20'));
      expect(ids, isNot(contains('21')));
      expect(ids, isNot(contains('22')));
      expect(ids, isNot(contains('23')));
    });

    test('Kein Rehwild-Habitat im 70-m-Puffer der Bahnlinie', () {
      const distance = Distance();
      for (final z in railAnalysis.habitatZones) {
        final dToRail = distance.as(
          LengthUnit.Meter,
          z.center,
          LatLng(railLat, z.center.longitude),
        );
        expect(
          dToRail,
          greaterThanOrEqualTo(70.0),
          reason: '${z.title} liegt nur ${dToRail.round()} m am Gleis',
        );
      }
    });
  });

  group('Siedlungsflächen & Gewerbegebiete', () {
    final settlementRing = ring(52.001, 13.003, 52.004, 13.007);
    final settlementPolygon = [
      for (final p in settlementRing) LatLng(p['lat']!, p['lon']!),
    ];

    final settlementElements = <Map<String, dynamic>>[
      // Waldgebiet
      {
        'type': 'way',
        'id': 101,
        'tags': <String, dynamic>{'landuse': 'forest'},
        'geometry': ring(51.998, 12.998, 52.002, 13.004),
      },
      // Wiese im Dorf / Neubaugebiet
      {
        'type': 'way',
        'id': 102,
        'tags': <String, dynamic>{'landuse': 'meadow'},
        'geometry': ring(52.0015, 13.0035, 52.0025, 13.0045),
      },
      // Wohnsiedlung (Polygongebiets-Ausweisung)
      {
        'type': 'way',
        'id': 103,
        'tags': <String, dynamic>{'landuse': 'residential', 'name': 'Neubaugebiet'},
        'geometry': settlementRing,
      },
    ];

    final settlementAnalysis = HabitatSuitabilityEngine.evaluateRealOsmElements(
      rawElements: settlementElements,
      origin: const LatLng(52.0, 13.0),
      species: roeDeer,
      sourceLabel: 'Settlement Test',
    );

    test('Kein Rehwild-Habitat innerhalb der Siedlungsfläche', () {
      for (final z in settlementAnalysis.habitatZones) {
        expect(
          GeoGeometryUtils.isPointInPolygon(z.center, settlementPolygon),
          isFalse,
          reason: '${z.title} liegt mitten in der Wohnsiedlung',
        );
      }
    });
  });

  group('Freizeit, Badestellen & Hecken', () {
    final beachRing = ring(52.0005, 12.9995, 52.0012, 13.0005);
    final elementsWithLeisure = <Map<String, dynamic>>[
      // Wald
      {
        'type': 'way',
        'id': 201,
        'tags': <String, dynamic>{'landuse': 'forest'},
        'geometry': ring(51.996, 12.994, 52.002, 13.004),
      },
      // Badestelle / Strandbad am Baggersee
      {
        'type': 'way',
        'id': 202,
        'tags': <String, dynamic>{'leisure': 'swimming_area', 'name': 'Badesee Strandbad'},
        'geometry': beachRing,
      },
      // Wanderparkplatz
      {
        'type': 'way',
        'id': 203,
        'tags': <String, dynamic>{'amenity': 'parking', 'name': 'Parkplatz Baggersee'},
        'geometry': ring(52.0025, 12.998, 52.0030, 12.999),
      },
      // Heckenriegel im Freiland
      {
        'type': 'way',
        'id': 204,
        'tags': <String, dynamic>{'barrier': 'hedge'},
        'geometry': [
          {'lat': 51.997, 'lon': 13.006},
          {'lat': 51.999, 'lon': 13.008},
          {'lat': 52.001, 'lon': 13.010},
        ],
      },
    ];

    final leisureAnalysis = HabitatSuitabilityEngine.evaluateRealOsmElements(
      rawElements: elementsWithLeisure,
      origin: const LatLng(52.0, 13.0),
      species: roeDeer,
      sourceLabel: 'Leisure Test',
    );

    test('Badestelle und Parkplatz werden als Störungskorridor registriert', () {
      final trailOsmIds = leisureAnalysis.disturbanceTrails.map((t) => t.osmId).toSet();
      expect(trailOsmIds, contains('202'));
      expect(trailOsmIds, contains('203'));
    });

    test('Heckenriegel wird als valides Deckungshabitat erkannt', () {
      expect(
        leisureAnalysis.habitatZones.any((z) => z.title.contains('Heckenriegel')),
        isTrue,
      );
    });

    test('Scores sind differenziert und nicht künstlich auf 92/93% geklumpt', () {
      final scores = leisureAnalysis.habitatZones.map((z) => z.suitabilityScore).toList();
      expect(scores, isNotEmpty);
      // Nicht alle Zonen haben identische Werte an der Obergrenze
      final uniqueRoundedScores = scores.map((s) => s.round()).toSet();
      expect(uniqueRoundedScores.length, greaterThanOrEqualTo(2));
      for (final s in scores) {
        expect(s, lessThanOrEqualTo(95.0));
        expect(s, greaterThanOrEqualTo(50.0));
      }
    });
  });

  group('Hochsitze (amenity=hunting_stand)', () {
    test('Hochsitz als Node wird erfasst und belohnt bewährte Wechsel im Einstiegsbereich', () {
      final elementsWithStand = <Map<String, dynamic>>[
        ...elements.where((e) => e['id'] != 5), // ohne Autobahn
        // Waldrand-Wiese
        {
          'type': 'way',
          'id': 301,
          'tags': <String, dynamic>{'landuse': 'meadow'},
          'geometry': ring(51.996, 12.998, 51.999, 13.002),
        },
        // Hochsitz als OSM-Node in 70m Entfernung
        {
          'type': 'node',
          'id': 9901,
          'lat': 51.9985,
          'lon': 13.001,
          'tags': <String, dynamic>{'amenity': 'hunting_stand'},
        },
      ];

      final categorized = OsmElementParser.parse(elementsWithStand);
      expect(categorized.huntingStands, isNotEmpty);
      expect(categorized.huntingStands.first.latitude, closeTo(51.9985, 0.0001));

      final standAnalysis = HabitatSuitabilityEngine.evaluateRealOsmElements(
        rawElements: elementsWithStand,
        origin: const LatLng(52.0, 13.0),
        species: roeDeer,
        sourceLabel: 'Hunting Stand Test',
      );

      // Mindestens eine Zone sollte den Hochsitz in den Subtitle aufnehmen
      final standZones = standAnalysis.habitatZones
          .where((z) => z.subtitle.contains('Hochsitz'))
          .toList();
      expect(standZones, isNotEmpty);
      expect(standZones.first.subtitle, contains('bewährter Wechsel'));
    });
  });
}
