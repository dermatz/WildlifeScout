import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

/// Eine wissenschaftlich fundierte Störungsregel für einen OSM-Wegtyp.
class WayDisturbanceRule {
  final String osmTag;
  final String label;
  final String description;
  final double radiusMeters;
  final double maxPenaltyPercent;
  final double quietBonusDistance;
  final bool rendersRedLine;

  const WayDisturbanceRule({
    required this.osmTag,
    required this.label,
    required this.description,
    required this.radiusMeters,
    required this.maxPenaltyPercent,
    required this.quietBonusDistance,
    required this.rendersRedLine,
  });

  factory WayDisturbanceRule.fromYaml(String osmTag, YamlMap map) {
    return WayDisturbanceRule(
      osmTag: osmTag,
      label: (map['label'] ?? osmTag).toString(),
      description: (map['description'] ?? '').toString(),
      radiusMeters: (map['radius_meters'] as num?)?.toDouble() ?? 25.0,
      maxPenaltyPercent:
          (map['max_penalty_percent'] as num?)?.toDouble() ?? -3.0,
      quietBonusDistance:
          (map['quiet_bonus_distance'] as num?)?.toDouble() ?? 100.0,
      rendersRedLine: map['renders_red_line'] == true,
    );
  }
}

/// Tierartspezifische Empfindlichkeit und Schwellenwerte gegenüber Wegen.
class SpeciesSensitivityRule {
  final String speciesId;
  final String name;
  final double sensitivityMultiplier;
  final double hardAvoidanceDistanceMeters;
  final String note;

  const SpeciesSensitivityRule({
    required this.speciesId,
    required this.name,
    required this.sensitivityMultiplier,
    required this.hardAvoidanceDistanceMeters,
    required this.note,
  });

  factory SpeciesSensitivityRule.fromYaml(String speciesId, YamlMap map) {
    return SpeciesSensitivityRule(
      speciesId: speciesId,
      name: (map['name'] ?? speciesId).toString(),
      sensitivityMultiplier:
          (map['sensitivity_multiplier'] as num?)?.toDouble() ?? 1.0,
      hardAvoidanceDistanceMeters:
          (map['hard_avoidance_distance_meters'] as num?)?.toDouble() ?? 20.0,
      note: (map['note'] ?? '').toString(),
    );
  }
}

/// Zentraler Service zur Auswertung der wildbiologischen Wegenetz- & Störungsmatrix.
///
/// Lädt die Konfiguration aus `assets/config/disturbance_matrix.yaml` und stellt
/// synchrone, hochperformante Zugriffe für die Habitat- und Karten-Engines bereit.
class DisturbanceMatrixService {
  DisturbanceMatrixService._();

  static bool _initialized = false;
  static Map<String, WayDisturbanceRule> _ways = _defaultWays;
  static Map<String, SpeciesSensitivityRule> _speciesSensitivities =
      _defaultSpeciesSensitivities;
  static Map<String, double> _timeModulation = _defaultTimeModulation;
  static double _displayDistanceMeters = 3500.0;
  static int _maxRenderWays = 450;

  /// Lädt die YAML-Konfiguration aus den Flutter-Assets oder einem übergebenen String.
  static Future<void> initialize({String? customYaml}) async {
    try {
      final content = customYaml ??
          await rootBundle.loadString('assets/config/disturbance_matrix.yaml');
      loadFromYamlString(content);
      _initialized = true;
    } catch (_) {
      // Bei Fehlern (z.B. im Unit-Test ohne AssetBundle) bleiben die wissenschaftlichen Defaults aktiv.
      _ways = _defaultWays;
      _speciesSensitivities = _defaultSpeciesSensitivities;
      _timeModulation = _defaultTimeModulation;
      _displayDistanceMeters = 3500.0;
      _maxRenderWays = 450;
    }
  }

  /// Parst einen YAML-String und aktualisiert die aktiven Störungsregeln.
  static void loadFromYamlString(String yamlContent) {
    final doc = loadYaml(yamlContent);
    if (doc is! YamlMap) return;

    final waysRaw = doc['ways'];
    if (waysRaw is YamlMap) {
      final parsedWays = <String, WayDisturbanceRule>{};
      for (final entry in waysRaw.entries) {
        final tag = entry.key.toString();
        final val = entry.value;
        if (val is YamlMap) {
          parsedWays[tag] = WayDisturbanceRule.fromYaml(tag, val);
        }
      }
      if (parsedWays.isNotEmpty) _ways = parsedWays;
    }

    final speciesRaw = doc['species_sensitivity'];
    if (speciesRaw is YamlMap) {
      final parsedSpecies = <String, SpeciesSensitivityRule>{};
      for (final entry in speciesRaw.entries) {
        final spId = entry.key.toString();
        final val = entry.value;
        if (val is YamlMap) {
          parsedSpecies[spId] = SpeciesSensitivityRule.fromYaml(spId, val);
        }
      }
      if (parsedSpecies.isNotEmpty) _speciesSensitivities = parsedSpecies;
    }

    final timeRaw = doc['time_modulation'];
    if (timeRaw is YamlMap) {
      final parsedTime = <String, double>{};
      for (final entry in timeRaw.entries) {
        final key = entry.key.toString();
        final val = entry.value;
        if (val is num) {
          parsedTime[key] = val.toDouble();
        }
      }
      if (parsedTime.isNotEmpty) _timeModulation = parsedTime;
    }

    final mapDisplayRaw = doc['map_display'];
    if (mapDisplayRaw is YamlMap) {
      final dist =
          (mapDisplayRaw['display_distance_meters'] as num?)?.toDouble();
      if (dist != null && dist > 0) _displayDistanceMeters = dist;
      final maxWays = (mapDisplayRaw['max_render_ways'] as num?)?.toInt();
      if (maxWays != null && maxWays > 0) _maxRenderWays = maxWays;
    }

    _initialized = true;
  }

  /// Liefert die Regel für einen OSM-Tag (`highway=*`).
  static WayDisturbanceRule getRule(String osmTag) {
    if (_ways.containsKey(osmTag)) return _ways[osmTag]!;

    // Präfix- und Teil-Matches (z.B. highway=primary_link -> highway=primary)
    if (osmTag.contains('motorway')) return _ways['highway=motorway']!;
    if (osmTag.contains('trunk')) return _ways['highway=trunk']!;
    if (osmTag.contains('primary')) return _ways['highway=primary']!;
    if (osmTag.contains('secondary')) return _ways['highway=secondary']!;
    if (osmTag.contains('tertiary')) return _ways['highway=tertiary']!;
    if (osmTag.contains('cycleway') || osmTag.contains('bicycle')) {
      return _ways['highway=cycleway']!;
    }
    if (osmTag.contains('path') || osmTag.contains('footway')) {
      return _ways['highway=path']!;
    }
    if (osmTag.contains('track') && osmTag.contains('frequented=yes')) {
      return _ways['highway=track;frequented=yes']!;
    }
    if (osmTag.contains('track')) return _ways['highway=track']!;
    if (osmTag.contains('service')) return _ways['highway=service']!;
    if (osmTag.contains('living_street')) {
      return _ways['highway=living_street']!;
    }
    if (osmTag.contains('residential')) return _ways['highway=residential']!;
    if (osmTag.contains('unclassified')) return _ways['highway=unclassified']!;

    return _defaultGenericRule(osmTag);
  }

  /// Berechnet den effektiven Störradius für die Kartendarstellung und Habitatbewertung.
  static double getRadius(String osmTag, {String? speciesId}) {
    final rule = getRule(osmTag);
    if (rule.radiusMeters <= 0.0) return 0.0;

    if (speciesId != null && _speciesSensitivities.containsKey(speciesId)) {
      final sens = _speciesSensitivities[speciesId]!;
      // Radien skalieren moderat mit der artspezifischen Sensitivität (Quadratwurzel-Dämpfung)
      final multiplier = 0.5 + (0.5 * sens.sensitivityMultiplier);
      return (rule.radiusMeters * multiplier).clamp(10.0, 200.0);
    }
    return rule.radiusMeters;
  }

  /// Berechnet den maximalen prozentualen Abzug (% Penalty) am Weg unter
  /// Berücksichtigung von Tierart und Tageszeit/Wochentag.
  static double getEffectivePenaltyPercent(
    String osmTag, {
    String? speciesId,
    DateTime? time,
  }) {
    final rule = getRule(osmTag);
    double penalty = rule.maxPenaltyPercent;

    if (speciesId != null && _speciesSensitivities.containsKey(speciesId)) {
      final sens = _speciesSensitivities[speciesId]!;
      penalty *= sens.sensitivityMultiplier;
    }

    if (time != null) {
      final timeFactor = getTimeModulationFactor(time);
      penalty *= timeFactor;
    }

    return penalty;
  }

  /// Ob dieser Wegtyp auf der Karte als rotes Störungsband visualisiert werden soll.
  static bool shouldRenderRedLine(String osmTag) {
    return getRule(osmTag).rendersRedLine;
  }

  /// Deutsche Beschriftung für den Wegtyp.
  static String getGermanLabel(String osmTag) {
    return getRule(osmTag).label;
  }

  /// Berechnet den zeitlichen Multiplikator für menschlichen Freizeitdruck.
  static double getTimeModulationFactor(DateTime time) {
    final hour = time.hour + (time.minute / 60.0);
    final isWeekend =
        time.weekday == DateTime.saturday || time.weekday == DateTime.sunday;

    // Nachts (21:30 - 05:00): nahezu keine Freizeitstörung
    if (hour >= 21.5 || hour < 5.0) {
      return _timeModulation['nighttime'] ?? 0.08;
    }

    // Morgendämmerung (05:00 - 07:30) & Abenddämmerung (19:30 - 21:30): minimal
    if ((hour >= 5.0 && hour < 7.5) || (hour >= 19.5 && hour < 21.5)) {
      return _timeModulation['dawn_and_dusk'] ?? 0.25;
    }

    // Wochenende tagsüber: Peak-Freizeitdruck (Spaziergänger, E-Biker, Hunde)
    if (isWeekend) {
      if (hour >= 10.5 && hour <= 17.5) {
        return _timeModulation['weekend_afternoon'] ?? 1.45;
      }
      return 1.15;
    }

    // Werktags Feierabend-Spitze (16:30 - 18:30)
    if (hour >= 16.5 && hour <= 18.5) {
      return _timeModulation['weekday_rushhour'] ?? 1.15;
    }

    // Werktags tagsüber (09:00 - 16:30)
    return _timeModulation['weekday_daytime'] ?? 0.90;
  }

  /// Artspezifische K.O.-Meidedistanz in Metern (z.B. 55 m für Rotwild).
  static double? getHardAvoidanceDistance(String speciesId) {
    return _speciesSensitivities[speciesId]?.hardAvoidanceDistanceMeters;
  }

  static double get displayDistanceMeters => _displayDistanceMeters;
  static int get maxRenderWays => _maxRenderWays;
  static Map<String, WayDisturbanceRule> get allWays => Map.unmodifiable(_ways);
  static Map<String, SpeciesSensitivityRule> get allSpeciesSensitivities =>
      Map.unmodifiable(_speciesSensitivities);
  static bool get isInitialized => _initialized;

  // ---------------------------------------------------------------------------
  // Wissenschaftlich fundierte Standard-Werte (Fallback & Unit-Test-Sicherheit)
  // ---------------------------------------------------------------------------

  static WayDisturbanceRule _defaultGenericRule(String tag) {
    return WayDisturbanceRule(
      osmTag: tag,
      label: tag,
      description: 'Sonstiger Weg',
      radiusMeters: 25.0,
      maxPenaltyPercent: -2.5,
      quietBonusDistance: 80.0,
      rendersRedLine: false,
    );
  }

  static const Map<String, WayDisturbanceRule> _defaultWays = {
    'highway=motorway': WayDisturbanceRule(
      osmTag: 'highway=motorway',
      label: 'Autobahn',
      description: 'Permanenter Schallteppich, massive Zerschneidung',
      radiusMeters: 150.0,
      maxPenaltyPercent: -25.0,
      quietBonusDistance: 350.0,
      rendersRedLine: true,
    ),
    'highway=trunk': WayDisturbanceRule(
      osmTag: 'highway=trunk',
      label: 'Schnellstraße / Kraftfahrstraße',
      description: 'Hohe Fahrgeschwindigkeiten, stetiger Verkehrsfluss',
      radiusMeters: 110.0,
      maxPenaltyPercent: -20.0,
      quietBonusDistance: 280.0,
      rendersRedLine: true,
    ),
    'highway=primary': WayDisturbanceRule(
      osmTag: 'highway=primary',
      label: 'Bundesstraße',
      description: 'Starker Berufs- & Schwerlastverkehr',
      radiusMeters: 85.0,
      maxPenaltyPercent: -16.0,
      quietBonusDistance: 220.0,
      rendersRedLine: true,
    ),
    'highway=secondary': WayDisturbanceRule(
      osmTag: 'highway=secondary',
      label: 'Landesstraße / Staatsstraße',
      description: 'Regelmäßiger Durchgangsverkehr',
      radiusMeters: 70.0,
      maxPenaltyPercent: -13.0,
      quietBonusDistance: 180.0,
      rendersRedLine: true,
    ),
    'highway=tertiary': WayDisturbanceRule(
      osmTag: 'highway=tertiary',
      label: 'Kreisstraße',
      description: 'Mäßiger lokaler Durchgangsverkehr',
      radiusMeters: 55.0,
      maxPenaltyPercent: -10.0,
      quietBonusDistance: 150.0,
      rendersRedLine: true,
    ),
    'highway=unclassified': WayDisturbanceRule(
      osmTag: 'highway=unclassified',
      label: 'Verbindungsstraße',
      description: 'Gemeindeverbindungsstraße',
      radiusMeters: 45.0,
      maxPenaltyPercent: -8.0,
      quietBonusDistance: 120.0,
      rendersRedLine: true,
    ),
    'highway=residential': WayDisturbanceRule(
      osmTag: 'highway=residential',
      label: 'Wohnstraße',
      description: 'Anwohnerverkehr, Fußgänger am Ortsrand',
      radiusMeters: 40.0,
      maxPenaltyPercent: -7.0,
      quietBonusDistance: 110.0,
      rendersRedLine: true,
    ),
    'highway=cycleway': WayDisturbanceRule(
      osmTag: 'highway=cycleway',
      label: 'Ausgewiesener Radweg',
      description: 'Schneller Rad- & E-Bike-Verkehr',
      radiusMeters: 65.0,
      maxPenaltyPercent: -9.0,
      quietBonusDistance: 160.0,
      rendersRedLine: true,
    ),
    'highway=bridleway': WayDisturbanceRule(
      osmTag: 'highway=bridleway',
      label: 'Reitweg',
      description: 'Pferdeverkehr, Geruch & Bodenerschütterung',
      radiusMeters: 35.0,
      maxPenaltyPercent: -4.0,
      quietBonusDistance: 90.0,
      rendersRedLine: true,
    ),
    'highway=path': WayDisturbanceRule(
      osmTag: 'highway=path',
      label: 'Frequentierter Wander- & Spazierpfad',
      description: 'Regelmäßiger Fußverkehr, Spaziergänger mit Hunden',
      radiusMeters: 45.0,
      maxPenaltyPercent: -6.5,
      quietBonusDistance: 130.0,
      rendersRedLine: true,
    ),
    'highway=footway': WayDisturbanceRule(
      osmTag: 'highway=footway',
      label: 'Ausgewiesener Fußweg',
      description: 'Spazierweg, Trittschall & menschliche Witterung',
      radiusMeters: 40.0,
      maxPenaltyPercent: -6.0,
      quietBonusDistance: 120.0,
      rendersRedLine: true,
    ),
    'highway=track;frequented=yes': WayDisturbanceRule(
      osmTag: 'highway=track;frequented=yes',
      label: 'Befestigter Wirtschaftsweg',
      description: 'Befestigter/benannter Flurweg mit Rad- & Freizeitverkehr',
      radiusMeters: 28.0,
      maxPenaltyPercent: -4.5,
      quietBonusDistance: 85.0,
      rendersRedLine: true,
    ),
    'highway=track': WayDisturbanceRule(
      osmTag: 'highway=track',
      label: 'Ruhiger Feldrain / Ackerfahrspur',
      description: 'Reine Parzellengrenzen & Traktorspuren ohne Freizeitverkehr',
      radiusMeters: 0.0,
      maxPenaltyPercent: 0.0,
      quietBonusDistance: 20.0,
      rendersRedLine: false,
    ),
    'highway=service': WayDisturbanceRule(
      osmTag: 'highway=service',
      label: 'Zufahrtsweg',
      description: 'Zufahrt zu Höfen oder Forsthütten',
      radiusMeters: 25.0,
      maxPenaltyPercent: -3.5,
      quietBonusDistance: 70.0,
      rendersRedLine: false,
    ),
    'highway=living_street': WayDisturbanceRule(
      osmTag: 'highway=living_street',
      label: 'Verkehrsberuhigter Bereich',
      description: 'Spielstraße / Naherholungsbereich',
      radiusMeters: 30.0,
      maxPenaltyPercent: -4.0,
      quietBonusDistance: 80.0,
      rendersRedLine: false,
    ),
  };

  static const Map<String, SpeciesSensitivityRule>
      _defaultSpeciesSensitivities = {
    'red_deer': SpeciesSensitivityRule(
      speciesId: 'red_deer',
      name: 'Rotwild',
      sensitivityMultiplier: 1.85,
      hardAvoidanceDistanceMeters: 55.0,
      note: 'Hochgradig scheues Steppentier; meidet Wege im Freiland extrem.',
    ),
    'roe_deer': SpeciesSensitivityRule(
      speciesId: 'roe_deer',
      name: 'Rehwild',
      sensitivityMultiplier: 1.0,
      hardAvoidanceDistanceMeters: 18.0,
      note: 'Schlüpfertyp; toleriert berechenbaren Verkehr.',
    ),
    'wild_boar': SpeciesSensitivityRule(
      speciesId: 'wild_boar',
      name: 'Schwarzwild',
      sensitivityMultiplier: 0.9,
      hardAvoidanceDistanceMeters: 25.0,
      note: 'Tageseinstand in Dickung fast weg-unempfindlich.',
    ),
    'red_fox': SpeciesSensitivityRule(
      speciesId: 'red_fox',
      name: 'Rotfuchs',
      sensitivityMultiplier: 0.65,
      hardAvoidanceDistanceMeters: 12.0,
      note: 'Kulturfolger; nutzt Wege in der Dämmerung aktiv.',
    ),
    'badger': SpeciesSensitivityRule(
      speciesId: 'badger',
      name: 'Dachs',
      sensitivityMultiplier: 1.15,
      hardAvoidanceDistanceMeters: 20.0,
      note: 'Trittschallempfindlich am Bau.',
    ),
    'kingfisher': SpeciesSensitivityRule(
      speciesId: 'kingfisher',
      name: 'Eisvogel',
      sensitivityMultiplier: 1.3,
      hardAvoidanceDistanceMeters: 30.0,
      note: 'Flieht bei Annäherung am Gewässersaum.',
    ),
  };

  static const Map<String, double> _defaultTimeModulation = {
    'weekend_afternoon': 1.45,
    'weekday_daytime': 0.90,
    'weekday_rushhour': 1.15,
    'dawn_and_dusk': 0.25,
    'nighttime': 0.08,
  };
}
