import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/photo_gear_profile.dart';

/// Service zur lokalen, DSGVO-konformen Speicherung der Foto-Ausrüstung
/// (Objektiv, Sensor, Telekonverter) via SharedPreferences mit reaktivem [ValueNotifier].
class PhotoGearService {
  static const String _keyPhotoGear = 'wildlifescout_photo_gear_v1';
  static const String _legacyKeyPhotoGear = 'wildscout_photo_gear_v1';

  /// Standard-Ausrüstung: 400 mm f/4.0 an Vollformat ohne Konverter
  static const PhotoGearProfile defaultGear = PhotoGearProfile(
    lensName: '400 mm f/4.0 Festbrennweite',
    focalLengthMm: 400.0,
    maxAperture: 4.0,
    sensorFormat: CameraSensorFormat.fullFrame,
    teleconverter: Teleconverter.none,
    hasOpticalStabilization: true,
  );

  /// Globaler reaktiver Notifier für das aktuelle Foto-Setup.
  /// Alle Widgets (Karten-Peilstrahl, Tier-Steckbrief, Einstellungen)
  /// reagieren sofort ohne App-Neustart auf Änderungen.
  static final ValueNotifier<PhotoGearProfile> gearNotifier =
      ValueNotifier<PhotoGearProfile>(defaultGear);

  /// Lädt das gespeicherte Foto-Setup aus dem lokalen Gerätespeicher.
  static Future<PhotoGearProfile> loadGear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keyPhotoGear) ?? prefs.getString(_legacyKeyPhotoGear);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        final loaded = PhotoGearProfile.fromJson(data);
        gearNotifier.value = loaded;
        return loaded;
      }
    } catch (_) {}

    gearNotifier.value = defaultGear;
    return defaultGear;
  }

  /// Speichert ein neues Foto-Setup persistent ab und informiert alle Hörer.
  static Future<void> saveGear(PhotoGearProfile gear) async {
    gearNotifier.value = gear;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(gear.toJson());
      await prefs.setString(_keyPhotoGear, jsonStr);
    } catch (_) {}
  }

  /// Setzt die Foto-Ausrüstung auf die Werkseinstellung zurück.
  static Future<void> resetToDefaults() async {
    await saveGear(defaultGear);
  }
}
