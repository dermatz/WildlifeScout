import 'package:flutter/material.dart';

class WildScoutTheme {
  const WildScoutTheme._();

  // Obsidian Forest Palette
  static const Color bgObsidian = Color(0xFF090E0C);
  static const Color surfaceGlass = Color(0xD9111A16);
  static const Color surfaceCard = Color(0xFF16221D);
  static const Color borderSubtle = Color(0x26FFFFFF);

  // Tactical Accents
  static const Color emeraldBio = Color(0xFF10B981);
  static const Color amberGold = Color(0xFFF59E0B);
  static const Color crimsonScent = Color(0xFFEF4444);
  static const Color cyanWater = Color(0xFF06B6D4);
  static const Color textPrimary = Color(0xFFF3F7F5);
  static const Color textMuted = Color(0xFF94A89E);

  /// Echter Tarnzelt-Rotlicht-Farbfilter (Night-Vision Red Mode).
  /// Wandelt alle hellen Grün-/Blau-Anteile in dunkles Monochrom-Rot um,
  /// damit die Dunkeladaption der Augen im finsteren Wald um 04:30 Uhr
  /// zu 100 % erhalten bleibt.
  static const ColorFilter nightVisionRedMatrix = ColorFilter.matrix(<double>[
    0.45, 0.45, 0.10, 0, 0, // Rot-Kanal behält Luminanz
    0.00, 0.05, 0.00, 0, 0, // Grün-Kanal fast komplett ausgeblendet
    0.00, 0.00, 0.03, 0, 0, // Blau-Kanal fast komplett ausgeblendet
    0.00, 0.00, 0.00, 1, 0, // Alpha unverändert
  ]);

  static ThemeData buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgObsidian,
      colorScheme: const ColorScheme.dark(
        primary: emeraldBio,
        secondary: amberGold,
        error: crimsonScent,
        surface: surfaceCard,
        onSurface: textPrimary,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: emeraldBio,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
        thumbColor: amberGold,
        overlayColor: amberGold.withValues(alpha: 0.18),
        trackHeight: 5.0,
      ),
    );
  }
}
