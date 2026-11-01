import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../data/repositories/spot_vault_repository.dart';
import '../../data/services/app_settings_service.dart';
import '../../domain/models/severe_weather_alert.dart';
import 'severe_weather_alert_sheet.dart';

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
  bool _showWindScentCone = AppSettings.defaultShowWindScentCone;
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

  static const List<double> _presetRadii = [25.0, 50.0, 75.0, 100.0, 150.0];
  static const List<double> _presetGustThresholds = [50.0, 60.0, 75.0];

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
      _showWindScentCone = settings.showWindScentCone;
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
    HapticFeedback.selectionClick();
    setState(() {
      if (_expandedIndices.length >= 3) {
        _expandedIndices.clear();
      } else {
        _expandedIndices.addAll({0, 1, 2, 3, 4});
      }
    });
  }

  Future<void> _updateRadius(double newRadius) async {
    HapticFeedback.selectionClick();
    final clamped = newRadius.clamp(
      AppSettings.minSearchRadiusKm,
      AppSettings.maxSearchRadiusKm,
    );
    setState(() {
      _radiusKm = clamped;
    });
    await AppSettingsService.setSearchRadiusKm(clamped);
    widget.onSettingsChanged?.call();
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

  Future<void> _updateShowWindScentCone(bool val) async {
    HapticFeedback.selectionClick();
    setState(() {
      _showWindScentCone = val;
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
    HapticFeedback.selectionClick();
    final clamped = val.clamp(
      AppSettings.minWindGustThresholdKmh,
      AppSettings.maxWindGustThresholdKmh,
    );
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
          'Probe-Alarm: Sturmböen bis ${_gustThresholdKmh.round()} km/h (${_gustThresholdLabel(_gustThresholdKmh)})',
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

  String _gustThresholdLabel(double gust) {
    if (gust >= 75) return 'Bft 9 • Sturm';
    if (gust >= 62) return 'Bft 8 • Sturmböen';
    if (gust >= 50) return 'Bft 7 • Starker Wind';
    return 'Bft 6 • Kräftig';
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
      showWindScentCone: _showWindScentCone,
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
      _showWindScentCone = AppSettings.defaultShowWindScentCone;
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
              const Text(
                'EINSTELLUNGS-BEREICHE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: WildlifeScoutTheme.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _toggleAllSections,
                icon: Icon(
                  allExpanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 15,
                ),
                label: Text(
                  allExpanded ? 'Alle zuklappen' : 'Alle aufklappen',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: WildlifeScoutTheme.emeraldBio,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  color: WildlifeScoutTheme.emeraldBio,
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==========================================
                    // Accordion 1: Fotogebiet & Umkreissuche
                    // ==========================================
                    _buildAccordionSection(
                      index: 0,
                      icon: Icons.radar_rounded,
                      iconColor: WildlifeScoutTheme.emeraldBio,
                      title: 'Fotogebiet & Umkreissuche',
                      subtitle: 'Suchbereich & Standorterfassung',
                      summaryBadge: '${_radiusKm.round()} km',
                      children: [
                        // Suchradius
                        Row(
                          children: [
                            const Icon(
                              Icons.adjust_rounded,
                              size: 16,
                              color: WildlifeScoutTheme.emeraldBio,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Suchradius Umkreissuche',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: WildlifeScoutTheme.emeraldBio
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: WildlifeScoutTheme.emeraldBio
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                '${_radiusKm.round()} km',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: WildlifeScoutTheme.emeraldBio,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Legt fest, bis zu welcher Entfernung Natur- & Waldgebiete bei der Ortssuche in deiner Nähe vorgeschlagen werden.',
                          style: TextStyle(
                            fontSize: 11,
                            color: WildlifeScoutTheme.textMuted
                                .withValues(alpha: 0.9),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Slider
                        Row(
                          children: [
                            const Text(
                              '10 km',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: WildlifeScoutTheme.textMuted,
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: WildlifeScoutTheme.emeraldBio,
                                  inactiveTrackColor: Colors.white12,
                                  thumbColor: WildlifeScoutTheme.amberGold,
                                  overlayColor: WildlifeScoutTheme.amberGold
                                      .withValues(alpha: 0.2),
                                  trackHeight: 3.5,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 8,
                                  ),
                                ),
                                child: Slider(
                                  value: _radiusKm,
                                  min: AppSettings.minSearchRadiusKm,
                                  max: AppSettings.maxSearchRadiusKm,
                                  divisions: 38,
                                  label: '${_radiusKm.round()} km',
                                  onChanged: _updateRadius,
                                ),
                              ),
                            ),
                            const Text(
                              '200 km',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: WildlifeScoutTheme.textMuted,
                              ),
                            ),
                          ],
                        ),

                        // Preset Chips
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _presetRadii.map((preset) {
                            final isSelected =
                                (_radiusKm - preset).abs() < 1.0;
                            final isDefault =
                                (preset - AppSettings.defaultSearchRadiusKm)
                                        .abs() <
                                    1.0;

                            return ChoiceChip(
                              label: Text(
                                isDefault
                                    ? '${preset.round()} km (Standard)'
                                    : '${preset.round()} km',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : WildlifeScoutTheme.textMuted,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: WildlifeScoutTheme.emeraldBio
                                  .withValues(alpha: 0.35),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.05),
                              side: BorderSide(
                                color: isSelected
                                    ? WildlifeScoutTheme.emeraldBio
                                    : WildlifeScoutTheme.borderSubtle,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onSelected: (_) => _updateRadius(preset),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 10),
                        const Divider(
                          height: 1,
                          color: WildlifeScoutTheme.borderSubtle,
                        ),
                        const SizedBox(height: 4),

                        // GPS-Startzentrierung
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: WildlifeScoutTheme.emeraldBio
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.my_location_rounded,
                              size: 16,
                              color: WildlifeScoutTheme.emeraldBio,
                            ),
                          ),
                          title: const Text(
                            'GPS beim Start zentrieren',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Bestimmt automatisch deine Position bei App-Öffnung.',
                            style: TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          value: _autoGps,
                          activeTrackColor: WildlifeScoutTheme.emeraldBio,
                          onChanged: _updateAutoGps,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ==========================================
                    // Accordion 2: Unwetter-Warnung am Fotospot
                    // ==========================================
                    _buildAccordionSection(
                      index: 1,
                      icon: Icons.warning_amber_rounded,
                      iconColor: WildlifeScoutTheme.amberGold,
                      title: 'Unwetter-Warnung am Fotospot',
                      subtitle: 'Sturmwarnung & Probe-Alarm',
                      summaryBadge: _warnSevereWeather
                          ? '${_gustThresholdKmh.round()} km/h'
                          : 'Aus',
                      badgeColor: _warnSevereWeather
                          ? WildlifeScoutTheme.amberGold
                          : WildlifeScoutTheme.textMuted,
                      children: [
                        // Unwetterwarnung Toggle
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Vor Unwetter bei aktiver Fotosession warnen',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Überwacht das Wetter live am Fotospot und warnt vor Gefahren.',
                            style: TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          value: _warnSevereWeather,
                          activeTrackColor: WildlifeScoutTheme.amberGold,
                          onChanged: _updateWarnSevereWeather,
                        ),

                        if (_warnSevereWeather) ...[
                          const Divider(
                            height: 1,
                            color: WildlifeScoutTheme.borderSubtle,
                          ),
                          const SizedBox(height: 10),

                          // Böenschwelle
                          Row(
                            children: [
                              const Icon(
                                Icons.air_rounded,
                                size: 16,
                                color: WildlifeScoutTheme.amberGold,
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'Böenschwelle für Sturmwarnung',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: WildlifeScoutTheme.amberGold
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: WildlifeScoutTheme.amberGold
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  '${_gustThresholdKmh.round()} km/h',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: WildlifeScoutTheme.amberGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ab dieser Windstärke wird Astbruch-Alarm geschlagen (${_gustThresholdLabel(_gustThresholdKmh)}).',
                            style: const TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Slider
                          Row(
                            children: [
                              const Text(
                                '45 km/h',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: WildlifeScoutTheme.textMuted,
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: WildlifeScoutTheme.amberGold,
                                    inactiveTrackColor: Colors.white12,
                                    thumbColor: WildlifeScoutTheme.amberGold,
                                    overlayColor: WildlifeScoutTheme.amberGold
                                        .withValues(alpha: 0.2),
                                    trackHeight: 3.5,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8,
                                    ),
                                  ),
                                  child: Slider(
                                    value: _gustThresholdKmh,
                                    min: AppSettings.minWindGustThresholdKmh,
                                    max: AppSettings.maxWindGustThresholdKmh,
                                    divisions: 9,
                                    label:
                                        '${_gustThresholdKmh.round()} km/h',
                                    onChanged: _updateGustThreshold,
                                  ),
                                ),
                              ),
                              const Text(
                                '90 km/h',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: WildlifeScoutTheme.textMuted,
                                ),
                              ),
                            ],
                          ),

                          // Schnellwahl-Chips
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _presetGustThresholds.map((preset) {
                              final isSelected =
                                  (_gustThresholdKmh - preset).abs() < 1.0;
                              final isDefault = (preset -
                                          AppSettings
                                              .defaultWindGustThresholdKmh)
                                      .abs() <
                                  1.0;

                              return ChoiceChip(
                                label: Text(
                                  isDefault
                                      ? '${preset.round()} km/h (Standard • Bft 8)'
                                      : (preset >= 75
                                          ? '${preset.round()} km/h (Bft 9 Sturm)'
                                          : '${preset.round()} km/h (Bft 7)'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : WildlifeScoutTheme.textMuted,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: WildlifeScoutTheme.amberGold
                                    .withValues(alpha: 0.35),
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.05),
                                side: BorderSide(
                                  color: isSelected
                                      ? WildlifeScoutTheme.amberGold
                                      : WildlifeScoutTheme.borderSubtle,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                onSelected: (_) =>
                                    _updateGustThreshold(preset),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 8),
                          const Divider(
                            height: 1,
                            color: WildlifeScoutTheme.borderSubtle,
                          ),

                          // Haptik & Signal
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: WildlifeScoutTheme.amberGold
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.vibration_rounded,
                                size: 16,
                                color: WildlifeScoutTheme.amberGold,
                              ),
                            ),
                            title: const Text(
                              'Vibrations- & Signal-Alarm',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: const Text(
                              'Löst bei akuter Lebensgefahr durch Sturm oder Gewitter spürbare Haptik aus.',
                              style: TextStyle(
                                fontSize: 11,
                                color: WildlifeScoutTheme.textMuted,
                              ),
                            ),
                            value: _severeWeatherHaptics,
                            activeTrackColor: WildlifeScoutTheme.amberGold,
                            onChanged: _updateSevereWeatherHaptics,
                          ),

                          const SizedBox(height: 6),

                          // Wald-Sicherheitshinweis
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: WildlifeScoutTheme.amberGold
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: WildlifeScoutTheme.amberGold
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  size: 15,
                                  color: WildlifeScoutTheme.amberGold,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Wald-Sicherheit: Ab 60 km/h (Bft 8) brechen größere Äste ab. Auf erhöhten Plattformen besteht Lebensgefahr. Bei Gewitter offenes Gelände umgehend verlassen.',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: WildlifeScoutTheme.textPrimary,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Probe-Alarm testen Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _triggerTestAlert,
                              icon: const Icon(
                                Icons.play_circle_outline_rounded,
                                size: 16,
                                color: WildlifeScoutTheme.amberGold,
                              ),
                              label: const Text(
                                'Probe-Alarm testen',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: WildlifeScoutTheme.amberGold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: WildlifeScoutTheme.amberGold
                                      .withValues(alpha: 0.5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ==========================================
                    // Accordion 3: Karten & Sensoren
                    // ==========================================
                    _buildAccordionSection(
                      index: 2,
                      icon: Icons.layers_outlined,
                      iconColor: WildlifeScoutTheme.cyanWater,
                      title: 'Karten & Sensoren',
                      subtitle: 'Satellit, Radar, Peilstrahl & Witterung',
                      summaryBadge: 'Ebenen',
                      children: [
                        // Orts- & Wegenamen
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: WildlifeScoutTheme.emeraldBio
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.label_outline_rounded,
                              size: 16,
                              color: WildlifeScoutTheme.emeraldBio,
                            ),
                          ),
                          title: const Text(
                            'Orts- & Wegenamen auf Satellit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Blendet Geländenamen über dem Satellitenlayer ein.',
                            style: TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          value: _showPlaceNames,
                          activeTrackColor: WildlifeScoutTheme.emeraldBio,
                          onChanged: _updateShowPlaceNames,
                        ),
                        const Divider(
                          height: 1,
                          color: WildlifeScoutTheme.borderSubtle,
                        ),

                        // DWD Niederschlagsradar
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: WildlifeScoutTheme.cyanWater
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.thunderstorm_outlined,
                              size: 16,
                              color: WildlifeScoutTheme.cyanWater,
                            ),
                          ),
                          title: const Text(
                            'DWD Niederschlags- & Gewitterradar',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Live-Radarfilm des DWD (Open Data / GeoNutzV).',
                            style: TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          value: _showRainRadar,
                          activeTrackColor: WildlifeScoutTheme.cyanWater,
                          onChanged: _updateShowRainRadar,
                        ),
                        const Divider(
                          height: 1,
                          color: WildlifeScoutTheme.borderSubtle,
                        ),

                        // Blickrichtungs-Peilstrahl
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: WildlifeScoutTheme.cyanWater
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.explore_rounded,
                              size: 16,
                              color: WildlifeScoutTheme.cyanWater,
                            ),
                          ),
                          title: const Text(
                            'Blickrichtung & Peilstrahl',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Zeigt die Handy-Ausrichtung live als Lichtkegel auf der Karte.',
                            style: TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          value: _showCompassBeam,
                          activeTrackColor: WildlifeScoutTheme.cyanWater,
                          onChanged: _updateShowCompassBeam,
                        ),
                        const Divider(
                          height: 1,
                          color: WildlifeScoutTheme.borderSubtle,
                        ),

                        // Witterungs- & Windkegel
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: WildlifeScoutTheme.crimsonScent
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.air_rounded,
                              size: 16,
                              color: WildlifeScoutTheme.crimsonScent,
                            ),
                          ),
                          title: const Text(
                            'Witterungs- & Windkegel',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Visualisiert die menschliche Geruchsausbreitung vor Ort.',
                            style: TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          value: _showWindScentCone,
                          activeTrackColor: WildlifeScoutTheme.crimsonScent,
                          onChanged: _updateShowWindScentCone,
                        ),
                        const Divider(
                          height: 1,
                          color: WildlifeScoutTheme.borderSubtle,
                        ),

                        // Objektiv-Blickwinkel (FOV-Modus)
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: WildlifeScoutTheme.amberGold
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: WildlifeScoutTheme.amberGold,
                            ),
                          ),
                          title: const Text(
                            'Objektiv-Bildwinkel (FOV)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Passt den Peilstrahl exakt an den optischen Bildwinkel deines Teleobjektivs an.',
                            style: TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          value: _showLensFieldOfView,
                          activeTrackColor: WildlifeScoutTheme.amberGold,
                          onChanged: _updateShowLensFieldOfView,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ==========================================
                    // Accordion 4: Einheiten & Mess-Format
                    // ==========================================
                    _buildAccordionSection(
                      index: 3,
                      icon: Icons.tune_rounded,
                      iconColor: Colors.deepPurpleAccent,
                      title: 'Einheiten & Mess-Format',
                      subtitle: 'Windgeschwindigkeit & Distanzen',
                      summaryBadge:
                          '${_windSpeedUnit.toUpperCase()} • ${_distanceUnit == "metric" ? "km" : "mi"}',
                      children: [
                        // Wind-Einheit
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.deepPurpleAccent
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.speed_rounded,
                                size: 16,
                                color: Colors.deepPurpleAccent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Wind-Geschwindigkeitseinheit',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Darstellung auf Witterungs-Kompass & Wetterkarte',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: WildlifeScoutTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildSegmentChip(
                              label: 'km/h',
                              isSelected: _windSpeedUnit == 'kmh',
                              onSelect: () => _updateWindSpeedUnit('kmh'),
                            ),
                            _buildSegmentChip(
                              label: 'Beaufort (Bft)',
                              isSelected: _windSpeedUnit == 'bft',
                              onSelect: () => _updateWindSpeedUnit('bft'),
                            ),
                            _buildSegmentChip(
                              label: 'm/s',
                              isSelected: _windSpeedUnit == 'ms',
                              onSelect: () => _updateWindSpeedUnit('ms'),
                            ),
                            _buildSegmentChip(
                              label: 'Knoten (kn)',
                              isSelected: _windSpeedUnit == 'kn',
                              onSelect: () => _updateWindSpeedUnit('kn'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(
                          height: 1,
                          color: WildlifeScoutTheme.borderSubtle,
                        ),
                        const SizedBox(height: 8),

                        // Distanz-Einheit
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.deepPurpleAccent
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.straighten_rounded,
                                size: 16,
                                color: Colors.deepPurpleAccent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Distanzen & Entfernungen',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Format für Distanzen & Geländepunkte',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: WildlifeScoutTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildSegmentChip(
                              label: 'Metrisch (km / m)',
                              isSelected: _distanceUnit == 'metric',
                              onSelect: () => _updateDistanceUnit('metric'),
                            ),
                            _buildSegmentChip(
                              label: 'Imperial (mi / yd)',
                              isSelected: _distanceUnit == 'imperial',
                              onSelect: () => _updateDistanceUnit('imperial'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ==========================================
                    // Accordion 5: Datenschutz & Speicher
                    // ==========================================
                    _buildAccordionSection(
                      index: 4,
                      icon: Icons.security_rounded,
                      iconColor: WildlifeScoutTheme.cyanWater,
                      title: 'Datenschutz & Speicher',
                      subtitle: 'Zero-Track Garantie & Spot-Tresor',
                      summaryBadge: 'Zero-Track',
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: WildlifeScoutTheme.cyanWater
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.verified_user_rounded,
                                size: 16,
                                color: WildlifeScoutTheme.cyanWater,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'DSGVO & Zero-Track Garantie',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Deine Suchanfragen und Fotospots bleiben lokal. Der CoordinateGuard rundet Wetter-Abfragen auf 2 km ab.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: WildlifeScoutTheme.textMuted,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Divider(
                          height: 1,
                          color: WildlifeScoutTheme.borderSubtle,
                        ),
                        const SizedBox(height: 8),

                        // Lokaler Spot-Tresor Status
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.lock_outline_rounded,
                                size: 16,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Spot-Tresor (SpotVault)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '$_savedSpotsCount Fotospots sicher auf diesem Gerät gespeichert',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: WildlifeScoutTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'OFFLINE',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: WildlifeScoutTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Reset-Button auf Standardwerte
                    Center(
                      child: TextButton.icon(
                        onPressed: _resetDefaults,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text(
                          'Auf Standardwerte zurücksetzen (50 km)',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: WildlifeScoutTheme.textMuted,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Baut einen animierten, klappbaren Accordion-Karten-Listenpunkt nach Apple HIG.
  Widget _buildAccordionSection({
    required int index,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String summaryBadge,
    Color? badgeColor,
    required List<Widget> children,
  }) {
    final isExpanded = _expandedIndices.contains(index);

    return Material(
      color: WildlifeScoutTheme.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded
                ? iconColor.withValues(alpha: 0.4)
                : WildlifeScoutTheme.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Klickbare Accordion-Kopfzeile
            InkWell(
              onTap: () => _toggleSection(index),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        size: 17,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: WildlifeScoutTheme.textMuted
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Kompakte Statusanzeige auch im zugeklappten Zustand
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (badgeColor ?? iconColor).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (badgeColor ?? iconColor)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        summaryBadge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: badgeColor ?? iconColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: WildlifeScoutTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Ausklappbarer Rumpf (Progressive Disclosure)
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: isExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(
                            height: 1,
                            color: WildlifeScoutTheme.borderSubtle,
                          ),
                          const SizedBox(height: 12),
                          ...children,
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// Segment-Chip für Einheiten und Optionen
  Widget _buildSegmentChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? Colors.white : WildlifeScoutTheme.textMuted,
        ),
      ),
      selected: isSelected,
      selectedColor: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.35),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      side: BorderSide(
        color: isSelected
            ? WildlifeScoutTheme.emeraldBio
            : WildlifeScoutTheme.borderSubtle,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onSelected: (_) => onSelect(),
    );
  }
}
