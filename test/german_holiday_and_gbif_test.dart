import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wildlifescout/data/api/gbif_occurrence_client.dart';
import 'package:wildlifescout/domain/models/habitat_zone.dart';
import 'package:wildlifescout/domain/models/species_profile.dart';
import 'package:wildlifescout/domain/models/weather_frame.dart';
import 'package:wildlifescout/domain/services/disturbance_matrix_service.dart';
import 'package:wildlifescout/domain/services/german_holiday_service.dart';
import 'package:wildlifescout/domain/services/sun_moon_calculator.dart';
import 'package:wildlifescout/domain/services/wildlife_tactical_engine.dart';

void main() {
  group('GermanHolidayService (100% Offline-Gauß-Formel & Ferien)', () {
    test('Berechnet Ostersonntag für mehrere Jahre mathematisch exakt', () {
      final easter2025 = GermanHolidayService.calculateEasterSunday(2025);
      expect(easter2025, DateTime(2025, 4, 20));

      final easter2026 = GermanHolidayService.calculateEasterSunday(2026);
      expect(easter2026, DateTime(2026, 4, 5));

      final easter2027 = GermanHolidayService.calculateEasterSunday(2027);
      expect(easter2027, DateTime(2027, 3, 28));
    });

    test('Erkennt feste bundesweite Feiertage zuverlässig', () {
      expect(
        GermanHolidayService.isPublicHoliday(DateTime(2026, 1, 1)),
        isTrue,
      );
      expect(
        GermanHolidayService.getHolidayName(DateTime(2026, 1, 1)),
        'Neujahr',
      );

      expect(
        GermanHolidayService.isPublicHoliday(DateTime(2026, 5, 1)),
        isTrue,
      );
      expect(
        GermanHolidayService.getHolidayName(DateTime(2026, 5, 1)),
        'Tag der Arbeit',
      );

      expect(
        GermanHolidayService.isPublicHoliday(DateTime(2026, 10, 3)),
        isTrue,
      );
      expect(
        GermanHolidayService.getHolidayName(DateTime(2026, 10, 3)),
        'Tag der Deutschen Einheit',
      );

      expect(
        GermanHolidayService.isPublicHoliday(DateTime(2026, 12, 25)),
        isTrue,
      );
      expect(
        GermanHolidayService.isPublicHoliday(DateTime(2026, 12, 26)),
        isTrue,
      );
    });

    test('Erkennt bewegliche Feiertage für 2026 exakt', () {
      // 2026: Ostern = 5. April
      // Karfreitag = 3. April
      expect(
        GermanHolidayService.isPublicHoliday(DateTime(2026, 4, 3)),
        isTrue,
      );
      expect(
        GermanHolidayService.getHolidayName(DateTime(2026, 4, 3)),
        'Karfreitag',
      );

      // Ostermontag = 6. April
      expect(
        GermanHolidayService.isPublicHoliday(DateTime(2026, 4, 6)),
        isTrue,
      );
      expect(
        GermanHolidayService.getHolidayName(DateTime(2026, 4, 6)),
        'Ostermontag',
      );

      // Christi Himmelfahrt = 14. Mai 2026 (Donnerstag)
      expect(
        GermanHolidayService.isPublicHoliday(DateTime(2026, 5, 14)),
        isTrue,
      );
      expect(
        GermanHolidayService.getHolidayName(DateTime(2026, 5, 14)),
        'Christi Himmelfahrt',
      );

      // Pfingstmontag = 25. Mai 2026
      expect(
        GermanHolidayService.isPublicHoliday(DateTime(2026, 5, 25)),
        isTrue,
      );
      expect(
        GermanHolidayService.getHolidayName(DateTime(2026, 5, 25)),
        'Pfingstmontag',
      );
    });

    test('Erkennt Schulferien-Korridore (Sommer- & Osterferien)', () {
      expect(
        GermanHolidayService.isSchoolVacation(DateTime(2026, 7, 20)),
        isTrue,
      );
      expect(
        GermanHolidayService.getSchoolVacationName(DateTime(2026, 7, 20)),
        'Sommerferien',
      );

      expect(
        GermanHolidayService.isSchoolVacation(DateTime(2026, 4, 1)),
        isTrue,
      );
      expect(
        GermanHolidayService.getSchoolVacationName(DateTime(2026, 4, 1)),
        'Osterferien',
      );

      // Ein normaler Novembertag ist keine Ferienzeit
      expect(
        GermanHolidayService.isSchoolVacation(DateTime(2026, 11, 10)),
        isFalse,
      );
    });

    test('DisturbanceMatrixService moduliert Freizeitdruck an Feiertagen wie am Wochenende', () {
      // Christi Himmelfahrt (14. Mai 2026, Donnerstag) um 14:00 Uhr:
      // Trotz Werktag (Donnerstag) greift der Feiertagsfaktor 1.45 statt regulär 0.90!
      final himmelfahrtMidday = DateTime(2026, 5, 14, 14, 0);
      final factorHoliday = DisturbanceMatrixService.getTimeModulationFactor(himmelfahrtMidday);
      expect(factorHoliday, equals(1.45));

      // Normaler Donnerstag (21. Mai 2026) um 14:00 Uhr:
      // Regulärer Werktag = 0.90
      final regularThursday = DateTime(2026, 5, 21, 14, 0);
      final factorRegular = DisturbanceMatrixService.getTimeModulationFactor(regularThursday);
      expect(factorRegular, equals(0.90));
    });
  });

  group('GBIF Occurrence Client & WildlifeTacticalEngine Integration', () {
    final defaultSpecies = SpeciesProfile.fromJson({
      'id': 'roe_deer',
      'name': 'Rehwild (Capreolus capreolus)',
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

    final sampleZone = HabitatZone(
      id: 'test_zone',
      osmId: '123',
      osmTag: 'natural=wood',
      title: 'Waldkante',
      subtitle: 'Ruhige Lage',
      type: HabitatZoneType.optimalEdge,
      suitabilityScore: 75.0,
      distanceToNearestTrailMeters: 45.0,
      distanceToWaterMeters: 100.0,
      distanceToForestMeters: 0.0,
      polygonPoints: const [
        LatLng(52.0, 13.0),
        LatLng(52.01, 13.0),
        LatLng(52.01, 13.01),
        LatLng(52.0, 13.01),
      ],
      center: const LatLng(52.005, 13.005),
    );

    test('GBIF-Nachweise erzeugen TacticalFactorBadge mit Bio-Validierungs-Bonus', () {
      const confirmedGbif = GbifRegionalPresence(
        scientificName: 'Capreolus capreolus',
        totalCount: 42,
        latestYear: 2026,
        datasets: ['iNaturalist', 'Observation.org'],
        summaryLabel: '42 verifizierte GBIF-Nachweise im 15-km-Umkreis (zuletzt 2026)',
        isConfirmed: true,
      );

      final weather = WeatherFrame(
        time: DateTime(2026, 5, 21, 6, 0), // Werktag früh
        temperatureCelsius: 12.0,
        windSpeedKmh: 10.0,
        windGustsKmh: 15.0,
        windDirectionDegrees: 180.0,
        surfacePressureHpa: 1015.0,
        pressureDelta6hHpa: 0.0,
        cloudCoverPercent: 20,
        visibilityMeters: 10000.0,
        precipitationMm: 0.0,
        weatherCode: 0,
      );

      final astro = SunMoonCalculator.calculate(
        dateTime: weather.time,
        latitude: 52.0,
        longitude: 13.0,
      );

      final assessment = WildlifeTacticalEngine.assessZone(
        zone: sampleZone,
        species: defaultSpecies,
        weather: weather,
        astro: astro,
        baseActivityScore: 80,
        gbifPresence: confirmedGbif,
      );

      // Prüfung: GBIF-Badge vorhanden
      expect(
        assessment.badges.any((b) => b.title == 'GBIF-Vorkommen bestätigt'),
        isTrue,
      );
      final gbifBadge = assessment.badges.firstWhere(
        (b) => b.title == 'GBIF-Vorkommen bestätigt',
      );
      expect(gbifBadge.icon, '🔬');
      expect(gbifBadge.scoreDelta, 3.0);
      expect(gbifBadge.isPositive, isTrue);
    });

    test('Feiertag am Werktag erzeugt Feiertags-Freizeitdruck Badge', () {
      // Christi Himmelfahrt (14. Mai 2026, Donnerstag um 14:00 Uhr)
      final weatherHoliday = WeatherFrame(
        time: DateTime(2026, 5, 14, 14, 0),
        temperatureCelsius: 20.0,
        windSpeedKmh: 10.0,
        windGustsKmh: 15.0,
        windDirectionDegrees: 180.0,
        surfacePressureHpa: 1015.0,
        pressureDelta6hHpa: 0.0,
        cloudCoverPercent: 10,
        visibilityMeters: 10000.0,
        precipitationMm: 0.0,
        weatherCode: 0,
      );

      final astro = SunMoonCalculator.calculate(
        dateTime: weatherHoliday.time,
        latitude: 52.0,
        longitude: 13.0,
      );

      final assessment = WildlifeTacticalEngine.assessZone(
        zone: sampleZone,
        species: defaultSpecies,
        weather: weatherHoliday,
        astro: astro,
        baseActivityScore: 60,
      );

      // Prüfung: Feiertags-Badge anstelle von einfachem Werktag
      expect(
        assessment.badges.any((b) => b.title.contains('Feiertags-Freizeitdruck')),
        isTrue,
      );
      final holidayBadge = assessment.badges.firstWhere(
        (b) => b.title.contains('Feiertags-Freizeitdruck'),
      );
      expect(holidayBadge.icon, '🚶');
      expect(holidayBadge.isPositive, isFalse);
    });
  });
}
