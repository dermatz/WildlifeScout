import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/secret_spot.dart';

/// 100% lokaler, geräteseitiger Tresor für eigene Standorte (Zero-Cloud).
/// Keine Synchronisation an fremde Server (DSGVO & Spot-Schutz).
class SpotVaultRepository {
  static const String _storageKey = 'wildlifescout_local_spot_vault_v1';
  static const String _legacyStorageKey = 'wildscout_local_spot_vault_v1';

  Future<List<SecretSpot>> loadSpots() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey) ??
        prefs.getStringList(_legacyStorageKey);
    if (rawList == null || rawList.isEmpty) {
      return [];
    }

    final spots = rawList
        .map((item) {
          try {
            return SecretSpot.fromJson(
              jsonDecode(item) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<SecretSpot>()
        .where((spot) => !spot.id.startsWith('spot_demo_'))
        .toList();

    if (spots.length != rawList.length) {
      await saveSpots(spots);
    }

    return spots;
  }

  Future<void> saveSpots(List<SecretSpot> spots) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = spots.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_storageKey, encoded);
  }
}
