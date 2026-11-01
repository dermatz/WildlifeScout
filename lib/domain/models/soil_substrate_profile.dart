enum SoilDiggability {
  optimalDryDiggable('Top grabfähig & trocken (Sand/Löss/Braunerde)'),
  moderateLoam('Gut grabfähig (Lehm/Schluff)'),
  rockyOrHeavyClay('Schwer grabbar (Fels/Stein/Schwerer Ton)'),
  waterloggedOrPeat('Staunass / Grundwassernah (Moor/Gley/Aue)'),
  unknown('Standard-Waldboden');

  final String label;
  const SoilDiggability(this.label);
}

class TerrainSlopeSample {
  final double elevationMeters;
  final double slopeDegrees;
  final String aspectCardinal; // Wohin der Hang abfällt (z. B. "SO", "SW")

  const TerrainSlopeSample({
    required this.elevationMeters,
    required this.slopeDegrees,
    required this.aspectCardinal,
  });

  bool get isSloped => slopeDegrees >= 3.0;

  String get compactLabel {
    if (slopeDegrees < 2.0) {
      return 'Flach (${elevationMeters.round()}m ü.NN)';
    }
    return 'Hang ${slopeDegrees.toStringAsFixed(1)}° ($aspectCardinal)';
  }
}

class SoilSubstrateProfile {
  final String shortLabel;
  final String fullGeologicalDescription;
  final String dataSource; // z. B. "BGR BÜK200" oder "ISRIC SoilGrids"
  final SoilDiggability diggability;
  final double? sandPercent;
  final double? siltPercent;
  final double? clayPercent;

  const SoilSubstrateProfile({
    required this.shortLabel,
    required this.fullGeologicalDescription,
    required this.dataSource,
    required this.diggability,
    this.sandPercent,
    this.siltPercent,
    this.clayPercent,
  });

  /// Score-Anpassung für Höhlengräber (Dachs / Rotfuchs) bzw. Suhlen-Liebhaber (Schwarzwild).
  double scoreAdjustmentForSpecies(String speciesId, {required bool isBurrowRefuge}) {
    if (speciesId == 'badger' || speciesId == 'red_fox') {
      switch (diggability) {
        case SoilDiggability.optimalDryDiggable:
          return isBurrowRefuge ? 5.5 : 2.5;
        case SoilDiggability.moderateLoam:
          return isBurrowRefuge ? 2.5 : 2.0;
        case SoilDiggability.rockyOrHeavyClay:
          return isBurrowRefuge ? -5.5 : -1.0;
        case SoilDiggability.waterloggedOrPeat:
          // Staunässe/Moor im Untergrund ist für Dachs- und Fuchsbaue extrem ungünstig
          return isBurrowRefuge ? -11.0 : 1.0;
        case SoilDiggability.unknown:
          return 0.0;
      }
    } else if (speciesId == 'wild_boar') {
      // Schwarzwild liebt grundwassernahe Gleye, Auenböden und Moore zum Suhlen & Brechen
      if (diggability == SoilDiggability.waterloggedOrPeat) {
        return 4.5;
      }
      if (diggability == SoilDiggability.optimalDryDiggable ||
          diggability == SoilDiggability.moderateLoam) {
        return 2.0;
      }
    }
    return 0.0;
  }
}
