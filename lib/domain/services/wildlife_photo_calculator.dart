import '../models/photo_gear_profile.dart';
import '../models/species_profile.dart';

/// Risikoeinschätzung der Annäherungsdistanz im Vergleich zur Fluchtdistanz.
enum FlightDistanceStatus {
  /// Fotodistanz liegt komfortabel außerhalb der Fluchtdistanz.
  safe(
    label: 'Freiland-Distanz möglich',
    badgeColorHex: '#10B981',
    description: 'Du bleibst außerhalb der Fluchtdistanz und störst das Tier nicht.',
  ),

  /// Fotodistanz liegt im Nahbereich der Fluchtdistanz.
  borderline(
    label: 'Grenzbereich zur Fluchtdistanz',
    badgeColorHex: '#F59E0B',
    description: 'Sehr langsame Annäherung, Windrichtung und natürliche Deckung zwingend beachten.',
  ),

  /// Fotodistanz liegt deutlich innerhalb der Fluchtdistanz.
  hideRecommended(
    label: 'Tarnzelt / Versteck empfohlen',
    badgeColorHex: '#EF4444',
    description: 'Für diese Bildgröße musst du näher heran als die Fluchtdistanz erlaubt. Ein stationäres Tarnzelt oder Tarnnetz ist erforderlich.',
  );

  final String label;
  final String badgeColorHex;
  final String description;

  const FlightDistanceStatus({
    required this.label,
    required this.badgeColorHex,
    required this.description,
  });
}

/// Ergebnis der Brennweiten- & Distanzberechnung für eine konkrete Wildart.
class WildlifeFramingAnalysis {
  /// Distanz für ein formatfüllendes Nahporträt / Kopfstudie (in Metern)
  final double portraitDistanceMeters;

  /// Distanz für eine Ganzkörper-Aufnahme mit Biotop-Rand (in Metern)
  final double fullBodyDistanceMeters;

  /// Distanz für eine Umgebungs- / Habitataufnahme (in Metern)
  final double habitatDistanceMeters;

  /// Fluchtdistanz der jeweiligen Art (in Metern)
  final double flightDistanceMeters;

  /// Status der Ganzkörper-Fotodistanz im Vergleich zur Fluchtdistanz
  final FlightDistanceStatus fullBodyStatus;

  /// Status der Nahporträt-Distanz im Vergleich zur Fluchtdistanz
  final FlightDistanceStatus portraitStatus;

  /// Schärfentiefe bei Ganzkörper-Distanz (in Zentimetern)
  final double dofAtFullBodyCm;

  /// Schärfentiefe bei Porträt-Distanz (in Zentimetern)
  final double dofAtPortraitCm;

  /// Sichtfeld-Breite bei der Fluchtdistanz (in Metern)
  final double fieldWidthAtFlightDistanceMeters;

  /// Geschätzte Motiv-Höhe (in Metern)
  final double estimatedSubjectHeightMeters;

  /// Spezifische Praxis-Empfehlung für den Fotografen
  final String practicalRecommendation;

  const WildlifeFramingAnalysis({
    required this.portraitDistanceMeters,
    required this.fullBodyDistanceMeters,
    required this.habitatDistanceMeters,
    required this.flightDistanceMeters,
    required this.fullBodyStatus,
    required this.portraitStatus,
    required this.dofAtFullBodyCm,
    required this.dofAtPortraitCm,
    required this.fieldWidthAtFlightDistanceMeters,
    required this.estimatedSubjectHeightMeters,
    required this.practicalRecommendation,
  });
}

/// Verschlusszeiten-Leitfaden für die jeweilige Art & Bewegungsart.
class WildlifeShutterGuide {
  final String restingShutter;
  final String restingNote;
  final String movingShutter;
  final String movingNote;
  final String actionShutter;
  final String actionNote;
  final String duskLightAdvice;

  const WildlifeShutterGuide({
    required this.restingShutter,
    required this.restingNote,
    required this.movingShutter,
    required this.movingNote,
    required this.actionShutter,
    required this.actionNote,
    required this.duskLightAdvice,
  });
}

/// Reine Business-Logik zur Berechnung fotophysikalischer Kenngrößen
/// für Wildtiere (Clean Architecture & entkoppelt von UI).
class WildlifePhotoCalculator {
  /// Ermittelt die typische Körperhöhe des Motivs in Metern
  static double estimateSubjectHeightMeters(SpeciesProfile species) {
    switch (species.id) {
      case 'kingfisher':
        return 0.17; // 17 cm
      case 'badger':
        return 0.32; // 32 cm Schulterhöhe
      case 'red_fox':
        return 0.38; // 38 cm Schulterhöhe
      case 'roe_deer':
        return 0.72; // 72 cm Schulterhöhe
      case 'wild_boar':
        return 0.85; // 85 cm Rückenhöhe
      case 'red_deer':
        return 1.35; // 135 cm Schulterhöhe
      default:
        // Text-Heuristik aus openData.bodySize
        final text = species.openData.bodySize.toLowerCase();
        if (text.contains('120') || text.contains('150') || text.contains('hirsch')) {
          return 1.35;
        }
        if (text.contains('schulterhöhe') || text.contains('70') || text.contains('80')) {
          return 0.75;
        }
        if (text.contains('16') || text.contains('vogel') || text.contains('20 cm')) {
          return 0.18;
        }
        return 0.60;
    }
  }

  /// Berechnet die Bildausschnitt- und Distanzanalyse für das gegebene Setup.
  static WildlifeFramingAnalysis calculateFramingAnalysis({
    required SpeciesProfile species,
    required PhotoGearProfile gear,
  }) {
    final subjectHeightM = estimateSubjectHeightMeters(species);
    final sensorHeightM = gear.sensorFormat.sensorHeightMm / 1000.0;
    final focalLengthM = gear.opticalFocalLengthMm / 1000.0;
    final flightDistM = species.behavior.flightDistanceMeters;

    // 1. Distanz für Ganzkörper (Tier füllt ca. 35 % der Sensor-Höhe)
    // d = f * (H_subject / (0.35 * H_sensor))
    const fullBodyFillRatio = 0.35;
    final fullBodyDistance =
        focalLengthM * (subjectHeightM / (fullBodyFillRatio * sensorHeightM));

    // 2. Distanz für Nahporträt / Kopfstudie (Kopfpartie ~ 40 % der Tierhöhe füllt 50 % des Sensors)
    final headHeightM = subjectHeightM * 0.45;
    const portraitFillRatio = 0.50;
    final portraitDistance =
        focalLengthM * (headHeightM / (portraitFillRatio * sensorHeightM));

    // 3. Distanz für Biotop- / Habitataufnahme (Tier füllt ca. 15 % der Sensor-Höhe)
    const habitatFillRatio = 0.15;
    final habitatDistance =
        focalLengthM * (subjectHeightM / (habitatFillRatio * sensorHeightM));

    // Status-Klassifizierung
    final fullBodyStatus = _evaluateStatus(fullBodyDistance, flightDistM);
    final portraitStatus = _evaluateStatus(portraitDistance, flightDistM);

    // Schärfentiefe
    final dofFullBody = gear.depthOfFieldCm(fullBodyDistance);
    final dofPortrait = gear.depthOfFieldCm(portraitDistance);

    // Sichtbreite bei Fluchtdistanz
    final fieldWidthAtFlight = gear.fieldWidthAtDistanceMeters(flightDistM);

    // Praxis-Empfehlung formulieren
    final recommendation = _buildRecommendation(
      species: species,
      gear: gear,
      fullBodyDist: fullBodyDistance,
      portraitDist: portraitDistance,
      flightDist: flightDistM,
      fullBodyStatus: fullBodyStatus,
    );

    return WildlifeFramingAnalysis(
      portraitDistanceMeters: portraitDistance,
      fullBodyDistanceMeters: fullBodyDistance,
      habitatDistanceMeters: habitatDistance,
      flightDistanceMeters: flightDistM,
      fullBodyStatus: fullBodyStatus,
      portraitStatus: portraitStatus,
      dofAtFullBodyCm: dofFullBody,
      dofAtPortraitCm: dofPortrait,
      fieldWidthAtFlightDistanceMeters: fieldWidthAtFlight,
      estimatedSubjectHeightMeters: subjectHeightM,
      practicalRecommendation: recommendation,
    );
  }

  static FlightDistanceStatus _evaluateStatus(double photoDist, double flightDist) {
    if (photoDist >= flightDist * 1.15) {
      return FlightDistanceStatus.safe;
    } else if (photoDist >= flightDist * 0.85) {
      return FlightDistanceStatus.borderline;
    } else {
      return FlightDistanceStatus.hideRecommended;
    }
  }

  static String _buildRecommendation({
    required SpeciesProfile species,
    required PhotoGearProfile gear,
    required double fullBodyDist,
    required double portraitDist,
    required double flightDist,
    required FlightDistanceStatus fullBodyStatus,
  }) {
    final effFocal = gear.effectiveFocalLengthMm.round();
    final fullBodyRounded = fullBodyDist.round();
    final flightRounded = flightDist.round();

    if (fullBodyStatus == FlightDistanceStatus.safe) {
      return 'Mit deinem $effFocal mm Kleinbild-Setup erreichst du bei $fullBodyRounded m eine hervorragende Ganzkörper-Abbildung und bleibst mit Respektabstand außerhalb der Fluchtdistanz ($flightRounded m). Freiland-Fotografie ohne festes Tarnzelt gut machbar!';
    } else if (fullBodyStatus == FlightDistanceStatus.borderline) {
      return 'Bei $fullBodyRounded m Distanz befindest du dich genau an der Wahrnehmungsgrenze der Art ($flightRounded m). Ruhige Körperhaltung, gute natürliche Deckung am Waldrand und der Windrichtungskegel sind hier erfolgsentscheidend.';
    } else {
      return 'Für eine formatfüllende Abbildung ($fullBodyRounded m) müsstest du näher heran als die Fluchtdistanz ($flightRounded m) erlaubt. Ohne stationäres Tarnzelt, Hide oder Telekonverter wird das Tier vorher flüchten.';
    }
  }

  /// Berechnet Empfehlungen für Verschlusszeiten und Dämmerungs-Tauglichkeit.
  static WildlifeShutterGuide calculateShutterGuide({
    required SpeciesProfile species,
    required PhotoGearProfile gear,
  }) {
    final isBird = species.category == SpeciesCategory.waterfowl ||
        species.category == SpeciesCategory.raptor ||
        species.id == 'kingfisher';

    final restingSpeed = isBird ? '1/500 – 1/800 s' : '1/250 – 1/500 s';
    final restingNote = isBird
        ? 'Sitzend auf Ansitzast oder Stein (Kopfbewegungen ausgleichen)'
        : 'Ruhig stehend, äsend oder wiederkäuend';

    final movingSpeed = isBird ? '1/1600 – 1/2000 s' : '1/1000 – 1/1250 s';
    final movingNote = isBird
        ? 'Gefiederputzen, Rüttelflug oder Landeanflug'
        : 'Zügiges Ziehen am Waldsaum oder Sicherungsverhalten';

    final actionSpeed = isBird ? '1/3200 – 1/4000 s' : '1/2000 – 1/2500 s';
    final actionNote = isBird
        ? 'Sturztauchgang, Beuteflug oder schnelles Abstreichen'
        : 'Flucht, Brunftkampf oder plötzliche Fluchtbewegung';

    // Dämmerungs-Ratschlag basierend auf der effektiven Blende
    final effAperture = gear.effectiveAperture;
    String duskAdvice;
    if (effAperture <= 3.2) {
      duskAdvice =
          'Hervorragende Lichtstärke (f/${effAperture.toStringAsFixed(1)}): Ideal für die frühe Morgen- und späte Abenddämmerung bei moderaten ISO-Werten.';
    } else if (effAperture <= 5.6) {
      duskAdvice =
          'Solide Allround-Lichtstärke (f/${effAperture.toStringAsFixed(1)}): In der blauen Stunde empfiehlt sich ein Einbein- oder Dreibeinstativ, um die Verschlusszeit stabil zu halten.';
    } else {
      duskAdvice =
          'Lichtschwächeres Setup (f/${effAperture.toStringAsFixed(1)}): In der Dämmerung steigen die ISO-Werte rasch über 6400. Konzentriere dich auf ruhige Momente bei 1/250 s.';
    }

    return WildlifeShutterGuide(
      restingShutter: restingSpeed,
      restingNote: restingNote,
      movingShutter: movingSpeed,
      movingNote: movingNote,
      actionShutter: actionSpeed,
      actionNote: actionNote,
      duskLightAdvice: duskAdvice,
    );
  }
}
