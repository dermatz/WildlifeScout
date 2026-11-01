/// DSGVO & Spot-Secrecy Guard (Privacy by Design).
///
/// Stellt sicher, dass exakte GPS-Koordinaten eines geheimen Ansitzes oder
/// Tier-Einstands NIEMALS im Klartext an externe APIs übertragen werden.
class CoordinateGuard {
  const CoordinateGuard._();

  /// Rundet Breiten- und Längengrad auf 2 Nachkommastellen (~1,1 km Raster)
  /// für externe Wetter-Aufrufe (Open-Meteo / DWD ICON-D2).
  static ({double lat, double lon}) obfuscateForWeatherApi(
    double latitude,
    double longitude,
  ) {
    final safeLat = (latitude * 100).roundToDouble() / 100;
    final safeLon = (longitude * 100).roundToDouble() / 100;
    return (lat: safeLat, lon: safeLon);
  }

  /// Erzeugt eine auf ein Sektor-Gitter (3 Nachkommastellen) quantisierte
  /// Bounding-Box für OpenStreetMap-Overpass-Abfragen, sodass der exakte
  /// Tarnzelt-Pin verborgen bleibt, aber alle echten Wälder, Wiesen und Wege
  /// im ~3,0 bis 3,2 km Kartenausschnitt (ca. 1,6x größerer Radius) geladen werden.
  static ({double south, double west, double north, double east})
  buildPrivacyBoundingBoxForOsm(
    double latitude,
    double longitude, {
    double latHalfSpan = 0.0070,
    double lonHalfSpan = 0.0100,
  }) {
    final sectorLat = (latitude * 200).roundToDouble() / 200;
    final sectorLon = (longitude * 200).roundToDouble() / 200;
    return (
      south: double.parse((sectorLat - latHalfSpan).toStringAsFixed(4)),
      west: double.parse((sectorLon - lonHalfSpan).toStringAsFixed(4)),
      north: double.parse((sectorLat + latHalfSpan).toStringAsFixed(4)),
      east: double.parse((sectorLon + lonHalfSpan).toStringAsFixed(4)),
    );
  }

  /// Prüft, ob Koordinaten im gültigen geografischen Bereich liegen.
  static bool isValidCoordinate(double latitude, double longitude) {
    if (latitude.isNaN || longitude.isNaN) return false;
    return latitude >= -90.0 &&
        latitude <= 90.0 &&
        longitude >= -180.0 &&
        longitude <= 180.0;
  }
}
