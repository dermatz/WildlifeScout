import 'dart:convert';
import 'package:http/http.dart' as http;

/// Modell für Feiertags- & Ferienauswertungen.
class HolidayAndVacationInfo {
  final bool isHoliday;
  final String? holidayName;
  final bool isSchoolVacation;
  final String? vacationName;

  const HolidayAndVacationInfo({
    required this.isHoliday,
    this.holidayName,
    required this.isSchoolVacation,
    this.vacationName,
  });

  bool get hasRecreationalImpact => isHoliday || isSchoolVacation;
}

/// Service zur Ermittlung von gesetzlichen Feiertagen und Schulferien in Deutschland.
///
/// Funktioniert 100% offline (Gaußsche Osterformel für bewegliche Feiertage +
/// verlässliche bundesweite Ferienkorridore), sodass im Funkloch im Wald keine
/// Netzwerkverbindung erforderlich ist.
/// Unterstützt optionalen Online-Cache-Sync über feiertage-api.de.
class GermanHolidayService {
  GermanHolidayService._();

  static final Map<int, Map<String, String>> _holidayCacheByYear = {};
  static final Map<String, String> _customSyncedHolidays = {};

  /// Berechnet das genaue Datum des Ostersonntags für ein beliebiges Jahr
  /// nach dem Algorithmus von Gauß / Gregorianischer Algorithmus.
  static DateTime calculateEasterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  /// Gibt alle gesetzlichen Feiertage (bundesweit + wichtige länderspezifische)
  /// für ein Jahr als Map zurück (Schlüssel: 'YYYY-MM-DD', Wert: Name).
  static Map<String, String> getPublicHolidaysForYear(int year) {
    if (_holidayCacheByYear.containsKey(year)) {
      return _holidayCacheByYear[year]!;
    }

    final holidays = <String, String>{};

    String dateKey(DateTime dt) =>
        '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    // 1. Feste bundesweite Feiertage
    holidays['$year-01-01'] = 'Neujahr';
    holidays['$year-05-01'] = 'Tag der Arbeit';
    holidays['$year-10-03'] = 'Tag der Deutschen Einheit';
    holidays['$year-12-25'] = '1. Weihnachtstag';
    holidays['$year-12-26'] = '2. Weihnachtstag';

    // 2. Feste regionale Feiertage mit hoher Ausflugswirkung
    holidays['$year-01-06'] = 'Heilige Drei Könige';
    holidays['$year-10-31'] = 'Reformationstag';
    holidays['$year-11-01'] = 'Allerheiligen';

    // 3. Bewegliche Feiertage (abgeleitet von Ostern)
    final easter = calculateEasterSunday(year);
    holidays[dateKey(easter.subtract(const Duration(days: 2)))] = 'Karfreitag';
    holidays[dateKey(easter.add(const Duration(days: 1)))] = 'Ostermontag';
    holidays[dateKey(easter.add(const Duration(days: 39)))] = 'Christi Himmelfahrt';
    holidays[dateKey(easter.add(const Duration(days: 50)))] = 'Pfingstmontag';
    holidays[dateKey(easter.add(const Duration(days: 60)))] = 'Fronleichnam';

    _holidayCacheByYear[year] = holidays;
    return holidays;
  }

  /// Prüft, ob ein gegebenes Datum ein gesetzlicher Feiertag ist.
  static bool isPublicHoliday(DateTime date) {
    final key = _formatDateKey(date);
    if (_customSyncedHolidays.containsKey(key)) return true;
    final holidays = getPublicHolidaysForYear(date.year);
    return holidays.containsKey(key);
  }

  /// Liefert den Namen des Feiertags oder `null`.
  static String? getHolidayName(DateTime date) {
    final key = _formatDateKey(date);
    if (_customSyncedHolidays.containsKey(key)) {
      return _customSyncedHolidays[key];
    }
    final holidays = getPublicHolidaysForYear(date.year);
    return holidays[key];
  }

  /// Prüft, ob ein Datum in einen bundesdeutschen Schulferien-Korridor fällt
  /// (Sommer-, Oster-, Herbst- oder Weihnachtsferien).
  ///
  /// In diesen Zeiträumen ist der werktägliche Freizeitdruck im Wald und an
  /// Gewässern (Familien mit Kindern, Radfahrer, Hunde) spürbar erhöht.
  static bool isSchoolVacation(DateTime date) {
    return getSchoolVacationName(date) != null;
  }

  /// Liefert die Bezeichnung der Ferien oder `null`.
  static String? getSchoolVacationName(DateTime date) {
    final m = date.month;
    final d = date.day;
    final y = date.year;

    // Weihnachtsferien: ca. 23. Dez bis 06. Jan
    if ((m == 12 && d >= 23) || (m == 1 && d <= 6)) {
      return 'Weihnachtsferien';
    }

    // Osterferien: 1 Woche vor bis 1 Woche nach Ostern
    final easter = calculateEasterSunday(y);
    final osterStart = easter.subtract(const Duration(days: 8));
    final osterEnd = easter.add(const Duration(days: 7));
    if (date.isAfter(osterStart) && date.isBefore(osterEnd)) {
      return 'Osterferien';
    }

    // Sommerferien: Kernzeitraum bundesweit (Anfang Juli bis Mitte September)
    if ((m == 7 && d >= 1) || m == 8 || (m == 9 && d <= 15)) {
      return 'Sommerferien';
    }

    // Herbstferien: Mitte bis Ende Oktober
    if (m == 10 && d >= 15 && d <= 31) {
      return 'Herbstferien';
    }

    return null;
  }

  /// Kombinierte Auswertung für ein Datum.
  static HolidayAndVacationInfo getHolidayOrVacationInfo(DateTime date) {
    final holiday = getHolidayName(date);
    final vacation = getSchoolVacationName(date);
    return HolidayAndVacationInfo(
      isHoliday: holiday != null,
      holidayName: holiday,
      isSchoolVacation: vacation != null,
      vacationName: vacation,
    );
  }

  /// Optionaler Online-Sync mit feiertage-api.de (sofern Internetverbindung verfügbar).
  static Future<void> syncFromHolidayApi(int year, {String state = 'ALL'}) async {
    try {
      final uri = Uri.https('feiertage-api.de', '/api/', {
        'jahr': year.toString(),
        if (state != 'ALL') 'nur_land': state,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final val = entry.value;
            if (val is Map<String, dynamic> && val['datum'] != null) {
              final dateStr = val['datum'].toString();
              _customSyncedHolidays[dateStr] = entry.key;
            }
          }
        }
      }
    } catch (_) {
      // Offline-Fallback greift geräuschlos
    }
  }

  static String _formatDateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
