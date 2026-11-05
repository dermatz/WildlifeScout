import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../data/repositories/spot_vault_repository.dart';
import '../../data/services/app_settings_service.dart';
import '../../domain/models/severe_weather_alert.dart';
import 'severe_weather_alert_sheet.dart';
import 'settings/settings_maps_sensors_section.dart';
import 'settings/settings_privacy_storage_section.dart';
import 'settings/settings_search_area_section.dart';
import 'settings/settings_severe_weather_section.dart';
import 'settings/settings_units_section.dart';

/// Modal-Sheet für die Einstellungen der WildlifeScout-App.
/// Organisiert als vertikale Accordion-Liste nach Apple HIG
/// mit progressiver Offenlegung (Progressive Disclosure) und
/// kompakter Statusanzeige bei geschlossenen Kategorien.
class AppSettingsSheet extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const AppSettingsSheet({
    super.key,
    this.onSettingsChanged,
  });

  @override
  State<AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<AppSettingsSheet> {
  double _radiusKm = AppSettings.defaultSearchRadiusKm;
  bool _autoGps = true;
  bool _showPlaceNames = true;
  bool _showRainRadar = false;
  bool _showCompassBeam = AppSettings.defaultShowCompassHeadingBeam;
  bool _showHudCompassTape = AppSettings.defaultShowHudCompassTape;
  bool _showWindScentCone = AppSettings.defaultShowWindScentCone;
  bool _showDisturbanceLayer = AppSettings.defaultShowDisturbanceLayer;
  bool _showLensFieldOfView = AppSettings.defaultShowLensFieldOfView;
  bool _warnSevereWeather = AppSettings.defaultWarnSevereWeather;
  double _gustThresholdKmh = AppSettings.defaultWindGustThresholdKmh;
  bool _severeWeatherHaptics = AppSettings.defaultSevereWeatherSoundAndHaptics;
  String _windSpeedUnit = AppSettings.defaultWindSpeedUnit;
  String _distanceUnit = AppSettings.defaultDistanceUnit;
  int _savedSpotsCount = 0;
  bool _isLoading = true;

  /// Indexe der aktuell geöffneten Accordion-Karten.
  /// Standardmäßig sind alle Bereiche eingeklappt.
  final Set<int> _expandedIndices = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final settings = await AppSettingsService.loadSettings();
    int spotCount = 0;
    try {
      final spots = await SpotVaultRepository().loadSpots();
      spotCount = spots.length;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _radiusKm = settings.searchRadiusKm;
      _autoGps = settings.autoCenterGpsOnStart;
      _showPlaceNames = settings.showPlaceNamesOnSatellite;
      _showRainRadar = settings.showRainRadarLayer;
      _showCompassBeam = settings.showCompassHeadingBeam;
      _showHudCompassTape = settings.showHudCompassTape;
      _showWindScentCone = settings.showWindScentCone;
      _showDisturbanceLayer = settings.showDisturbanceLayer;
      _showLensFieldOfView = settings.showLensFieldOfView;
      _warnSevereWeather = settings.warnSevereWeatherDuringAnsitz;
      _gustThresholdKmh = settings.severeWeatherWindGustThresholdKmh;
      _severeWeatherHaptics = settings.severeWeatherSoundAndHaptics;
      _windSpeedUnit = settings.windSpeedUnit;
      _distanceUnit = settings.distanceUnit;
      _savedSpotsCount = spotCount;
      _isLoading = false;
    });
  }

  void _toggleSection(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_expandedIndices.contains(index)) {
        _expandedIndices.remove(index);
      } else {
        _expandedIndices.add(index);
      }
    });
  }

  void _toggleAllSections() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_expandedIndices.length >= 3) {
        _expandedIndices.clear();
      } else {
        _expandedIndices.addAll(const {0, 1, 2, 3, 4});
      }
    });
  }

  Future<void> _updateRadius(double newRadius) async {
    final clamped = newRadius.clamp(
      AppSettings.minSearchRadiusKm,
      AppSettings.maxSearchRadiusKm,
    );
    HapticFeedback.selectionClick();
    setState(() {
      _radiusKm = clamped;
    });
    await _saveFullSettings();
  }

  Future<void> _updateAutoGps(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _autoGps = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateShowPlaceNames(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _showPlaceNames = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateShowRainRadar(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _showRainRadar = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateShowCompassBeam(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _showCompassBeam = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateShowHudCompassTape(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _showHudCompassTape = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateShowWindScentCone(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _showWindScentCone = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateShowDisturbanceLayer(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _showDisturbanceLayer = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateShowLensFieldOfView(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _showLensFieldOfView = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateWarnSevereWeather(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _warnSevereWeather = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateGustThreshold(double val) async {
    final clamped = val.clamp(
      AppSettings.minWindGustThresholdKmh,
      AppSettings.maxWindGustThresholdKmh,
    );
    HapticFeedback.selectionClick();
    setState(() {
      _gustThresholdKmh = clamped;
    });
    await _saveFullSettings();
  }

  Future<void> _updateSevereWeatherHaptics(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _severeWeatherHaptics = val;
    });
    await _saveFullSettings();
  }

  Future<void> _updateWindSpeedUnit(String unit) async {
    HapticFeedback.selectionClick();
    setState(() {
      _windSpeedUnit = unit;
    });
    await _saveFullSettings();
  }

  Future<void> _updateDistanceUnit(String unit) async {
    HapticFeedback.selectionClick();
    setState(() {
      _distanceUnit = unit;
    });
    await _saveFullSettings();
  }

  void _triggerTestAlert() {
    final demoAlert = SevereWeatherAlert(
      type: SevereWeatherType.stormGusts,
      severity: _gustThresholdKmh >= 75.0
          ? SevereWeatherSeverity.danger
          : SevereWeatherSeverity.warning,
      headline:
          'Probe-Alarm: Sturmböen bis ${_gustThresholdKmh.round()} km/h (${SettingsSevereWeatherSection.gustThresholdLabel(_gustThresholdKmh)})',
      subheadline: 'Funktionstest der Unwetter-Warnung für den Fotospot',
      description:
          'Dies ist ein Test deiner eingestellten Warnschwelle (${_gustThresholdKmh.round()} km/h). Im Ernstfall schlägt WildlifeScout bei heranziehendem Sturm, Gewitter oder Starkregen während einer aktiven Fotosession sofort Alarm.',
      safetyRecommendation:
          'Im Ernstfall: Offenes Gelände oder Hochstände sofort verlassen; bei aufziehendem Sturm Waldgebiet rechtzeitig vor Windbruch räumen.',
      peakGustKmh: _gustThresholdKmh,
      precipitationMm: 12.0,
      weatherCode: 95,
      eventTime: DateTime.now().add(const Duration(hours: 1)),
      hoursUntilEvent: 1,
    );

    SevereWeatherAlertSheet.show(
      context,
      alert: demoAlert,
      isPreviewTest: true,
    );
  }

  Future<void> _saveFullSettings() async {
    final settings = AppSettings(
      searchRadiusKm: _radiusKm,
      autoCenterGpsOnStart: _autoGps,
      showPlaceNamesOnSatellite: _showPlaceNames,
      showRainRadarLayer: _showRainRadar,
      warnSevereWeatherDuringAnsitz: _warnSevereWeather,
      severeWeatherWindGustThresholdKmh: _gustThresholdKmh,
      severeWeatherSoundAndHaptics: _severeWeatherHaptics,
      showCompassHeadingBeam: _showCompassBeam,
      showHudCompassTape: _showHudCompassTape,
      showWindScentCone: _showWindScentCone,
      showDisturbanceLayer: _showDisturbanceLayer,
      showLensFieldOfView: _showLensFieldOfView,
      windSpeedUnit: _windSpeedUnit,
      distanceUnit: _distanceUnit,
    );
    await AppSettingsService.saveSettings(settings);
    widget.onSettingsChanged?.call();
  }

  Future<void> _resetDefaults() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _radiusKm = AppSettings.defaultSearchRadiusKm;
      _autoGps = true;
      _showPlaceNames = true;
      _showRainRadar = false;
      _showCompassBeam = AppSettings.defaultShowCompassHeadingBeam;
      _showHudCompassTape = AppSettings.defaultShowHudCompassTape;
      _showWindScentCone = AppSettings.defaultShowWindScentCone;
      _showDisturbanceLayer = AppSettings.defaultShowDisturbanceLayer;
      _showLensFieldOfView = AppSettings.defaultShowLensFieldOfView;
      _warnSevereWeather = AppSettings.defaultWarnSevereWeather;
      _gustThresholdKmh = AppSettings.defaultWindGustThresholdKmh;
      _severeWeatherHaptics = AppSettings.defaultSevereWeatherSoundAndHaptics;
      _windSpeedUnit = AppSettings.defaultWindSpeedUnit;
      _distanceUnit = AppSettings.defaultDistanceUnit;
    });
    await AppSettingsService.resetToDefaults();
    widget.onSettingsChanged?.call();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Einstellungen auf Standardwerte zurückgesetzt.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: WildlifeScoutTheme.surfaceCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: WildlifeScoutTheme.borderSubtle),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final screenHeight = mediaQuery.size.height;

    final allExpanded = _expandedIndices.length >= 3;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.90),
      decoration: BoxDecoration(
        color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildlifeScoutTheme.borderSubtle, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 12,
        bottom: bottomPadding + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: WildlifeScoutTheme.emeraldBio,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App-Einstellungen',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Fotogebiet • Sicherheit • Einheiten • System',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: WildlifeScoutTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 22,
                  color: WildlifeScoutTheme.textMuted,
                ),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Schließen',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Sub-Header: Steuerung "Alle aufklappen / zuklappen"
          Row(
            children: [
              const Expanded(
                child: Text(
                  'EINSTELLUNGS-BEREICHE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: WildlifeScoutTheme.textMuted,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _toggleAllSections,
                icon: Icon(
                  allExpanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 14,
                  color: WildlifeScoutTheme.emeraldBio,
                ),
                label: Text(
                  allExpanded ? 'Alle zuklappen' : 'Alle aufklappen',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: WildlifeScoutTheme.emeraldBio,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: WildlifeScoutTheme.emeraldBio,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Content
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: WildlifeScoutTheme.emeraldBio,
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    SettingsSearchAreaSection(
                      radiusKm: _radiusKm,
                      autoGps: _autoGps,
                      isExpanded: _expandedIndices.contains(0),
                      onToggle: () => _toggleSection(0),
                      onRadiusChanged: _updateRadius,
                      onAutoGpsChanged: _updateAutoGps,
                    ),
                    const SizedBox(height: 12),
                    SettingsSevereWeatherSection(
                      warnSevereWeather: _warnSevereWeather,
                      gustThresholdKmh: _gustThresholdKmh,
                      severeWeatherHaptics: _severeWeatherHaptics,
                      isExpanded: _expandedIndices.contains(1),
                      onToggle: () => _toggleSection(1),
                      onWarnSevereWeatherChanged: _updateWarnSevereWeather,
                      onGustThresholdChanged: _updateGustThreshold,
                      onSevereWeatherHapticsChanged: _updateSevereWeatherHaptics,
                      onTriggerTestAlert: _triggerTestAlert,
                    ),
                    const SizedBox(height: 12),
                    SettingsMapsSensorsSection(
                      showPlaceNames: _showPlaceNames,
                      showRainRadar: _showRainRadar,
                      showCompassBeam: _showCompassBeam,
                      showHudCompassTape: _showHudCompassTape,
                      showWindScentCone: _showWindScentCone,
                      showDisturbanceLayer: _showDisturbanceLayer,
                      showLensFieldOfView: _showLensFieldOfView,
                      isExpanded: _expandedIndices.contains(2),
                      onToggle: () => _toggleSection(2),
                      onShowPlaceNamesChanged: _updateShowPlaceNames,
                      onShowRainRadarChanged: _updateShowRainRadar,
                      onShowCompassBeamChanged: _updateShowCompassBeam,
                      onShowHudCompassTapeChanged: _updateShowHudCompassTape,
                      onShowWindScentConeChanged: _updateShowWindScentCone,
                      onShowDisturbanceLayerChanged: _updateShowDisturbanceLayer,
                      onShowLensFieldOfViewChanged: _updateShowLensFieldOfView,
                    ),
                    const SizedBox(height: 12),
                    SettingsUnitsSection(
                      windSpeedUnit: _windSpeedUnit,
                      distanceUnit: _distanceUnit,
                      isExpanded: _expandedIndices.contains(3),
                      onToggle: () => _toggleSection(3),
                      onWindSpeedUnitChanged: _updateWindSpeedUnit,
                      onDistanceUnitChanged: _updateDistanceUnit,
                    ),
                    const SizedBox(height: 12),
                    SettingsPrivacyStorageSection(
                      savedSpotsCount: _savedSpotsCount,
                      isExpanded: _expandedIndices.contains(4),
                      onToggle: () => _toggleSection(4),
                      onResetDefaults: _resetDefaults,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
