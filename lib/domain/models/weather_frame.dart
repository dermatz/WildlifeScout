class WeatherFrame {
  final DateTime time;
  final double temperatureCelsius;
  final double windSpeedKmh;
  final double windGustsKmh;
  final double windDirectionDegrees; // Meteorologische Richtung (woher der Wind kommt)
  final double surfacePressureHpa;
  final double pressureDelta6hHpa; // Negativ = Druck fällt (Fress-Trigger!)
  final int cloudCoverPercent;
  final double precipitationMm;

  const WeatherFrame({
    required this.time,
    required this.temperatureCelsius,
    required this.windSpeedKmh,
    required this.windGustsKmh,
    required this.windDirectionDegrees,
    required this.surfacePressureHpa,
    required this.pressureDelta6hHpa,
    required this.cloudCoverPercent,
    required this.precipitationMm,
  });

  /// Richtung, in die die Witterung (Geruch des Fotografen) getragen wird.
  double get scentBlowDirectionDegrees => (windDirectionDegrees + 180.0) % 360.0;

  /// Deutsche Himmelsrichtung (woher der Wind weht).
  String get windCardinalLabel {
    const directions = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
    final idx = ((windDirectionDegrees + 22.5) % 360 / 45).floor();
    return directions[idx % 8];
  }
}
