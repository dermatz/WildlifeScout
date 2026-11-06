import 'dart:convert';
import 'package:flutter/services.dart';
import '../../domain/models/species_profile.dart';

/// Lädt alle registrierten Tier-Profile aus `assets/species/*.json`.
/// Neue Tierarten können jederzeit als JSON-Datei ergänzt werden, ohne die
/// Berechnungs-Engine zu verändern.
class SpeciesRepository {
  static const List<String> _registeredSpeciesPaths = [
    'assets/species/roe_deer.json',
    'assets/species/badger.json',
  ];

  Future<List<SpeciesProfile>> loadAllSpecies() async {
    final profiles = <SpeciesProfile>[];
    for (final path in _registeredSpeciesPaths) {
      final raw = await rootBundle.loadString(path);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      profiles.add(SpeciesProfile.fromJson(map));
    }
    return profiles;
  }
}
