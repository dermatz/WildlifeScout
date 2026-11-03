import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Datenmodell für die persistenten Einstellungen der WildlifeScout-App.
class AppSettings {
  /// Suchradius für die Umkreissuche von Gebieten & Wäldern in Kilometern.
  /// Standardwert: 50.0 km.
  final double searchRadiusKm;

  /// Ob beim App-Start automatisch der aktuelle GPS-Standort zentriert werden soll.
  final bool autoCenterGpsOnStart;

  /// Ob hybride Orts- und Wegenamen auf dem Satellitenlayer angezeigt werden.
  final bool showPlaceNamesOnSatellite;

  /// Ob der DWD-Niederschlags- & Gewitterradar-Layer auf der Karte eingeblendet wird.
  final bool showRainRadarLayer;

  /// Ob während einer aktiven Fotosession vor heranziehendem Unwetter gewarnt werden soll.
  final bool warnSevereWeatherDuringAnsitz;
  bool get warnSevereWeatherDuringSession => warnSevereWeatherDuringAnsitz;

  /// Windböen-Warnschwelle in km/h, ab der Sturm-Alarm für den Fotospot ausgelöst wird.
  /// Standardwert: 60.0 km/h (Beaufort 8: Astbruchgefahr im Wald).
  final double severeWeatherWindGustThresholdKmh;

  /// Ob bei Unwetterwarnungen spürbare Haptik & Töne ausgelöst werden sollen.
  final bool severeWeatherSoundAndHaptics;

  /// Ob der Blickrichtungs-Peilstrahl (Geräte-Kompass) auf der Karte angezeigt werden soll.
  final bool showCompassHeadingBeam;

  /// Ob der Wind- & Geruchskegel auf der Karte angezeigt werden soll.
  final bool showWindScentCone;

  /// Ob rot markierte Störwege & Pufferzonen (Wanderpfade, Forst- & Wirtschaftswege)
  /// auf der Karte angezeigt werden sollen. Standardwert: false (nur wenn aktiv eingeschaltet).
  final bool showDisturbanceLayer;

  /// Ob der Kompass-Peilstrahl auf den realen optischen Bildwinkel (FOV)
  /// des konfigurierten Foto-Objektivs angepasst werden soll.
  final bool showLensFieldOfView;

  /// Bevorzugte Einheit für Windgeschwindigkeit: 'kmh', 'bft', 'ms', 'kn'.
  final String windSpeedUnit;

  /// Bevorzugte Distanzeinheit: 'metric' (km/m) oder 'imperial' (mi/yd).
  final String distanceUnit;

  /// Standard: 50 km Umkreissuche
  static const double defaultSearchRadiusKm = 50.0;
  static const double minSearchRadiusKm = 10.0;
  static const double maxSearchRadiusKm = 200.0;

  /// Standardwerte für Unwetter-Warnungen am Fotospot
  static const bool defaultWarnSevereWeather = true;
  static const double defaultWindGustThresholdKmh = 60.0;
  static const minWindGustThresholdKmh = 45.0;
  static const maxWindGustThresholdKmh = 90.0;
  static const bool defaultSevereWeatherSoundAndHaptics = true;

  /// Standardwerte für Sensorik, Optik & Einheiten
  static const bool defaultShowCompassHeadingBeam = true;
  static const bool defaultShowWindScentCone = true;
  static const bool defaultShowDisturbanceLayer = false;
  static const bool defaultShowLensFieldOfView = true;
  static const String defaultWindSpeedUnit = 'kmh';
  static const String defaultDistanceUnit = 'metric';

  const AppSettings({
    this.searchRadiusKm = defaultSearchRadiusKm,
    this.autoCenterGpsOnStart = true,
    this.showPlaceNamesOnSatellite = true,
    this.showRainRadarLayer = false,
    this.warnSevereWeatherDuringAnsitz = defaultWarnSevereWeather,
    this.severeWeatherWindGustThresholdKmh = defaultWindGustThresholdKmh,
    this.severeWeatherSoundAndHaptics = defaultSevereWeatherSoundAndHaptics,
    this.showCompassHeadingBeam = defaultShowCompassHeadingBeam,
    this.showWindScentCone = defaultShowWindScentCone,
    this.showDisturbanceLayer = defaultShowDisturbanceLayer,
    this.showLensFieldOfView = defaultShowLensFieldOfView,
    this.windSpeedUnit = defaultWindSpeedUnit,
    this.distanceUnit = defaultDistanceUnit,
  });

  AppSettings copyWith({
    double? searchRadiusKm,
    bool? autoCenterGpsOnStart,
    bool? showPlaceNamesOnSatellite,
    bool? showRainRadarLayer,
    bool? warnSevereWeatherDuringAnsitz,
    double? severeWeatherWindGustThresholdKmh,
    bool? severeWeatherSoundAndHaptics,
    bool? showCompassHeadingBeam,
    bool? showWindScentCone,
    bool? showDisturbanceLayer,
    bool? showLensFieldOfView,
    String? windSpeedUnit,
    String? distanceUnit,
  }) {
    return AppSettings(
      searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
      autoCenterGpsOnStart: autoCenterGpsOnStart ?? this.autoCenterGpsOnStart,
      showPlaceNamesOnSatellite:
          showPlaceNamesOnSatellite ?? this.showPlaceNamesOnSatellite,
      showRainRadarLayer: showRainRadarLayer ?? this.showRainRadarLayer,
      warnSevereWeatherDuringAnsitz:
          warnSevereWeatherDuringAnsitz ?? this.warnSevereWeatherDuringAnsitz,
      severeWeatherWindGustThresholdKmh: severeWeatherWindGustThresholdKmh ??
          this.severeWeatherWindGustThresholdKmh,
      severeWeatherSoundAndHaptics:
          severeWeatherSoundAndHaptics ?? this.severeWeatherSoundAndHaptics,
      showCompassHeadingBeam:
          showCompassHeadingBeam ?? this.showCompassHeadingBeam,
      showWindScentCone: showWindScentCone ?? this.showWindScentCone,
      showDisturbanceLayer: showDisturbanceLayer ?? this.showDisturbanceLayer,
      showLensFieldOfView: showLensFieldOfView ?? this.showLensFieldOfView,
      windSpeedUnit: windSpeedUnit ?? this.windSpeedUnit,
      distanceUnit: distanceUnit ?? this.distanceUnit,
    );
  }
}

/// Service zur lokalen, DSGVO-konformen Speicherung der App-Einstellungen
/// via SharedPreferences mit reaktivem [ValueNotifier].
class AppSettingsService {
  static const String _keySearchRadiusKm = 'wildlifescout_search_radius_km_v1';
  static const String _keyAutoCenterGps = 'wildlifescout_auto_center_gps_v1';
  static const String _keyShowPlaceNames = 'wildlifescout_show_place_names_v1';
  static const String _keyShowRainRadar = 'wildlifescout_show_rain_radar_v1';
  static const String _keyWarnSevereWeather =
      'wildlifescout_warn_severe_weather_v1';
  static const String _keySevereWeatherGustThreshold =
      'wildlifescout_severe_weather_gust_threshold_v1';
  static const String _keySevereWeatherHaptics =
      'wildlifescout_severe_weather_haptics_v1';
  static const String _keyShowCompassBeam =
      'wildlifescout_show_compass_beam_v1';
  static const String _keyShowWindScentCone =
      'wildlifescout_show_wind_scent_cone_v1';
  static const String _keyShowDisturbanceLayer =
      'wildlifescout_show_disturbance_layer_v1';
  static const String _keyShowLensFieldOfView =
      'wildlifescout_show_lens_field_of_view_v1';
  static const String _keyWindSpeedUnit =
      'wildlifescout_wind_speed_unit_v1';
  static const String _keyDistanceUnit =
      'wildlifescout_distance_unit_v1';

  // Legacy-Keys für nahtlose Abwärtskompatibilität
  static const String _legacyKeySearchRadiusKm = 'wildscout_search_radius_km_v1';
  static const String _legacyKeyAutoCenterGps = 'wildscout_auto_center_gps_v1';
  static const String _legacyKeyShowPlaceNames = 'wildscout_show_place_names_v1';
  static const String _legacyKeyShowRainRadar = 'wildscout_show_rain_radar_v1';
  static const String _legacyKeyWarnSevereWeather = 'wildscout_warn_severe_weather_v1';
  static const String _legacyKeySevereWeatherGustThreshold = 'wildscout_severe_weather_gust_threshold_v1';
  static const String _legacyKeySevereWeatherHaptics = 'wildscout_severe_weather_haptics_v1';
  static const String _legacyKeyShowCompassBeam = 'wildscout_show_compass_beam_v1';
  static const String _legacyKeyShowWindScentCone = 'wildscout_show_wind_scent_cone_v1';
  static const String _legacyKeyShowDisturbanceLayer = 'wildscout_show_disturbance_layer_v1';
  static const String _legacyKeyShowLensFieldOfView = 'wildscout_show_lens_field_of_view_v1';
  static const String _legacyKeyWindSpeedUnit = 'wildscout_wind_speed_unit_v1';
  static const String _legacyKeyDistanceUnit = 'wildscout_distance_unit_v1';

  /// Reaktiver Notifier für den aktuellen Suchradius, damit alle Sheets
  /// und Widgets (z. B. Ortssuche, Karte) ohne Neustart sofort reagieren.
  static final ValueNotifier<double> searchRadiusNotifier =
      ValueNotifier<double>(AppSettings.defaultSearchRadiusKm);

  /// Globaler reaktiver Notifier für die App-Einstellungen.
  static final ValueNotifier<AppSettings> settingsNotifier =
      ValueNotifier<AppSettings>(const AppSettings());

  /// Lädt alle gespeicherten App-Einstellungen.
  static Future<AppSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final radius = prefs.getDouble(_keySearchRadiusKm) ??
          prefs.getDouble(_legacyKeySearchRadiusKm) ??
          AppSettings.defaultSearchRadiusKm;
      final autoGps = prefs.getBool(_keyAutoCenterGps) ??
          prefs.getBool(_legacyKeyAutoCenterGps) ??
          true;
      final showPlaces = prefs.getBool(_keyShowPlaceNames) ??
          prefs.getBool(_legacyKeyShowPlaceNames) ??
          true;
      final showRainRadar = prefs.getBool(_keyShowRainRadar) ??
          prefs.getBool(_legacyKeyShowRainRadar) ??
          false;
      final warnSevereWeather = prefs.getBool(_keyWarnSevereWeather) ??
          prefs.getBool(_legacyKeyWarnSevereWeather) ??
          AppSettings.defaultWarnSevereWeather;
      final gustThreshold = prefs.getDouble(_keySevereWeatherGustThreshold) ??
          prefs.getDouble(_legacyKeySevereWeatherGustThreshold) ??
          AppSettings.defaultWindGustThresholdKmh;
      final soundHaptics = prefs.getBool(_keySevereWeatherHaptics) ??
          prefs.getBool(_legacyKeySevereWeatherHaptics) ??
          AppSettings.defaultSevereWeatherSoundAndHaptics;
      final showCompassBeam = prefs.getBool(_keyShowCompassBeam) ??
          prefs.getBool(_legacyKeyShowCompassBeam) ??
          AppSettings.defaultShowCompassHeadingBeam;
      final showWindScentCone = prefs.getBool(_keyShowWindScentCone) ??
          prefs.getBool(_legacyKeyShowWindScentCone) ??
          AppSettings.defaultShowWindScentCone;
      final showDisturbanceLayer = prefs.getBool(_keyShowDisturbanceLayer) ??
          prefs.getBool(_legacyKeyShowDisturbanceLayer) ??
          AppSettings.defaultShowDisturbanceLayer;
      final showLensFov = prefs.getBool(_keyShowLensFieldOfView) ??
          prefs.getBool(_legacyKeyShowLensFieldOfView) ??
          AppSettings.defaultShowLensFieldOfView;
      final windSpeedUnit = prefs.getString(_keyWindSpeedUnit) ??
          prefs.getString(_legacyKeyWindSpeedUnit) ??
          AppSettings.defaultWindSpeedUnit;
      final distanceUnit = prefs.getString(_keyDistanceUnit) ??
          prefs.getString(_legacyKeyDistanceUnit) ??
          AppSettings.defaultDistanceUnit;

      final safeRadius = radius.clamp(
        AppSettings.minSearchRadiusKm,
        AppSettings.maxSearchRadiusKm,
      );

      final safeGustThreshold = gustThreshold.clamp(
        AppSettings.minWindGustThresholdKmh,
        AppSettings.maxWindGustThresholdKmh,
      );

      searchRadiusNotifier.value = safeRadius;

      final loaded = AppSettings(
        searchRadiusKm: safeRadius,
        autoCenterGpsOnStart: autoGps,
        showPlaceNamesOnSatellite: showPlaces,
        showRainRadarLayer: showRainRadar,
        warnSevereWeatherDuringAnsitz: warnSevereWeather,
        severeWeatherWindGustThresholdKmh: safeGustThreshold,
        severeWeatherSoundAndHaptics: soundHaptics,
        showCompassHeadingBeam: showCompassBeam,
        showWindScentCone: showWindScentCone,
        showDisturbanceLayer: showDisturbanceLayer,
        showLensFieldOfView: showLensFov,
        windSpeedUnit: windSpeedUnit,
        distanceUnit: distanceUnit,
      );

      settingsNotifier.value = loaded;
      return loaded;
    } catch (_) {
      return const AppSettings();
    }
  }

  /// Speichert die kompletten Einstellungen.
  static Future<void> saveSettings(AppSettings settings) async {
    try {
      final safeRadius = settings.searchRadiusKm.clamp(
        AppSettings.minSearchRadiusKm,
        AppSettings.maxSearchRadiusKm,
      );

      final safeGustThreshold = settings.severeWeatherWindGustThresholdKmh.clamp(
        AppSettings.minWindGustThresholdKmh,
        AppSettings.maxWindGustThresholdKmh,
      );

      final adjusted = settings.copyWith(
        searchRadiusKm: safeRadius,
        severeWeatherWindGustThresholdKmh: safeGustThreshold,
      );

      searchRadiusNotifier.value = safeRadius;
      settingsNotifier.value = adjusted;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keySearchRadiusKm, safeRadius);
      await prefs.setBool(_keyAutoCenterGps, adjusted.autoCenterGpsOnStart);
      await prefs.setBool(
        _keyShowPlaceNames,
        adjusted.showPlaceNamesOnSatellite,
      );
      await prefs.setBool(
        _keyShowRainRadar,
        adjusted.showRainRadarLayer,
      );
      await prefs.setBool(
        _keyWarnSevereWeather,
        adjusted.warnSevereWeatherDuringAnsitz,
      );
      await prefs.setDouble(
        _keySevereWeatherGustThreshold,
        safeGustThreshold,
      );
      await prefs.setBool(
        _keySevereWeatherHaptics,
        adjusted.severeWeatherSoundAndHaptics,
      );
      await prefs.setBool(
        _keyShowCompassBeam,
        adjusted.showCompassHeadingBeam,
      );
      await prefs.setBool(
        _keyShowWindScentCone,
        adjusted.showWindScentCone,
      );
      await prefs.setBool(
        _keyShowDisturbanceLayer,
        adjusted.showDisturbanceLayer,
      );
      await prefs.setBool(
        _keyShowLensFieldOfView,
        adjusted.showLensFieldOfView,
      );
      await prefs.setString(
        _keyWindSpeedUnit,
        adjusted.windSpeedUnit,
      );
      await prefs.setString(
        _keyDistanceUnit,
        adjusted.distanceUnit,
      );
    } catch (_) {}
  }

  /// Ändert spezifisch die Unwetter-Warnung und speichert sie persistent.
  static Future<void> setWarnSevereWeather(bool enabled) async {
    final current = settingsNotifier.value;
    final updated = current.copyWith(warnSevereWeatherDuringAnsitz: enabled);
    await saveSettings(updated);
  }

  /// Ändert spezifisch die Anzeige der rot markierten Störwege & Pufferzonen und speichert sie persistent.
  static Future<void> setShowDisturbanceLayer(bool enabled) async {
    final current = settingsNotifier.value;
    final updated = current.copyWith(showDisturbanceLayer: enabled);
    await saveSettings(updated);
  }

  /// Ändert spezifisch die Anzeige des DWD Niederschlags- & Gewitterradars und speichert sie persistent.
  static Future<void> setShowRainRadarLayer(bool enabled) async {
    final current = settingsNotifier.value;
    final updated = current.copyWith(showRainRadarLayer: enabled);
    await saveSettings(updated);
  }

  /// Ändert die Windböen-Warnschwelle für Sturm am Fotospot.
  static Future<void> setSevereWeatherWindGustThresholdKmh(double threshold) async {
    final current = settingsNotifier.value;
    final updated = current.copyWith(severeWeatherWindGustThresholdKmh: threshold);
    await saveSettings(updated);
  }

  /// Ändert spezifisch den Suchradius der Umkreissuche und speichert ihn persistent.
  static Future<void> setSearchRadiusKm(double radiusKm) async {
    final safeRadius = radiusKm.clamp(
      AppSettings.minSearchRadiusKm,
      AppSettings.maxSearchRadiusKm,
    );

    searchRadiusNotifier.value = safeRadius;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keySearchRadiusKm, safeRadius);
    } catch (_) {}
  }

  /// Setzt die Einstellungen auf Werkseinstellungen zurück (Standard: 50 km).
  static Future<void> resetToDefaults() async {
    await saveSettings(const AppSettings());
  }
}
