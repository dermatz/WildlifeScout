class WeatherFrame {
  final DateTime time;
  final double temperatureCelsius;
  final double windSpeedKmh;
  final double windGustsKmh;
  final double windDirectionDegrees; // Meteorologische Richtung (woher der Wind kommt)
  final double surfacePressureHpa;
  final double pressureDelta6hHpa; // Negativ = Druck fällt (Fress-Trigger!)
  final int cloudCoverPercent;
  final int cloudCoverLowPercent;
  final int cloudCoverMidPercent;
  final int cloudCoverHighPercent;
  final double? visibilityMeters;
  final String meteorologicalModel;
  final double precipitationMm;
  final int weatherCode;

  const WeatherFrame({
    required this.time,
    required this.temperatureCelsius,
    required this.windSpeedKmh,
    required this.windGustsKmh,
    required this.windDirectionDegrees,
    required this.surfacePressureHpa,
    required this.pressureDelta6hHpa,
    required this.cloudCoverPercent,
    this.cloudCoverLowPercent = 0,
    this.cloudCoverMidPercent = 0,
    this.cloudCoverHighPercent = 0,
    this.visibilityMeters,
    this.meteorologicalModel = 'ECMWF IFS & Open-Meteo',
    required this.precipitationMm,
    this.weatherCode = 0,
  });

  int get effectiveCloudLow =>
      cloudCoverLowPercent > 0 ? cloudCoverLowPercent : (cloudCoverPercent * 0.35).round();

  int get effectiveCloudMid =>
      cloudCoverMidPercent > 0 ? cloudCoverMidPercent : (cloudCoverPercent * 0.45).round();

  int get effectiveCloudHigh =>
      cloudCoverHighPercent > 0 ? cloudCoverHighPercent : (cloudCoverPercent * 0.55).round();

  /// Liefert eine kurze, prägnante Zusammenfassung der 3 Wolkenstockwerke.
  String get cloudStratificationSummary =>
      'Hoch: $effectiveCloudHigh% • Mittel: $effectiveCloudMid% • Tief: $effectiveCloudLow%';

  /// Fotografische Lichtqualität basierend auf Wolkenschichten und Rayleigh-Streuung.
  String get photographicLightQuality {
    if (isFog || (visibilityMeters != null && visibilityMeters! < 1000)) {
      return 'Dichter Bodennebel / Dunstschleier';
    }
    if (effectiveCloudLow >= 75) {
      return 'Diffuses Flachlicht (Tiefe Stratusdecke)';
    }
    if (effectiveCloudMid >= 45) {
      return 'Natürliche Riesen-Softbox (ideal für Porträts)';
    }
    if (effectiveCloudHigh >= 35 && effectiveCloudLow <= 25) {
      return 'Feines Streulicht (Cirren für Abendrot)';
    }
    if (cloudCoverPercent <= 15) {
      return 'Klares, hartes Kontrastlicht';
    }
    return 'Wechselndes Licht / Mischbewölkung';
  }

  /// True, wenn tiefer Hochnebel oder Bodennebel die Fernsicht hemmt.
  bool get isMistyOrLowCeiling =>
      isFog || effectiveCloudLow >= 80 || (visibilityMeters != null && visibilityMeters! < 2500);

  /// True, wenn WMO Weather Code auf Nebel oder Raureifnebel hinweist (WMO 45, 48).
  bool get isFog => weatherCode == 45 || weatherCode == 48;

  /// True, wenn WMO Weather Code auf Gewitter oder Blitze hinweist (WMO 95, 96, 99).
  bool get isThunderstorm => weatherCode >= 95 && weatherCode <= 99;

  /// True, wenn WMO Weather Code auf starken/heftigen Regen oder Schauer hinweist.
  bool get isHeavyRain =>
      weatherCode == 65 ||
      weatherCode == 67 ||
      weatherCode == 81 ||
      weatherCode == 82 ||
      isThunderstorm;

  /// Richtung, in die die Witterung (Geruch des Fotografen) getragen wird.
  double get scentBlowDirectionDegrees => (windDirectionDegrees + 180.0) % 360.0;

  /// Deutsche Himmelsrichtung (woher der Wind weht).
  String get windCardinalLabel {
    const directions = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
    final idx = ((windDirectionDegrees + 22.5) % 360 / 45).floor();
    return directions[idx % 8];
  }
}
