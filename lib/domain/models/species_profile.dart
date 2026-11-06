import 'dart:ui';

enum SpeciesCategory {
  ungulate('Schalenwild'),
  carnivore('Raubwild'),
  waterfowl('Wasser- & Ansitzvögel'),
  raptor('Greife & Eulen');

  final String label;
  const SpeciesCategory(this.label);

  static SpeciesCategory fromString(String value) {
    return SpeciesCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SpeciesCategory.ungulate,
    );
  }
}

enum ActivityPeriod {
  dawn('Morgendämmerung'),
  day('Tagsüber'),
  dusk('Abenddämmerung'),
  night('Nacht / Mondlicht');

  final String label;
  const ActivityPeriod(this.label);

  static ActivityPeriod fromString(String value) {
    return ActivityPeriod.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ActivityPeriod.dawn,
    );
  }
}

class BehaviorProfile {
  final double scentSensitivityMeters;
  final double scentConeAngleDegrees;
  final List<ActivityPeriod> primaryActivityPeriods;
  final double barometerDropSensitivity;
  final double maxToleratedWindSpeedKmh;
  final double flightDistanceMeters;

  const BehaviorProfile({
    required this.scentSensitivityMeters,
    required this.scentConeAngleDegrees,
    required this.primaryActivityPeriods,
    required this.barometerDropSensitivity,
    required this.maxToleratedWindSpeedKmh,
    required this.flightDistanceMeters,
  });

  factory BehaviorProfile.fromJson(Map<String, dynamic> json) {
    final periodsRaw = (json['primaryActivityPeriods'] as List<dynamic>? ?? []);
    return BehaviorProfile(
      scentSensitivityMeters:
          (json['scentSensitivityMeters'] as num?)?.toDouble() ?? 200.0,
      scentConeAngleDegrees:
          (json['scentConeAngleDegrees'] as num?)?.toDouble() ?? 45.0,
      primaryActivityPeriods: periodsRaw
          .map((e) => ActivityPeriod.fromString(e.toString()))
          .toList(),
      barometerDropSensitivity:
          (json['barometerDropSensitivity'] as num?)?.toDouble() ?? 0.5,
      maxToleratedWindSpeedKmh:
          (json['maxToleratedWindSpeedKmh'] as num?)?.toDouble() ?? 45.0,
      flightDistanceMeters:
          (json['flightDistanceMeters'] as num?)?.toDouble() ?? 100.0,
    );
  }
}

/// Offene wildbiologische & ökologische Kennzahlen (IUCN / GBIF / Wildtier-Monitoring)
class SpeciesOpenData {
  final String taxonomy;
  final String conservationStatus;
  final String bodyWeight;
  final String bodySize;
  final String homeRange;
  final String peakSeason;
  final String diet;
  final String tracksAndSigns;
  final String vocalizations;
  final String sensoryStrengths;
  final String recommendedLens;

  const SpeciesOpenData({
    this.taxonomy = '',
    this.conservationStatus = 'LC – Nicht gefährdet (IUCN)',
    this.bodyWeight = '',
    this.bodySize = '',
    this.homeRange = '',
    this.peakSeason = '',
    this.diet = '',
    this.tracksAndSigns = '',
    this.vocalizations = '',
    this.sensoryStrengths = '',
    this.recommendedLens = '400–600 mm Teleobjektiv',
  });

  factory SpeciesOpenData.fromJson(Map<String, dynamic> json) {
    return SpeciesOpenData(
      taxonomy: json['taxonomy']?.toString() ?? '',
      conservationStatus:
          json['conservationStatus']?.toString() ??
          'LC – Nicht gefährdet (IUCN)',
      bodyWeight: json['bodyWeight']?.toString() ?? '',
      bodySize: json['bodySize']?.toString() ?? '',
      homeRange: json['homeRange']?.toString() ?? '',
      peakSeason: json['peakSeason']?.toString() ?? '',
      diet: json['diet']?.toString() ?? '',
      tracksAndSigns: json['tracksAndSigns']?.toString() ?? '',
      vocalizations: json['vocalizations']?.toString() ?? '',
      sensoryStrengths: json['sensoryStrengths']?.toString() ?? '',
      recommendedLens:
          json['recommendedLens']?.toString() ?? '400–600 mm Teleobjektiv',
    );
  }
}

/// Einzelne charakteristische Verhaltensweise im Tages- oder Jahreslauf
class SpeciesBehaviorTrait {
  final String title;
  final String tag;
  final String description;

  const SpeciesBehaviorTrait({
    required this.title,
    required this.tag,
    required this.description,
  });

  factory SpeciesBehaviorTrait.fromJson(Map<String, dynamic> json) {
    return SpeciesBehaviorTrait(
      title: json['title']?.toString() ?? '',
      tag: json['tag']?.toString() ?? 'Verhalten',
      description: json['description']?.toString() ?? '',
    );
  }
}

class EdgeRule {
  final String typeA;
  final String typeB;
  final double bufferMeters;
  final double scoreBoost;
  final String label;

  const EdgeRule({
    required this.typeA,
    required this.typeB,
    required this.bufferMeters,
    required this.scoreBoost,
    required this.label,
  });

  factory EdgeRule.fromJson(Map<String, dynamic> json) {
    return EdgeRule(
      typeA: json['typeA']?.toString() ?? '',
      typeB: json['typeB']?.toString() ?? '',
      bufferMeters: (json['bufferMeters'] as num?)?.toDouble() ?? 50.0,
      scoreBoost: (json['scoreBoost'] as num?)?.toDouble() ?? 3.0,
      label: json['label']?.toString() ?? 'Saumbiotop / Waldrand',
    );
  }
}

class LanduseWeight {
  final String osmTag;
  final double score;
  final String label;

  const LanduseWeight({
    required this.osmTag,
    required this.score,
    required this.label,
  });

  factory LanduseWeight.fromJson(Map<String, dynamic> json) {
    return LanduseWeight(
      osmTag: json['osmTag']?.toString() ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 1.0,
      label: json['label']?.toString() ?? '',
    );
  }
}

class DisturbancePenalty {
  final String osmTag;
  final double radiusMeters;
  final double penaltyScore;
  final String label;

  const DisturbancePenalty({
    required this.osmTag,
    required this.radiusMeters,
    required this.penaltyScore,
    required this.label,
  });

  factory DisturbancePenalty.fromJson(Map<String, dynamic> json) {
    return DisturbancePenalty(
      osmTag: json['osmTag']?.toString() ?? '',
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 80.0,
      penaltyScore: (json['penaltyScore'] as num?)?.toDouble() ?? -5.0,
      label: json['label']?.toString() ?? 'Weg / Störungszone',
    );
  }
}

class WaterProximityRule {
  final double maxDistanceMeters;
  final double scoreBoost;

  const WaterProximityRule({
    required this.maxDistanceMeters,
    required this.scoreBoost,
  });

  factory WaterProximityRule.fromJson(Map<String, dynamic> json) {
    return WaterProximityRule(
      maxDistanceMeters:
          (json['maxDistanceMeters'] as num?)?.toDouble() ?? 250.0,
      scoreBoost: (json['scoreBoost'] as num?)?.toDouble() ?? 2.0,
    );
  }
}

class HabitatRules {
  final List<EdgeRule> edgePreferences;
  final List<LanduseWeight> landuseWeights;
  final List<DisturbancePenalty> disturbancePenalties;
  final WaterProximityRule? waterProximity;
  final double minContiguousAreaHectares;

  const HabitatRules({
    required this.edgePreferences,
    required this.landuseWeights,
    required this.disturbancePenalties,
    this.waterProximity,
    required this.minContiguousAreaHectares,
  });

  factory HabitatRules.fromJson(Map<String, dynamic> json) {
    final edgesRaw = json['edgePreferences'] as List<dynamic>? ?? [];
    final landuseRaw = json['landuseWeights'] as List<dynamic>? ?? [];
    final penaltiesRaw = json['disturbancePenalties'] as List<dynamic>? ?? [];

    return HabitatRules(
      edgePreferences: edgesRaw
          .map((e) => EdgeRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      landuseWeights: landuseRaw
          .map((e) => LanduseWeight.fromJson(e as Map<String, dynamic>))
          .toList(),
      disturbancePenalties: penaltiesRaw
          .map((e) => DisturbancePenalty.fromJson(e as Map<String, dynamic>))
          .toList(),
      waterProximity: json['waterProximity'] != null
          ? WaterProximityRule.fromJson(
              json['waterProximity'] as Map<String, dynamic>,
            )
          : null,
      minContiguousAreaHectares:
          (json['minContiguousAreaHectares'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class SpeciesProfile {
  final String id;
  final String name;

  /// Optionaler Kurzname für platzkritische UI (z. B. Header-Button).
  final String? shortName;
  final String scientificName;
  final SpeciesCategory category;
  final String shortDescription;
  final Color accentColor;
  final String imageAssetPath;
  final String imageUrl;
  final String imageAuthor;
  final String imageLicense;
  final String imageSourceUrl;
  final BehaviorProfile behavior;
  final SpeciesOpenData openData;
  final List<SpeciesBehaviorTrait> behaviorTraits;
  final HabitatRules habitatRules;
  final List<String> fieldTips;

  const SpeciesProfile({
    required this.id,
    required this.name,
    this.shortName,
    required this.scientificName,
    required this.category,
    required this.shortDescription,
    required this.accentColor,
    this.imageAssetPath = '',
    this.imageUrl = '',
    this.imageAuthor = '',
    this.imageLicense = 'Unsplash License (Lizenzfrei & frei nutzbar)',
    this.imageSourceUrl = '',
    required this.behavior,
    this.openData = const SpeciesOpenData(),
    this.behaviorTraits = const [],
    required this.habitatRules,
    required this.fieldTips,
  });

  /// Anzeigename für kompakte Elemente – fällt auf [name] zurück.
  String get displayShortName => shortName ?? name;

  factory SpeciesProfile.fromJson(Map<String, dynamic> json) {
    final hex = (json['accentColorHex']?.toString() ?? '#10B981').replaceFirst(
      '#',
      '',
    );
    final colorValue = int.tryParse('FF$hex', radix: 16) ?? 0xFF10B981;
    final id = json['id']?.toString() ?? 'unknown';
    final traitsRaw = json['behaviorTraits'] as List<dynamic>? ?? [];

    return SpeciesProfile(
      id: id,
      name: json['name']?.toString() ?? 'Unbekannt',
      shortName: (json['shortName']?.toString().trim().isEmpty ?? true)
          ? null
          : json['shortName'].toString().trim(),
      scientificName: json['scientificName']?.toString() ?? '',
      category: SpeciesCategory.fromString(
        json['category']?.toString() ?? 'ungulate',
      ),
      shortDescription: json['shortDescription']?.toString() ?? '',
      accentColor: Color(colorValue),
      imageAssetPath:
          json['imageAssetPath']?.toString() ?? 'assets/species/images/$id.jpg',
      imageUrl: json['imageUrl']?.toString() ?? '',
      imageAuthor: json['imageAuthor']?.toString() ?? 'Unsplash Wildlife',
      imageLicense:
          json['imageLicense']?.toString() ??
          'Unsplash License (Lizenzfrei & frei nutzbar)',
      imageSourceUrl: json['imageSourceUrl']?.toString() ?? '',
      behavior: BehaviorProfile.fromJson(
        json['behavior'] as Map<String, dynamic>? ?? {},
      ),
      openData: SpeciesOpenData.fromJson(
        json['openData'] as Map<String, dynamic>? ?? {},
      ),
      behaviorTraits: traitsRaw
          .map((e) => SpeciesBehaviorTrait.fromJson(e as Map<String, dynamic>))
          .toList(),
      habitatRules: HabitatRules.fromJson(
        json['habitatRules'] as Map<String, dynamic>? ?? {},
      ),
      fieldTips: (json['fieldTips'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
