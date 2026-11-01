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
    required this.precipitationMm,
    this.weatherCode = 0,
  });

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
