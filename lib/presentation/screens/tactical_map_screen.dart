import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../core/privacy/coordinate_guard.dart';
import '../../core/theme/wildscout_theme.dart';
import '../../data/api/location_search_client.dart';
import '../../data/api/open_meteo_client.dart';
import '../../data/repositories/species_repository.dart';
import '../../data/repositories/spot_vault_repository.dart';
import '../../data/services/app_settings_service.dart';
import '../../data/services/compass_heading_service.dart';
import '../../data/services/device_location_service.dart';
import '../../data/services/photo_gear_service.dart';
import '../../domain/models/habitat_zone.dart';
import '../../domain/models/photo_gear_profile.dart';
import '../../domain/models/secret_spot.dart';
import '../../domain/models/soil_substrate_profile.dart';
import '../../domain/models/species_profile.dart';
import '../../domain/models/weather_frame.dart';
import '../../domain/models/severe_weather_alert.dart';
import '../../domain/services/activity_score_calculator.dart';
import '../../domain/services/habitat_suitability_engine.dart';
import '../../domain/services/sun_moon_calculator.dart';
import '../widgets/app_settings_sheet.dart';
import '../widgets/device_heading_beam.dart';
import '../widgets/location_search_sheet.dart';
import '../widgets/map_layers_sheet.dart';
import '../widgets/photo_gear_sheet.dart';
import '../widgets/severe_weather_alert_sheet.dart';
import '../widgets/species_inspector_sheet.dart';
import '../widgets/species_multiselect_sheet.dart';
import '../widgets/spot_vault_sheet.dart';
import '../widgets/tactical_overlay_builder.dart';
import '../widgets/wind_scent_compass_sheet.dart';

class TacticalMapScreen extends StatefulWidget {
  const TacticalMapScreen({super.key});

  @override
  State<TacticalMapScreen> createState() => _TacticalMapScreenState();
}

class _TacticalMapScreenState extends State<TacticalMapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late final AnimationController _radarController;
  int _activeScanToken = 0;
  final SpeciesRepository _speciesRepo = SpeciesRepository();
  final SpotVaultRepository _vaultRepo = SpotVaultRepository();
  final OpenMeteoClient _weatherClient = OpenMeteoClient();
  final LocationSearchClient _locationClient = LocationSearchClient();

  List<SpeciesProfile> _speciesList = [];
  // Primärer Fokus: Rehwild ('roe_deer'), erweiterbar per Multi-Select
  Set<String> _selectedSpeciesIds = {'roe_deer'};
  List<SecretSpot> _savedSpots = [];

  LatLng _territoryOrigin = const LatLng(51.1657, 10.4515);
  LatLng _hidePinPosition = const LatLng(51.1657, 10.4515);
  String _currentRegionTitle = 'Aktueller Standort';
  bool _isLocatingUser = true;

  // 7-Tage Vorplanung (7 Tage x 24 Stunden = 168 Stunden)
  List<WeatherFrame> _hourlyForecast =
      OpenMeteoClient.buildOfflineFallbackForecast();
  int _selectedDayOffset = 0; // 0 = Heute, 1 = Morgen, ... bis 6
  int _selectedHourOfDay =
      DateTime.now().hour; // Standardmäßig aktuelle Stunde ("Jetzt")

  List<HabitatZone> _habitatZones = [];
  List<DisturbanceTrail> _disturbanceTrails = [];
  HabitatZone? _selectedZoneInfo;
  SoilSubstrateProfile? _currentSoilProfile;
  String _osmDataSourceStatus = 'Lade echte OpenStreetMap-Geometrien...';
  String? _bestChanceBannerInfo;

  // UI Toggles (hinter dem Karten-Elemente-Button gebündelt)
  bool _isNightVisionRedMode = false;
  bool _useSatelliteLayer = true;
  bool _showPlaceNames = true;
  bool _showRainRadarLayer = false;
  bool _showHabitatLayer = true;
  bool _showDisturbanceLayer = true;
  bool _showScentCone = true;
  bool _isLoadingOsm = false;
  bool _isDeckExpanded = false;
  bool _isSessionActive = true;
  AppSettings _appSettings = const AppSettings();
  PhotoGearProfile _currentPhotoGear = PhotoGearService.defaultGear;
  String? _lastAlertedWeatherKey;
  StreamSubscription<CompassHeadingData>? _headingSubscription;
  double? _deviceHeading;

  int get _activeForecastIndex =>
      (_selectedDayOffset * 24 + _selectedHourOfDay).clamp(
        0,
        _hourlyForecast.length - 1,
      );

  List<SpeciesProfile> get _selectedSpeciesProfiles {
    if (_speciesList.isEmpty) return const [];
    final matching = _speciesList
        .where((sp) => _selectedSpeciesIds.contains(sp.id))
        .toList();
    return matching.isNotEmpty ? matching : [_speciesList.first];
  }

  SpeciesProfile? get _primarySpecies {
    final selected = _selectedSpeciesProfiles;
    if (selected.isEmpty) return null;
    // Wenn Rehwild unter den ausgewählten Arten ist, bleibt Rehwild die Primärart
    for (final sp in selected) {
      if (sp.id == 'roe_deer') return sp;
    }
    return selected.first;
  }

  @override
  void initState() {
    super.initState();
    _selectedHourOfDay = DateTime.now().hour;
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1850),
    )..repeat();
    _headingSubscription = CompassHeadingService.stream.listen((data) {
      if (!mounted) return;
      if (data.hasSensor) {
        if (_deviceHeading == null ||
            (_deviceHeading! - data.heading).abs() > 0.5) {
          setState(() {
            _deviceHeading = data.heading;
          });
        }
      } else if (_deviceHeading != null) {
        setState(() {
          _deviceHeading = null;
        });
      }
    });
    PhotoGearService.loadGear().then((gear) {
      if (!mounted) return;
      setState(() {
        _currentPhotoGear = gear;
      });
    });
    PhotoGearService.gearNotifier.addListener(_onPhotoGearChanged);
    _initializeAppData();
  }

  @override
  void dispose() {
    PhotoGearService.gearNotifier.removeListener(_onPhotoGearChanged);
    _radarController.dispose();
    _headingSubscription?.cancel();
    super.dispose();
  }

  void _onPhotoGearChanged() {
    if (!mounted) return;
    setState(() {
      _currentPhotoGear = PhotoGearService.gearNotifier.value;
    });
  }

  Future<void> _initializeAppData() async {
    final loadedSpecies = await _speciesRepo.loadAllSpecies();
    final spots = await _vaultRepo.loadSpots();
    final lastSaved = await DeviceLocationService.loadLastSavedLocation();
    final settings = await AppSettingsService.loadSettings();

    if (!mounted) return;
    setState(() {
      _speciesList = loadedSpecies;
      _selectedSpeciesIds = {'roe_deer'};
      _savedSpots = spots;
      _appSettings = settings;
      _showPlaceNames = settings.showPlaceNamesOnSatellite;
      _showRainRadarLayer = settings.showRainRadarLayer;
      _showScentCone = settings.showWindScentCone;
      if (lastSaved != null) {
        _territoryOrigin = lastSaved.coordinate;
        _hidePinPosition = lastSaved.coordinate;
        _currentRegionTitle = lastSaved.label ?? 'Aktueller Standort';
      }
    });

    if (lastSaved != null && !settings.autoCenterGpsOnStart) {
      setState(() {
        _isLocatingUser = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(lastSaved.coordinate, 14.5);
        } catch (_) {}
      });
      _recalculateHabitatZones(lastSaved.coordinate);
      _refreshWeatherForPosition(lastSaved.coordinate);
    } else {
      await _locateAndMoveToCurrentPosition(initialLoad: true);
    }
  }

  Future<void> _locateAndMoveToCurrentPosition({
    bool initialLoad = false,
  }) async {
    setState(() {
      _isLocatingUser = true;
      _osmDataSourceStatus = 'Ermittle aktuellen Standort...';
    });

    final detected = await DeviceLocationService.determineCurrentLocation();
    if (!mounted) return;

    if (detected != null) {
      final pos = detected.coordinate;
      final initialTitle = detected.label ?? 'Aktueller Standort';

      setState(() {
        _territoryOrigin = pos;
        _hidePinPosition = pos;
        _currentRegionTitle = initialTitle;
        _isLocatingUser = false;
        _isLoadingOsm = true;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(pos, 14.5);
        } catch (_) {}
      });

      _recalculateHabitatZones(pos);
      _refreshWeatherForPosition(pos);
      DeviceLocationService.saveLastLocation(pos, initialTitle);

      // Ortsnamen im Hintergrund aufschlüsseln
      _locationClient.reverseGeocodeRegionName(pos).then((resolvedName) {
        if (!mounted || resolvedName == null || resolvedName.isEmpty) return;
        setState(() {
          _currentRegionTitle = resolvedName;
        });
        DeviceLocationService.saveLastLocation(pos, resolvedName);
      });
    } else {
      setState(() {
        _isLocatingUser = false;
      });
      if (initialLoad && _habitatZones.isEmpty) {
        _recalculateHabitatZones(_territoryOrigin);
        _refreshWeatherForPosition(_territoryOrigin);
      }
    }
  }

  void _recalculateHabitatZones(LatLng origin) {
    final primary = _primarySpecies;
    final selectedList = _selectedSpeciesProfiles;
    if (primary == null || selectedList.isEmpty) return;

    final int scanToken = ++_activeScanToken;
    final scanStartedAt = DateTime.now();

    final immediate = HabitatSuitabilityEngine.analyzeFromCachedRealOsm(
      origin: origin,
      species: primary,
      selectedSpeciesList: selectedList,
    );

    setState(() {
      _territoryOrigin = origin;
      _habitatZones = immediate.habitatZones;
      _disturbanceTrails = immediate.disturbanceTrails;
      _osmDataSourceStatus = immediate.dataSourceLabel;
      _selectedZoneInfo = null;
      _isLoadingOsm = true;
    });

    HabitatSuitabilityEngine.fetchAndAnalyzeLiveOsm(
      origin: origin,
      species: primary,
      selectedSpeciesList: selectedList,
    ).then((liveResult) async {
      if (!mounted || scanToken != _activeScanToken) return;
      setState(() {
        _habitatZones = liveResult.habitatZones;
        _disturbanceTrails = liveResult.disturbanceTrails;
        _currentSoilProfile = liveResult.soilProfile;
        _osmDataSourceStatus = liveResult.dataSourceLabel;
      });

      // Mindestens ca. eine volle Radar-Umdrehung sichtbar lassen,
      // auch wenn der Sektor bereits im lokalen Cache lag.
      final elapsedMs =
          DateTime.now().difference(scanStartedAt).inMilliseconds;
      const minRadarSweepMs = 1500;
      if (elapsedMs < minRadarSweepMs) {
        await Future<void>.delayed(
          Duration(milliseconds: minRadarSweepMs - elapsedMs),
        );
      }
      if (!mounted || scanToken != _activeScanToken) return;
      setState(() {
        _isLoadingOsm = false;
      });
    });
  }

  Future<void> _refreshWeatherForPosition(LatLng pos) async {
    final frames = await _weatherClient.fetchHourlyForecast(
      latitude: pos.latitude,
      longitude: pos.longitude,
    );
    if (!mounted) return;
    setState(() {
      _hourlyForecast = frames;
    });
  }

  void _onMapTapped(TapPosition tapPosition, LatLng point) {
    const dist = Distance();
    final metersFromLastScan = dist.as(
      LengthUnit.Meter,
      _territoryOrigin,
      point,
    );

    setState(() {
      _hidePinPosition = point;
      _selectedZoneInfo = null;
    });

    _recalculateHabitatZones(point);
    DeviceLocationService.saveLastLocation(point, _currentRegionTitle);

    if (metersFromLastScan > 450.0 || _disturbanceTrails.isEmpty) {
      _refreshWeatherForPosition(point);
    }
  }

  void _scanCurrentMapCenterAsNewTerritory() {
    final center = _mapController.camera.center;
    final title =
        '${center.latitude.toStringAsFixed(2)}, ${center.longitude.toStringAsFixed(2)}';
    setState(() {
      _hidePinPosition = center;
      _currentRegionTitle = title;
      _isLoadingOsm = true;
      _osmDataSourceStatus = 'Scanne echte OpenStreetMap-Polygone im Sektor...';
    });
    _recalculateHabitatZones(center);
    _refreshWeatherForPosition(center);
    DeviceLocationService.saveLastLocation(center, title);
  }

  void _openSpeciesMultiSelectSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SpeciesMultiSelectSheet(
        allSpecies: _speciesList,
        initialSelectedIds: _selectedSpeciesIds,
        onSelectionChanged: (updatedIds) {
          setState(() {
            _selectedSpeciesIds = updatedIds;
          });
          _recalculateHabitatZones(_territoryOrigin);
        },
        onInspectSpecies: _openSpeciesInspectorFor,
      ),
    );
  }

  void _openMapLayersSheet() {
    final primary = _primarySpecies;
    if (primary == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return MapLayersSheet(
            primarySpecies: primary,
            habitatCount: _habitatZones.length,
            trailCount: _disturbanceTrails.length,
            useSatelliteLayer: _useSatelliteLayer,
            showHabitatLayer: _showHabitatLayer,
            showDisturbanceLayer: _showDisturbanceLayer,
            showScentCone: _showScentCone,
            isNightVisionRedMode: _isNightVisionRedMode,
            onChangedSatellite: (val) {
              setState(() => _useSatelliteLayer = val);
              setSheetState(() {});
            },
            onChangedHabitat: (val) {
              setState(() => _showHabitatLayer = val);
              setSheetState(() {});
            },
            onChangedDisturbance: (val) {
              setState(() => _showDisturbanceLayer = val);
              setSheetState(() {});
            },
            onChangedScentCone: (val) {
              setState(() => _showScentCone = val);
              setSheetState(() {});
            },
            onChangedNightVision: (val) {
              setState(() => _isNightVisionRedMode = val);
              setSheetState(() {});
            },
            onScanCurrentMapCenter: _scanCurrentMapCenterAsNewTerritory,
          );
        },
      ),
    );
  }

  void _showTelemetryExplainerSheet({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<({String heading, String description, IconData icon})> points,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: BoxDecoration(
          color: WildScoutTheme.surfaceGlass,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: WildScoutTheme.borderSubtle),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 30,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: WildScoutTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WildScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final p in points) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(p.icon, size: 16, color: iconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.heading,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: WildScoutTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.description,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: WildScoutTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openWindCompassSheet() {
    final primary = _primarySpecies;
    if (primary == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final currentWeather = _hourlyForecast.isNotEmpty
              ? _hourlyForecast[_activeForecastIndex]
              : OpenMeteoClient.buildOfflineFallbackForecast()[0];

          return WindScentCompassSheet(
            weather: currentWeather,
            primarySpecies: primary,
            hidePosition: _hidePinPosition,
            habitatZones: _habitatZones,
            savedSpots: _savedSpots,
            selectedZone: _selectedZoneInfo,
            hourlyForecast: _hourlyForecast,
            selectedHourOfDay: _selectedHourOfDay,
            selectedDayOffset: _selectedDayOffset,
            onHourChanged: (newHour) {
              setState(() {
                _selectedHourOfDay = newHour;
              });
              setSheetState(() {});
            },
            onDayChanged: (newDay) {
              setState(() {
                _selectedDayOffset = newDay;
              });
              setSheetState(() {});
            },
          );
        },
      ),
    );
  }

  void _openLocationSearchSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocationSearchSheet(
        onUseCurrentLocation: () {
          _locateAndMoveToCurrentPosition();
        },
        onLocationSelected: (loc) {
          setState(() {
            _currentRegionTitle = loc.title;
            _hidePinPosition = loc.coordinate;
            _isLoadingOsm = true;
            _osmDataSourceStatus =
                'Lade echte OSM-Daten für ${loc.title}...';
          });
          _mapController.move(loc.coordinate, 14.5);
          _recalculateHabitatZones(loc.coordinate);
          _refreshWeatherForPosition(loc.coordinate);
          DeviceLocationService.saveLastLocation(loc.coordinate, loc.title);
        },
      ),
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AppSettingsSheet(
        onSettingsChanged: () {
          AppSettingsService.loadSettings().then((settings) {
            if (mounted) {
              setState(() {
                _appSettings = settings;
                _showPlaceNames = settings.showPlaceNamesOnSatellite;
                _showRainRadarLayer = settings.showRainRadarLayer;
                _showScentCone = settings.showWindScentCone;
              });
            }
          });
        },
      ),
    );
  }

  void _toggleSessionStatus() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSessionActive = !_isSessionActive;
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isSessionActive
              ? 'Fotosession aktiv • Unwetter-Wächter scharf'
              : 'Fotosession pausiert • Keine aktiven Warnungen',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: WildScoutTheme.surfaceCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openSpotVaultSheet(WeatherFrame currentWeather) {
    final sp = _primarySpecies;
    if (sp == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SpotVaultSheet(
        spots: _savedSpots,
        allSpecies: _speciesList,
        currentMapPosition: _hidePinPosition,
        activeSpecies: sp,
        currentWindCardinal: currentWeather.windCardinalLabel,
        onSelectSpot: (spot) {
          setState(() {
            _selectedSpeciesIds = {spot.speciesId};
            _currentRegionTitle = spot.title;
            _hidePinPosition = spot.coordinate;
          });
          _mapController.move(spot.coordinate, 14.8);
          _recalculateHabitatZones(spot.coordinate);
          _refreshWeatherForPosition(spot.coordinate);
          DeviceLocationService.saveLastLocation(spot.coordinate, spot.title);
        },
        onAddSpot: (newSpot) {
          final updated = [newSpot, ..._savedSpots];
          setState(() => _savedSpots = updated);
          _vaultRepo.saveSpots(updated);
        },
        onDeleteSpot: (id) {
          final updated = _savedSpots.where((s) => s.id != id).toList();
          setState(() => _savedSpots = updated);
          _vaultRepo.saveSpots(updated);
        },
      ),
    );
  }

  void _openSpeciesInspectorFor(SpeciesProfile sp) {
    final safe = CoordinateGuard.obfuscateForWeatherApi(
      _hidePinPosition.latitude,
      _hidePinPosition.longitude,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SpeciesInspectorSheet(
        species: sp,
        obfuscatedLat: safe.lat,
        obfuscatedLon: safe.lon,
        soilProfile: _currentSoilProfile,
      ),
    );
  }

  Color _accentForSpeciesId(String id) {
    for (final sp in _speciesList) {
      if (sp.id == id) return sp.accentColor;
    }
    return WildScoutTheme.emeraldBio;
  }

  Color _colorForActivityScore(int score) {
    if (score >= 78) return WildScoutTheme.emeraldBio;
    if (score >= 55) return WildScoutTheme.amberGold;
    return WildScoutTheme.textMuted;
  }

  int _calculateChanceScore(int activityScore, double suitabilityScore) {
    return ((activityScore + suitabilityScore) / 2.0).round().clamp(0, 100);
  }

  Color _colorForChanceScore(int score) {
    if (score >= 70) return WildScoutTheme.emeraldBio;
    if (score >= 45) return WildScoutTheme.amberGold;
    return WildScoutTheme.textMuted;
  }

  String _ratingForChanceScore(int score) {
    if (score >= 80) return 'Exzellent';
    if (score >= 68) return 'Sehr gut';
    if (score >= 50) return 'Gut';
    if (score >= 35) return 'Mäßig';
    return 'Gering';
  }

  TacticalAssessment _assessmentForZone({
    required HabitatZone zone,
    required WeatherFrame weather,
    required SunMoonPosition astro,
    required TacticalAssessment primaryAssessment,
    required Map<String, TacticalAssessment> cachedAssessments,
  }) {
    if (cachedAssessments.containsKey(zone.speciesId)) {
      return cachedAssessments[zone.speciesId]!;
    }
    final match = _speciesList.where((s) => s.id == zone.speciesId);
    if (match.isEmpty) return primaryAssessment;
    final res = ActivityScoreCalculator.evaluate(
      species: match.first,
      weather: weather,
      astro: astro,
      hidePosition: _hidePinPosition,
      habitatZones: _habitatZones,
    );
    cachedAssessments[zone.speciesId] = res;
    return res;
  }

  String _dayLabelForOffset(int dayOffset) {
    final date = DateTime.now().add(Duration(days: dayOffset));
    if (dayOffset == 0) return 'Heute';
    if (dayOffset == 1) return 'Morgen';
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final wd = weekdays[(date.weekday - 1) % 7];
    return '$wd ${date.day}.${date.month}.';
  }

  /// Ermittelt und wendet die „Beste Chance“ an (Tag, Uhrzeit, Hotspot-Ort ohne Witterungskollision)
  void _applyBestChanceOpportunity() {
    final primary = _primarySpecies;
    if (primary == null) return;

    if (_habitatZones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: WildScoutTheme.bgObsidian,
          content: const Row(
            children: [
              Icon(Icons.info_outline, color: WildScoutTheme.amberGold, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Noch keine Habitate geladen. Bitte scanne zuerst einen Sektor.',
                  style: TextStyle(color: WildScoutTheme.textPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // 1. Relevante Habitat-Zonen filtern (keine reinen Störzonen)
    final validZones = _habitatZones
        .where((z) => !z.isDisturbance)
        .toList();

    if (validZones.isEmpty) return;

    // Bevorzuge Zonen der Primärart, sonst alle validen
    final speciesZones = validZones.where((z) => z.speciesId == primary.id).toList();
    final candidateZones = speciesZones.isNotEmpty ? speciesZones : validZones;

    // Sortiere nach Habitat-Eignung
    candidateZones.sort((a, b) => b.suitabilityScore.compareTo(a.suitabilityScore));
    final targetZone = candidateZones.first;

    // 2. Optimalen Fotospot bestimmen:
    // Ca. 70m Luv-/Seitenabstand zum Zonen-Zentrum oder direkt das Zentrum,
    // falls hidePosition schon nahe liegt
    final targetCenter = targetZone.center;

    // 3. Suche in allen 168 Stunden nach der besten Kombination
    int bestDayOffset = _selectedDayOffset;
    int bestHour = _selectedHourOfDay;
    double highestScore = -1.0;
    TacticalAssessment? bestAssessment;

    final totalHours = _hourlyForecast.length;
    for (int idx = 0; idx < totalHours; idx++) {
      final weather = _hourlyForecast[idx];
      final dayOffset = (idx ~/ 24).clamp(0, 6);
      final hourOfDay = idx % 24;

      final astro = SunMoonCalculator.calculate(
        dateTime: weather.time,
        latitude: targetCenter.latitude,
        longitude: targetCenter.longitude,
      );

      final assessment = ActivityScoreCalculator.evaluate(
        species: primary,
        weather: weather,
        astro: astro,
        hidePosition: targetCenter,
        habitatZones: _habitatZones,
      );

      // Score-Berechnung:
      // Basis: Aktivitäts-Score (0-100)
      // Bonus für Golden Hour / Blaue Stunde (+10)
      // Starker Abzug bei Witterungskollision (-35)
      // Abzug bei Sturm / Regen
      double compositeScore = assessment.activityScorePercent.toDouble();
      if (astro.isGoldenHour || astro.isBlueHour) {
        compositeScore += 10.0;
      }
      if (assessment.hasScentCollision) {
        compositeScore -= 35.0;
      }
      if (weather.precipitationMm > 1.0) {
        compositeScore -= 15.0;
      }

      if (compositeScore > highestScore) {
        highestScore = compositeScore;
        bestDayOffset = dayOffset;
        bestHour = hourOfDay;
        bestAssessment = assessment;
      }
    }

    HapticFeedback.mediumImpact();

    final dayLabel = _dayLabelForOffset(bestDayOffset);
    final timeStr = '${bestHour.toString().padLeft(2, '0')}:00 Uhr';
    final scoreStr = bestAssessment != null
        ? '${bestAssessment.activityScorePercent}% Aktivität'
        : '${targetZone.suitabilityScore.round()}% Eignung';

    setState(() {
      _selectedDayOffset = bestDayOffset;
      _selectedHourOfDay = bestHour;
      _selectedZoneInfo = targetZone;
      _hidePinPosition = targetCenter;
      _bestChanceBannerInfo =
          '${targetZone.title} • $dayLabel um $timeStr ($scoreStr)';
    });

    _mapController.move(targetCenter, 15.5);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final activeSpecies = _primarySpecies;
    if (activeSpecies == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currentWeather = _hourlyForecast[_activeForecastIndex];

    final astro = SunMoonCalculator.calculate(
      dateTime: currentWeather.time,
      latitude: _hidePinPosition.latitude,
      longitude: _hidePinPosition.longitude,
    );

    final assessment = ActivityScoreCalculator.evaluate(
      species: activeSpecies,
      weather: currentWeather,
      astro: astro,
      hidePosition: _hidePinPosition,
      habitatZones: _habitatZones,
    );

    final assessmentsBySpecies = <String, TacticalAssessment>{
      activeSpecies.id: assessment,
    };
    for (final sp in _selectedSpeciesProfiles) {
      if (!assessmentsBySpecies.containsKey(sp.id)) {
        assessmentsBySpecies[sp.id] = ActivityScoreCalculator.evaluate(
          species: sp,
          weather: currentWeather,
          astro: astro,
          hidePosition: _hidePinPosition,
          habitatZones: _habitatZones,
        );
      }
    }

    final severeWeatherAlert = _isSessionActive
        ? SevereWeatherEvaluator.evaluateActiveSession(
            forecast: _hourlyForecast,
            activeForecastIndex: _activeForecastIndex,
            settings: _appSettings,
          )
        : null;

    if (severeWeatherAlert != null &&
        _appSettings.severeWeatherSoundAndHaptics &&
        _isSessionActive) {
      final alertKey =
          '${severeWeatherAlert.type}_${severeWeatherAlert.hoursUntilEvent}';
      if (_lastAlertedWeatherKey != alertKey) {
        _lastAlertedWeatherKey = alertKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          HapticFeedback.heavyImpact();
        });
      }
    }

    final polygons = TacticalOverlayBuilder.buildMapPolygons(
      hidePosition: _hidePinPosition,
      species: activeSpecies,
      weather: currentWeather,
      habitatZones: _habitatZones,
      showHabitatZones: _showHabitatLayer,
      showScentCone: _showScentCone,
      hasScentCollision: assessment.hasScentCollision,
    );

    final polylines = TacticalOverlayBuilder.buildMapPolylines(
      hidePosition: _hidePinPosition,
      species: activeSpecies,
      weather: currentWeather,
      astro: astro,
      trails: _disturbanceTrails,
      showDisturbanceTrails: _showDisturbanceLayer,
    );

    double mapRotation = 0.0;
    try {
      mapRotation = _mapController.camera.rotation;
    } catch (_) {}

    final mainContent = Scaffold(
      body: Stack(
        children: [
          // 1. Vollbild Satelliten- & Taktik-Karte (100% Echte OSM-Geometrie)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _hidePinPosition,
              initialZoom: 14.5,
              minZoom: 6.0,
              maxZoom: 18.5,
              onTap: _onMapTapped,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  setState(() {});
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _useSatelliteLayer
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'dev.wildlifescout.app',
                maxNativeZoom: 18,
                panBuffer: 0,
                keepBuffer: 2,
                tileProvider: NetworkTileProvider(
                  silenceExceptions: true,
                  attemptDecodeOfHttpErrorResponses: false,
                ),
                evictErrorTileStrategy: EvictErrorTileStrategy.none,
                errorTileCallback: (tile, error, stackTrace) {
                  // Graceful degradation bei kurzzeitigen Timeouts oder Funklöchern
                },
              ),
              // Optionales hybrides Ortsnamen- & Straßennetz-Overlay über Satellit (ArcGIS Reference & Transportation)
              if (_useSatelliteLayer && _showPlaceNames) ...[
                TileLayer(
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'dev.wildlifescout.app',
                  maxNativeZoom: 18,
                  panBuffer: 0,
                  keepBuffer: 2,
                  tileProvider: NetworkTileProvider(
                    silenceExceptions: true,
                    attemptDecodeOfHttpErrorResponses: false,
                  ),
                  evictErrorTileStrategy: EvictErrorTileStrategy.none,
                  errorTileCallback: (tile, error, stackTrace) {
                    // Graceful degradation bei Netzwerk-Timeouts
                  },
                ),
                TileLayer(
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'dev.wildlifescout.app',
                  maxNativeZoom: 18,
                  panBuffer: 0,
                  keepBuffer: 2,
                  tileProvider: NetworkTileProvider(
                    silenceExceptions: true,
                    attemptDecodeOfHttpErrorResponses: false,
                  ),
                  evictErrorTileStrategy: EvictErrorTileStrategy.none,
                  errorTileCallback: (tile, error, stackTrace) {
                    // Graceful degradation bei Netzwerk-Timeouts
                  },
                ),
              ],
              Container(
                color: Colors.black.withValues(
                  alpha: _useSatelliteLayer ? 0.16 : 0.34,
                ),
              ),
              // DWD Niederschlags- & Gewitterradar (WMS Open Data / GeoNutzV)
              if (_showRainRadarLayer)
                TileLayer(
                  wmsOptions: WMSTileLayerOptions(
                    baseUrl: 'https://maps.dwd.de/geoserver/dwd/wms?',
                    layers: const ['dwd:Niederschlagsradar'],
                    transparent: true,
                    version: '1.3.0',
                    crs: const Epsg3857(),
                    format: 'image/png',
                  ),
                  userAgentPackageName: 'dev.wildlifescout.app',
                  maxNativeZoom: 18,
                  panBuffer: 0,
                  keepBuffer: 2,
                  tileProvider: NetworkTileProvider(
                    silenceExceptions: true,
                    attemptDecodeOfHttpErrorResponses: false,
                  ),
                  evictErrorTileStrategy: EvictErrorTileStrategy.none,
                  errorTileCallback: (tile, error, stackTrace) {
                    // Graceful degradation bei WMS-Timeouts
                  },
                  tileBuilder: (context, tileWidget, tile) => Opacity(
                    opacity: 0.85,
                    child: tileWidget,
                  ),
                ),
              PolylineLayer(polylines: polylines),
              PolygonLayer(polygons: polygons),
              // Echte OSM Habitat-Hotspot-Pins zum Antippen (hochkontrastig & kollisionsfrei)
              if (_showHabitatLayer)
                MarkerLayer(
                  rotate: true,
                  markers: () {
                    // Ausgewähltes Habitat zuletzt rendern, damit es immer im Vordergrund liegt
                    final sortedZones = List<HabitatZone>.from(_habitatZones);
                    if (_selectedZoneInfo != null) {
                      sortedZones.removeWhere((z) => z.id == _selectedZoneInfo!.id);
                      sortedZones.add(_selectedZoneInfo!);
                    }
                    return sortedZones.map((zone) {
                      final isSelected = _selectedZoneInfo?.id == zone.id;
                      final zoneAssessment = _assessmentForZone(
                        zone: zone,
                        weather: currentWeather,
                        astro: astro,
                        primaryAssessment: assessment,
                        cachedAssessments: assessmentsBySpecies,
                      );
                      return Marker(
                        point: zone.center,
                        width: isSelected ? 260 : 108,
                        height: isSelected ? 124 : 44,
                        rotate: true,
                        alignment: isSelected
                            ? const Alignment(0.0, 0.435)
                            : Alignment.center,
                        child: _buildHabitatMarker(zone, zoneAssessment),
                      );
                    }).toList();
                  }(),
                ),
              // Tarnzelt / Fotospot-Pin des Fotografen + Taktischer Radar-Sweep beim Scannen
              MarkerLayer(
                rotate: true,
                markers: [
                  Marker(
                    point: _hidePinPosition,
                    width: 240,
                    height: 240,
                    rotate: true,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Blickrichtungs-Fächer / Objektiv-FOV (Echtzeit-Sensordaten des Geräts)
                        if (_deviceHeading != null && _appSettings.showCompassHeadingBeam)
                          DeviceHeadingBeam(
                            headingDeg: (_deviceHeading! - mapRotation) % 360.0,
                            beamLength: _appSettings.showLensFieldOfView ? 70.0 : 58.0,
                            beamAngleDeg: _appSettings.showLensFieldOfView
                                ? _currentPhotoGear.horizontalFovDeg.clamp(3.0, 50.0)
                                : 50.0,
                            accentColor: WildScoutTheme.cyanWater,
                          ),

                        // Kreisförmige Radar-Animation während des Scannens
                        IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 320),
                            opacity:
                                (_isLoadingOsm || _isLocatingUser) ? 1.0 : 0.0,
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.easeOutBack,
                              scale: (_isLoadingOsm || _isLocatingUser)
                                  ? 1.0
                                  : 0.72,
                              child: _TacticalRadarSweep(
                                animation: _radarController,
                                color: WildScoutTheme.emeraldBio,
                              ),
                            ),
                          ),
                        ),
                        // ANSITZ / SCANNT / UNWETTER Badge direkt über dem runden Pin
                        Positioned(
                          top: 240 / 2 - 17 - 22,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              if (severeWeatherAlert != null) {
                                SevereWeatherAlertSheet.show(
                                  context,
                                  alert: severeWeatherAlert,
                                  onEndSession: () {
                                    setState(() => _isSessionActive = false);
                                  },
                                );
                              } else {
                                _toggleSessionStatus();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (_isLoadingOsm || _isLocatingUser)
                                    ? WildScoutTheme.emeraldBio
                                    : (severeWeatherAlert != null
                                        ? severeWeatherAlert.accentColor
                                        : (assessment.hasScentCollision
                                            ? WildScoutTheme.crimsonScent
                                            : (_isSessionActive
                                                ? WildScoutTheme.emeraldBio
                                                : Colors.white30))),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Text(
                                (_isLoadingOsm || _isLocatingUser)
                                    ? 'SCANNT...'
                                    : (severeWeatherAlert != null
                                        ? (severeWeatherAlert.isDanger
                                            ? '⚠️ GEFAHR'
                                            : '⚠️ UNWETTER')
                                        : (_isSessionActive ? 'ANSITZ' : 'PAUSE')),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: (severeWeatherAlert != null &&
                                          severeWeatherAlert.isDanger)
                                      ? Colors.white
                                      : Colors.black,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Exakt zentrierter Fotospot-Pin
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            if (severeWeatherAlert != null) {
                              SevereWeatherAlertSheet.show(
                                context,
                                alert: severeWeatherAlert,
                                onEndSession: () {
                                  setState(() => _isSessionActive = false);
                                },
                              );
                            } else {
                              _toggleSessionStatus();
                            }
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: WildScoutTheme.bgObsidian,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: (_isLoadingOsm || _isLocatingUser)
                                    ? WildScoutTheme.emeraldBio
                                    : (severeWeatherAlert != null
                                        ? severeWeatherAlert.accentColor
                                        : (assessment.hasScentCollision
                                            ? WildScoutTheme.crimsonScent
                                            : (_isSessionActive
                                                ? WildScoutTheme.amberGold
                                                : Colors.white38))),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isLoadingOsm || _isLocatingUser)
                                      ? WildScoutTheme.emeraldBio.withValues(
                                          alpha: 0.55,
                                        )
                                      : (severeWeatherAlert != null
                                          ? severeWeatherAlert.accentColor
                                              .withValues(alpha: 0.6)
                                          : Colors.black87),
                                  blurRadius: (_isLoadingOsm || _isLocatingUser)
                                      ? 14
                                      : (severeWeatherAlert != null ? 12 : 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              severeWeatherAlert != null
                                  ? severeWeatherAlert.icon
                                  : Icons.camera_alt_outlined,
                              size: 17,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Aufgeräumtes Top Tactical HUD (schlanke Liquid Glass Leiste)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(
                    activeSpecies,
                    currentWeather,
                    severeWeatherAlert,
                  ),
                  if (_isSessionActive && severeWeatherAlert != null) ...[
                    const SizedBox(height: 8),
                    _buildSevereWeatherHUDBanner(severeWeatherAlert),
                  ],
                  if (_selectedZoneInfo != null) ...[
                    const SizedBox(height: 10),
                    _buildZoneInfoCard(
                      _selectedZoneInfo!,
                      _assessmentForZone(
                        zone: _selectedZoneInfo!,
                        weather: currentWeather,
                        astro: astro,
                        primaryAssessment: assessment,
                        cachedAssessments: assessmentsBySpecies,
                      ),
                    ),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: _bestChanceBannerInfo != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.0, -0.2),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutBack,
                                      ),
                                    ),
                                    child: child,
                                  ),
                                );
                              },
                              child: KeyedSubtree(
                                key: ValueKey(_bestChanceBannerInfo),
                                child: _buildBestChanceHUDCard(_bestChanceBannerInfo!),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),

          // 3. Daumenzone: Vertikale schwebende Taktik-Insel (Rechts)
          // Dynamischer Abstand nach unten, damit die Daumen-Navigation niemals von der unteren Box überdeckt wird
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            right: 14,
            bottom: (_isDeckExpanded
                    ? (isMobile ? 480.0 : 420.0)
                    : (isMobile ? 260.0 : 210.0)) +
                MediaQuery.of(context).padding.bottom,
            child: _buildFloatingTacticalIsland(currentWeather),
          ),

          // 4. Bottom Thumb-Zone Tactical Control Deck (Adaptive Progressive Disclosure)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: _buildBottomTacticalDeck(
                  species: activeSpecies,
                  weather: currentWeather,
                  astro: astro,
                  assessment: assessment,
                  severeWeatherAlert: severeWeatherAlert,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (_isNightVisionRedMode) {
      return ColorFiltered(
        colorFilter: WildScoutTheme.nightVisionRedMatrix,
        child: mainContent,
      );
    }

    return mainContent;
  }

  Widget _buildTopBar(
    SpeciesProfile primarySpecies,
    WeatherFrame currentWeather,
    SevereWeatherAlert? severeWeatherAlert,
  ) {
    final extraCount = _selectedSpeciesIds.length - 1;
    final speciesButtonLabel = extraCount > 0
        ? '${primarySpecies.name} +$extraCount'
        : primarySpecies.name;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: WildScoutTheme.glassDecoration(
            borderRadius: 20,
            shadows: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [WildScoutTheme.emeraldBio, Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: RotationTransition(
                  turns: (_isLoadingOsm || _isLocatingUser)
                      ? _radarController
                      : const AlwaysStoppedAnimation(0.0),
                  child: const Icon(
                    Icons.radar,
                    color: Colors.black,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Tooltip(
                  message: _osmDataSourceStatus,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Zeile 1: Titel WILDLIFESCOUT
                      const Text(
                        'WILDLIFESCOUT',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.0,
                          letterSpacing: 0.6,
                          color: WildScoutTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Zeile 2: Region • Habitate
                      Text(
                        _isLoadingOsm
                            ? 'Scanne OSM-Geometrien...'
                            : '$_currentRegionTitle • ${_habitatZones.length} Habitate',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: WildScoutTheme.textMuted,
                        ),
                      ),
                      if (severeWeatherAlert != null) ...[
                        const SizedBox(height: 3),
                        InkWell(
                          onTap: () {
                            SevereWeatherAlertSheet.show(
                              context,
                              alert: severeWeatherAlert,
                              onEndSession: () =>
                                  setState(() => _isSessionActive = false),
                            );
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: severeWeatherAlert.accentColor
                                  .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: severeWeatherAlert.accentColor
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  severeWeatherAlert.icon,
                                  size: 9.5,
                                  color: severeWeatherAlert.accentColor,
                                ),
                                const SizedBox(width: 2.5),
                                Text(
                                  severeWeatherAlert.isDanger
                                      ? 'ALARM'
                                      : 'UNWETTER',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                    color: severeWeatherAlert.accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Kompakter Tier-Auswahl Button mit Bild als Background
              Tooltip(
                message: 'Wildarten & Biologie-Steckbrief öffnen',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _openSpeciesMultiSelectSheet();
                    },
                    child: Container(
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primarySpecies.accentColor.withValues(alpha: 0.85),
                          width: 1.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: WildScoutTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          const BoxShadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                          BoxShadow(
                            color: primarySpecies.accentColor.withValues(alpha: 0.20),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: _buildSpeciesBackground(primarySpecies),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withValues(alpha: 0.65),
                                    Colors.black.withValues(alpha: 0.52),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: isMobile ? 120 : 160,
                                  ),
                                  child: Text(
                                    speciesButtonLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          blurRadius: 4,
                                          color: Colors.black,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeciesBackground(SpeciesProfile species) {
    if (species.imageAssetPath.isNotEmpty) {
      return Image.asset(
        species.imageAssetPath,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          if (species.imageUrl.isNotEmpty) {
            return Image.network(
              species.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: species.accentColor.withValues(alpha: 0.3),
              ),
            );
          }
          return Container(
            color: species.accentColor.withValues(alpha: 0.3),
          );
        },
      );
    }
    if (species.imageUrl.isNotEmpty) {
      return Image.network(
        species.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: species.accentColor.withValues(alpha: 0.3),
        ),
      );
    }
    return Container(
      color: species.accentColor.withValues(alpha: 0.3),
    );
  }

  /// Schwebende Taktik-Insel in der ergonomischen Daumenzone (Rechts)
  Widget _buildFloatingTacticalIsland(WeatherFrame currentWeather) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 1. GPS / Standort zentrieren
        _TacticalFloatingButton(
          icon: Icons.my_location_rounded,
          tooltip: 'Zum aktuellen Standort springen',
          isLoading: _isLocatingUser,
          iconColor: WildScoutTheme.emeraldBio,
          onTap: () {
            HapticFeedback.lightImpact();
            _locateAndMoveToCurrentPosition();
          },
        ),
        const SizedBox(height: 6),

        // 2. Ort / Waldgebiet suchen
        _TacticalFloatingButton(
          icon: Icons.search_rounded,
          tooltip: 'Ort, Waldgebiet oder Koordinaten suchen',
          onTap: () {
            HapticFeedback.lightImpact();
            _openLocationSearchSheet();
          },
        ),
        const SizedBox(height: 6),

        // 3. Karten-Ebenen & Nachtmodus
        _TacticalFloatingButton(
          icon: Icons.layers_rounded,
          tooltip: 'Karten-Ebenen & Nachtsicht',
          badgeColor: _isNightVisionRedMode
              ? WildScoutTheme.crimsonScent
              : (_showRainRadarLayer
                  ? WildScoutTheme.cyanWater
                  : (!_useSatelliteLayer ? WildScoutTheme.cyanWater : null)),
          onTap: () {
            HapticFeedback.lightImpact();
            _openMapLayersSheet();
          },
        ),
        const SizedBox(height: 6),

        // 4. Taktischer Witterungs- & Wind-Kompass (360° Rose & Scent-Cone)
        _TacticalFloatingButton(
          icon: Icons.explore_rounded,
          tooltip: 'Witterungs- & Wind-Kompass (${currentWeather.windCardinalLabel}, ${currentWeather.windSpeedKmh.round()} km/h)',
          badgeColor: WildScoutTheme.cyanWater,
          iconColor: WildScoutTheme.cyanWater,
          onTap: () {
            HapticFeedback.lightImpact();
            _openWindCompassSheet();
          },
        ),
        const SizedBox(height: 6),

        // 5. Foto-Ausrüstung & Wildlife-Optik (Brennweite, Sensor, FOV)
        _TacticalFloatingButton(
          icon: Icons.camera_alt_rounded,
          tooltip:
              'Foto-Ausrüstung & Optik (${_currentPhotoGear.effectiveFocalLengthMm.round()} mm KB)',
          badgeColor: WildScoutTheme.cyanWater,
          iconColor: WildScoutTheme.cyanWater,
          onTap: () {
            HapticFeedback.lightImpact();
            PhotoGearSheet.show(
              context,
              onGearChanged: () {
                setState(() {
                  _currentPhotoGear = PhotoGearService.gearNotifier.value;
                });
              },
            );
          },
        ),
        const SizedBox(height: 6),

        // 6. Geheimer Spot-Tresor (mit dezentem Indikator)
        _TacticalFloatingButton(
          icon: Icons.bookmark_rounded,
          tooltip: 'Geheimer Spot-Tresor (${_savedSpots.length})',
          badgeColor: _savedSpots.isNotEmpty ? WildScoutTheme.amberGold : null,
          iconColor: WildScoutTheme.amberGold,
          onTap: () {
            HapticFeedback.lightImpact();
            _openSpotVaultSheet(currentWeather);
          },
        ),
        const SizedBox(height: 6),

        // 7. App-Einstellungen & Umkreissuche
        _TacticalFloatingButton(
          icon: Icons.tune_rounded,
          tooltip: 'App-Einstellungen & Suchradius',
          onTap: () {
            HapticFeedback.lightImpact();
            _openSettingsSheet();
          },
        ),
        const SizedBox(height: 6),

        // 8. Quick Action: "Beste Chance" (Kompakte quadratische Liquid-Glass-Pille)
        _TacticalBestChanceButton(
          hasZones: _habitatZones.isNotEmpty,
          onTap: _applyBestChanceOpportunity,
        ),
      ],
    );
  }

  Widget _buildHabitatMarker(
    HabitatZone zone,
    TacticalAssessment zoneAssessment,
  ) {
    final isSelected = _selectedZoneInfo?.id == zone.id;
    final accentColor = zone.type == HabitatZoneType.waterSuhle
        ? WildScoutTheme.cyanWater
        : _accentForSpeciesId(zone.speciesId);

    final activityScore = zoneAssessment.activityScorePercent;
    final activityColor = _colorForActivityScore(activityScore);
    final chanceScore =
        _calculateChanceScore(activityScore, zone.suitabilityScore);
    final chanceColor = _colorForChanceScore(chanceScore);

    if (isSelected) {
      // Ausgewähltes Habitat: Vertikaler Callout-Pin mit Aufklapp-Details (Aktivität & Biotop)
      // Der Text schwebt in einer eigenen Badge-Box FREI ÜBER dem Pin.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _selectedZoneInfo = null);
        },
        child: SizedBox(
          width: 260,
          height: 124,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Text-Callout über dem Pin (schwebt frei über dem Badge)
              Positioned(
                top: 0,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 254),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: WildScoutTheme.bgObsidian.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 1.6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.85),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                      BoxShadow(
                        color: chanceColor.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header-Zeile mit Spot-Titel & Chance-Badge
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              zone.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: chanceColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: chanceColor.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.track_changes_rounded,
                                  size: 10,
                                  color: chanceColor,
                                ),
                                const SizedBox(width: 2.5),
                                Text(
                                  '$chanceScore% Chance',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    color: chanceColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),

                      // Aufklapp-Details: Aufschlüsselung in Aktivität & Biotop
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            // Faktor 1: Live-Aktivität
                            Expanded(
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 13,
                                    color: activityColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$activityScore% Akt.',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: activityColor,
                                          ),
                                        ),
                                        const Text(
                                          'Zeit & Wetter',
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w500,
                                            color: WildScoutTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              width: 1,
                              height: 20,
                              color: Colors.white12,
                            ),
                            // Faktor 2: Biotop-Eignung
                            Expanded(
                              child: Row(
                                children: [
                                  Icon(
                                    zone.type == HabitatZoneType.waterSuhle
                                        ? Icons.water_drop_rounded
                                        : Icons.park_rounded,
                                    size: 13,
                                    color: accentColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${zone.suitabilityScore.round()}% Biotop',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: accentColor,
                                          ),
                                        ),
                                        const Text(
                                          'Gelände-Güte',
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w500,
                                            color: WildScoutTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Kleiner Verbindungszeiger nach unten
              Positioned(
                top: 66,
                child: Container(
                  width: 2,
                  height: 10,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),

              // 3. Highlighted Pin (exakt zentriert auf der Koordinate)
              Positioned(
                top: 76,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: WildScoutTheme.bgObsidian,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 2.0),
                    boxShadow: [
                      BoxShadow(
                        color: chanceColor.withValues(alpha: 0.85),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                      const BoxShadow(
                        color: Colors.black87,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.track_changes_rounded,
                        size: 12,
                        color: chanceColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$chanceScore%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: chanceColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Standard-Zustand: Selbsterklärender Taktik-Marker mit kombiniertem Chance-Score
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedZoneInfo = zone);
      },
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: WildScoutTheme.bgObsidian.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: chanceColor, width: 1.8),
            boxShadow: [
              const BoxShadow(
                color: Colors.black87,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
              BoxShadow(
                color: chanceColor.withValues(alpha: 0.28),
                blurRadius: 7,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.track_changes_rounded,
                size: 13,
                color: chanceColor,
              ),
              const SizedBox(width: 3.5),
              Text(
                '$chanceScore%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: chanceColor,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                'Chance',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBestChanceHUDCard(String info) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: WildScoutTheme.bgObsidian.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: WildScoutTheme.amberGold.withValues(alpha: 0.75),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: WildScoutTheme.amberGold.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: WildScoutTheme.amberGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: WildScoutTheme.amberGold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BESTE CHANCE AKTIV',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: WildScoutTheme.amberGold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: WildScoutTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _bestChanceBannerInfo = null);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: WildScoutTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoneInfoCard(
    HabitatZone zone,
    TacticalAssessment zoneAssessment,
  ) {
    final accent = zone.type == HabitatZoneType.waterSuhle
        ? WildScoutTheme.cyanWater
        : _accentForSpeciesId(zone.speciesId);
    final activityScore = zoneAssessment.activityScorePercent;
    final activityColor = _colorForActivityScore(activityScore);
    final chanceScore =
        _calculateChanceScore(activityScore, zone.suitabilityScore);
    final chanceColor = _colorForChanceScore(chanceScore);
    final chanceRating = _ratingForChanceScore(chanceScore);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: WildScoutTheme.bgObsidian.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: chanceColor.withValues(alpha: 0.65), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Chance-Badge mit Tap zur Score-Erklärung
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showScoreExplanationSheet(
              zone: zone,
              zoneAssessment: zoneAssessment,
              chanceScore: chanceScore,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: chanceColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: chanceColor.withValues(alpha: 0.5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.track_changes_rounded,
                        size: 13,
                        color: chanceColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$chanceScore%',
                        style: TextStyle(
                          color: chanceColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Chance',
                    style: TextStyle(
                      color: chanceColor.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w800,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        zone.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      chanceRating,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: chanceColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _buildMicroFactorBadge(
                      icon: Icons.bolt_rounded,
                      color: activityColor,
                      label: '$activityScore% Akt.',
                    ),
                    const SizedBox(width: 5),
                    _buildMicroFactorBadge(
                      icon: zone.type == HabitatZoneType.waterSuhle
                          ? Icons.water_drop_rounded
                          : Icons.park_rounded,
                      color: accent,
                      label: '${zone.suitabilityScore.round()}% Biotop',
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.help_outline_rounded,
              size: 19,
              color: WildScoutTheme.textMuted,
            ),
            tooltip: 'Score-Erklärung',
            onPressed: () => _showScoreExplanationSheet(
              zone: zone,
              zoneAssessment: zoneAssessment,
              chanceScore: chanceScore,
            ),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _selectedZoneInfo = null),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildMicroFactorBadge({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showScoreExplanationSheet({
    required HabitatZone zone,
    required TacticalAssessment zoneAssessment,
    required int chanceScore,
  }) {
    HapticFeedback.lightImpact();
    final accent = zone.type == HabitatZoneType.waterSuhle
        ? WildScoutTheme.cyanWater
        : _accentForSpeciesId(zone.speciesId);
    final activityScore = zoneAssessment.activityScorePercent;
    final activityColor = _colorForActivityScore(activityScore);
    final chanceColor = _colorForChanceScore(chanceScore);
    final chanceRating = _ratingForChanceScore(chanceScore);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: WildScoutTheme.bgObsidian.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header: Icon + Titel + Chance Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: chanceColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: chanceColor.withValues(alpha: 0.4)),
                    ),
                    child: Icon(
                      Icons.track_changes_rounded,
                      color: chanceColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Erfolgs-Chance: $chanceScore%',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: chanceColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          '$chanceRating • ${zone.title}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: WildScoutTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Colors.white70,
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Text(
                'WildScout kombiniert zwei voneinander unabhängige Faktoren zur Berechnung der Foto- & Beobachtungschance für ${zone.speciesName}:',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 14),

              // Faktor 1: Live-Wildaktivität (Zeit & Wetter)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: activityColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: activityColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.bolt_rounded,
                        color: activityColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '1. Live-Wildaktivität: $activityScore%',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: activityColor,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Wann?',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: activityColor.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Berechnet aus Dämmerungs- & Sonnenstand, Temperatur, Windverhältnissen, Luftdruck und Mondphase. Zeigt, wie aktiv das Wild zu dieser Stunde unterwegs ist.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.3,
                              color: WildScoutTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Faktor 2: Biotop-Eignung (Ort & Gelände)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        zone.type == HabitatZoneType.waterSuhle
                            ? Icons.water_drop_rounded
                            : Icons.park_rounded,
                        color: accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '2. Biotop-Güte: ${zone.suitabilityScore.round()}%',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: accent,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Wo?',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: accent.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Bewertet das Gelände (${zone.subtitle}): Deckungsdichte, Nahrungsangebot (Äsung/Mast), Ruhe-Einstand und sicherer Pufferabstand zu Wander- & Radwegen.',
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.3,
                              color: WildScoutTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Formel-Zusammenfassung
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: chanceColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: chanceColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: chanceColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Formel: ($activityScore% Aktivität + ${zone.suitabilityScore.round()}% Biotop) ÷ 2 = $chanceScore% Chance',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: chanceColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getWeatherIcon(WeatherFrame weather, SunMoonPosition astro) {
    if (weather.precipitationMm > 0.1) return Icons.water_drop_rounded;
    if (weather.cloudCoverPercent >= 75) return Icons.cloud_rounded;
    if (weather.cloudCoverPercent >= 25) {
      return astro.currentPeriod == ActivityPeriod.night
          ? Icons.nightlight_outlined
          : Icons.cloud_queue_rounded;
    }
    if (astro.currentPeriod == ActivityPeriod.night) {
      return Icons.nightlight_round;
    }
    return Icons.wb_sunny_rounded;
  }

  Color _getWeatherIconColor(WeatherFrame weather, SunMoonPosition astro) {
    if (weather.precipitationMm > 0.1) return WildScoutTheme.cyanWater;
    if (weather.cloudCoverPercent >= 75) return WildScoutTheme.textMuted;
    if (astro.currentPeriod == ActivityPeriod.night) {
      return const Color(0xFFC7D2FE);
    }
    return WildScoutTheme.amberGold;
  }

  (IconData icon, Color color, String val, String detail) _getBarometerTelemetry(
    WeatherFrame weather,
  ) {
    final delta = weather.pressureDelta6hHpa;
    final valStr = '${weather.surfacePressureHpa.round()} hPa';
    if (delta <= -2.0) {
      return (
        Icons.trending_down_rounded,
        WildScoutTheme.amberGold,
        valStr,
        '⚡ Fällt (${delta.toStringAsFixed(1)}) • Fress-Schub',
      );
    } else if (delta <= -0.7) {
      return (
        Icons.trending_down_rounded,
        WildScoutTheme.amberGold,
        valStr,
        'Fällt (${delta.toStringAsFixed(1)}) • Mehr Aktivität',
      );
    } else if (delta >= 1.5) {
      return (
        Icons.trending_up_rounded,
        WildScoutTheme.cyanWater,
        valStr,
        'Steigt (+${delta.toStringAsFixed(1)}) • Ruhiges Wild',
      );
    } else {
      return (
        Icons.trending_flat_rounded,
        WildScoutTheme.textMuted,
        valStr,
        'Stabil • Gewohnter Rhythmus',
      );
    }
  }

  (IconData icon, Color color, String val, String detail) _getAstroTelemetry(
    SunMoonPosition astro,
    WeatherFrame weather,
  ) {
    final isMorning = weather.time.hour < 12;

    // Berechnung der optischen Wahrscheinlichkeit für Abendrot / Morgenrot (Rayleigh-Streuung an Wolkenuntergrenzen):
    // 1. Sonnenhöhe: Peak bei -1° bis +2° (Maximum bei 0.5°), fällt zu den Rändern (-4° und +5°) ab.
    // 2. Bewölkung: Ideal sind 30% bis 60% lockere Bewölkung (Faktor 1.0). Bei 0% kein Wolkenschirm, bei >80% Grauschleier.
    // 3. Niederschlag: Regen/starke Trübung reduziert die Sichtbarkeit drastisch.
    int calculateAlpenglowProbability() {
      if (astro.sunElevationDegrees < -4.0 || astro.sunElevationDegrees > 5.0) {
        return 0;
      }
      if (weather.precipitationMm > 0.2 || weather.isFog) {
        return 0;
      }

      // Sonnenhöhen-Faktor (0.0 bis 1.0)
      final elevDist = (astro.sunElevationDegrees - 0.5).abs();
      final elevFactor = (1.0 - (elevDist / 4.5)).clamp(0.0, 1.0);

      // Wolken-Faktor (Ideal: ca. 45% Bewölkung)
      final cloud = weather.cloudCoverPercent;
      double cloudFactor = 0.0;
      if (cloud >= 10 && cloud <= 80) {
        if (cloud >= 30 && cloud <= 60) {
          cloudFactor = 1.0;
        } else if (cloud < 30) {
          cloudFactor = (cloud - 10) / 20.0;
        } else {
          cloudFactor = 1.0 - ((cloud - 60) / 20.0);
        }
      }

      final prob = (elevFactor * cloudFactor * 100.0).round();
      return prob.clamp(0, 95);
    }

    final alpenglowProb = calculateAlpenglowProbability();

    if (alpenglowProb >= 25) {
      return (
        Icons.wb_twilight_rounded,
        const Color(0xFFFF6B6B), // Sanftes Korallrot / Morgenrot / Abendrot
        isMorning ? 'Morgenrot ($alpenglowProb%)' : 'Abendrot ($alpenglowProb%)',
        isMorning
            ? 'Ost • ${astro.sunElevationDegrees.toStringAsFixed(0)}° Horizont'
            : 'West • ${astro.sunElevationDegrees.toStringAsFixed(0)}° Horizont',
      );
    } else if (astro.isGoldenHour) {
      return (
        Icons.wb_twilight_rounded,
        WildScoutTheme.amberGold,
        isMorning ? 'Morgen-Gold' : 'Abend-Gold',
        '${astro.sunElevationDegrees.toStringAsFixed(0)}° Streiflicht',
      );
    } else if (astro.isBlueHour) {
      return (
        Icons.wb_twilight_rounded,
        WildScoutTheme.cyanWater,
        'Blaue Std.',
        isMorning ? 'Frühdämmerung' : 'Spätdämmerung',
      );
    } else if (astro.currentPeriod == ActivityPeriod.night) {
      final moonPct = (astro.moonIlluminationFraction * 100).round();
      return (
        Icons.nightlight_round,
        const Color(0xFFC7D2FE),
        '$moonPct% Mond',
        astro.moonPhaseName,
      );
    } else if (astro.sunElevationDegrees > 25) {
      return (
        Icons.wb_sunny_rounded,
        WildScoutTheme.amberGold,
        'Sonne',
        '${astro.sunElevationDegrees.round()}°',
      );
    } else {
      return (
        Icons.wb_sunny_outlined,
        WildScoutTheme.textMuted,
        'Weiches Licht',
        '${astro.sunElevationDegrees.round()}°',
      );
    }
  }

  (IconData icon, Color color, String val, String detail) _getSkyTelemetry(
    WeatherFrame weather,
    SunMoonPosition astro,
  ) {
    if (weather.precipitationMm > 0.1) {
      return (
        Icons.water_drop_rounded,
        WildScoutTheme.cyanWater,
        '${weather.precipitationMm.toStringAsFixed(1)} mm',
        'Regen',
      );
    } else if (weather.isFog) {
      return (
        Icons.cloud_queue_rounded,
        const Color(0xFFCBD5E1),
        'Nebel',
        'Sicht < 1 km',
      );
    } else if (weather.cloudCoverPercent >= 75) {
      return (
        Icons.cloud_rounded,
        WildScoutTheme.textMuted,
        '${weather.cloudCoverPercent}%',
        'Bedeckt',
      );
    } else if (weather.cloudCoverPercent >= 25) {
      return (
        Icons.cloud_queue_rounded,
        const Color(0xFFBAE6FD),
        '${weather.cloudCoverPercent}%',
        'Leicht bewölkt',
      );
    } else {
      return (
        astro.currentPeriod == ActivityPeriod.night
            ? Icons.nightlight_round
            : Icons.wb_sunny_rounded,
        astro.currentPeriod == ActivityPeriod.night
            ? const Color(0xFFC7D2FE)
            : WildScoutTheme.amberGold,
        'Klar',
        '${weather.cloudCoverPercent}% Wolken',
      );
    }
  }

  (IconData icon, Color color, String val, String detail) _getWindTelemetry(
    WeatherFrame weather,
  ) {
    final spd = weather.windSpeedKmh.round();
    final card = weather.windCardinalLabel;
    final valStr = '$spd km/h $card';
    if (weather.windSpeedKmh < 4.0) {
      return (
        Icons.air_rounded,
        WildScoutTheme.amberGold,
        valStr,
        'Thermik-Risiko',
      );
    } else if (weather.windSpeedKmh > 25.0) {
      return (
        Icons.air_rounded,
        WildScoutTheme.crimsonScent,
        valStr,
        'Böig',
      );
    } else {
      return (
        Icons.air_rounded,
        WildScoutTheme.emeraldBio,
        valStr,
        'Stetig',
      );
    }
  }

  Widget _buildSevereWeatherHUDBanner(SevereWeatherAlert alert) {
    final isDanger = alert.isDanger;
    final color = alert.accentColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.mediumImpact();
          SevereWeatherAlertSheet.show(
            context,
            alert: alert,
            onEndSession: () {
              setState(() => _isSessionActive = false);
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.8),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(alert.icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          isDanger
                              ? '⚠️ AKUTE GEFAHR (FOTOSPOT)'
                              : '⚠️ UNWETTER-WARNUNG',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: color,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• ${alert.timeLabel}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeckSevereWeatherCard(SevereWeatherAlert alert) {
    final isDanger = alert.isDanger;
    final color = alert.accentColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.mediumImpact();
          SevereWeatherAlertSheet.show(
            context,
            alert: alert,
            onEndSession: () {
              setState(() => _isSessionActive = false);
            },
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.65),
              width: 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(alert.icon, size: 17, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isDanger
                              ? 'AKUTER UNWETTER-ALARM'
                              : 'UNWETTER-WARNUNG AM FOTOSPOT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: color,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          alert.timeLabel,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: WildScoutTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${alert.headline} • ${alert.safetyRecommendation}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: WildScoutTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherTelemetryPill(
    WeatherFrame weather,
    SunMoonPosition astro,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.lightImpact();
          _openWindCompassSheet();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WildScoutTheme.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getWeatherIcon(weather, astro),
                size: 14,
                color: _getWeatherIconColor(weather, astro),
              ),
              const SizedBox(width: 4),
              Text(
                '${weather.temperatureCelsius.toStringAsFixed(0)}°C',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: WildScoutTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 1,
                height: 11,
                color: WildScoutTheme.borderSubtle,
              ),
              const SizedBox(width: 6),
              Transform.rotate(
                angle: weather.scentBlowDirectionDegrees * (math.pi / 180.0),
                child: const Icon(
                  Icons.navigation_rounded,
                  size: 11,
                  color: WildScoutTheme.emeraldBio,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                weather.windCardinalLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: WildScoutTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomTacticalDeck({
    required SpeciesProfile species,
    required WeatherFrame weather,
    required SunMoonPosition astro,
    required TacticalAssessment assessment,
    SevereWeatherAlert? severeWeatherAlert,
  }) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final dayLabel = _dayLabelForOffset(_selectedDayOffset);
    final hourStr =
        '${_selectedHourOfDay.toString().padLeft(2, '0')}:00 Uhr';
    final now = DateTime.now();
    final nowFraction = _selectedDayOffset == 0 ? now.hour.toDouble() : null;

    final scoreColor =
        _colorForActivityScore(assessment.activityScorePercent);

    final baroInfo = _getBarometerTelemetry(weather);
    final astroInfo = _getAstroTelemetry(astro, weather);
    final skyInfo = _getSkyTelemetry(weather, astro);
    final windInfo = _getWindTelemetry(weather);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: WildScoutTheme.glassDecoration(
            borderRadius: 24,
            borderColor: assessment.hasScentCollision
                ? WildScoutTheme.crimsonScent.withValues(alpha: 0.85)
                : WildScoutTheme.borderSubtle,
            borderWidth: assessment.hasScentCollision ? 1.8 : 1.0,
            shadows: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Drag Handle + Interaktiver Header (Score + Datum/Zeit + Aufklapp-Button)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _isDeckExpanded = !_isDeckExpanded);
                },
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Tier 1: Activity Score Pill + Detail-Aufklapp-Button (Wetter/Telemetrie)
                    Row(
                      children: [
                        // Activity Score Pill mit Farbindikator (Tieraktivität)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: scoreColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: scoreColor.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: scoreColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${assessment.activityScorePercent}%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: scoreColor,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    assessment.ratingLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: scoreColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Aufklapp-Button für erweiterte Wetter- & Umgebungs-Telemetrie
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: WildScoutTheme.borderSubtle,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isDeckExpanded ? 'Weniger' : 'Wetter & Details',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: WildScoutTheme.textMuted,
                                ),
                              ),
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: _isDeckExpanded ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 250),
                                child: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: WildScoutTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Unwetter-Alarm Card im Deck (bei aktiver Fotosession und Sturm/Gewitter)
              if (_isSessionActive && severeWeatherAlert != null) ...[
                _buildDeckSevereWeatherCard(severeWeatherAlert),
                const SizedBox(height: 8),
              ],

              // Tier 2: Vollbreiter Taktischer Witterungs- & Wind-Hinweis (Tippen öffnet den 360° Kompass)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _openWindCompassSheet();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: assessment.hasScentCollision
                          ? WildScoutTheme.crimsonScent.withValues(alpha: 0.18)
                          : WildScoutTheme.emeraldBio.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: assessment.hasScentCollision
                            ? WildScoutTheme.crimsonScent.withValues(alpha: 0.6)
                            : WildScoutTheme.emeraldBio.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1.5),
                          child: Icon(
                            assessment.hasScentCollision
                                ? Icons.warning_amber_rounded
                                : (weather.windSpeedKmh < 4.0
                                    ? Icons.air_rounded
                                    : Icons.check_circle_outline),
                            size: 16,
                            color: assessment.hasScentCollision
                                ? WildScoutTheme.crimsonScent
                                : WildScoutTheme.emeraldBio,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            assessment.windTacticalAdvice,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                              color: assessment.hasScentCollision
                                  ? const Color(0xFFFFB4C0)
                                  : WildScoutTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.explore_rounded,
                            size: 15,
                            color: assessment.hasScentCollision
                                ? WildScoutTheme.crimsonScent.withValues(alpha: 0.8)
                                : WildScoutTheme.emeraldBio.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Tier 3: Zeitschieberegler (Time-Scrubber: Ergonomisch optimiert für Touchscreen)
              if (isMobile) ...[
                // Zeile 1: Schnellauswahl-Tasten & Wetter-Telemetrie-Pill
                Row(
                  children: [
                    _QuickTimeButton(
                      icon: Icons.wb_twilight_rounded,
                      label: '06:00',
                      isSelected: _selectedHourOfDay == 6,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedHourOfDay = 6);
                      },
                    ),
                    if (_selectedDayOffset == 0) ...[
                      const SizedBox(width: 5),
                      _QuickTimeButton(
                        icon: Icons.schedule_rounded,
                        label: 'Jetzt',
                        isSelected: _selectedHourOfDay == DateTime.now().hour,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedHourOfDay = DateTime.now().hour);
                        },
                      ),
                    ],
                    const SizedBox(width: 5),
                    _QuickTimeButton(
                      icon: Icons.nightlight_round,
                      label: '18:00',
                      isSelected: _selectedHourOfDay == 18,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedHourOfDay = 18);
                      },
                    ),
                    const Spacer(),
                    _buildWeatherTelemetryPill(weather, astro),
                  ],
                ),
                const SizedBox(height: 4),

                // Zeile 2: Skalen-Header & Zeitanzeige
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '00:00 Morgenfrühe',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: WildScoutTheme.textMuted,
                        ),
                      ),
                      Text(
                        '23:00 Nacht',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: WildScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                // Zeile 3: Volle Breite Zeitschieberegler mit astronomischem Lichtphasen-Verlauf & Live-Markierung
                SizedBox(
                  width: double.infinity,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackShape: TacticalSliderTrackShape(
                        nowFraction: nowFraction,
                        referenceDate: weather.time,
                        latitude: _hidePinPosition.latitude,
                        longitude: _hidePinPosition.longitude,
                      ),
                    ),
                    child: Slider(
                      value: _selectedHourOfDay.toDouble(),
                      min: 0,
                      max: 23,
                      divisions: 23,
                      label: '$dayLabel, $hourStr',
                      onChanged: (val) {
                        final newHour = val.round();
                        if (newHour != _selectedHourOfDay) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedHourOfDay = newHour;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ] else ...[
                // Desktop / Tablet: Einzeiliges Horizontallayout
                Row(
                  children: [
                    _QuickTimeButton(
                      icon: Icons.wb_twilight_rounded,
                      label: '06:00',
                      isSelected: _selectedHourOfDay == 6,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedHourOfDay = 6);
                      },
                    ),
                    if (_selectedDayOffset == 0) ...[
                      const SizedBox(width: 6),
                      _QuickTimeButton(
                        icon: Icons.schedule_rounded,
                        label: 'Jetzt',
                        isSelected: _selectedHourOfDay == DateTime.now().hour,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedHourOfDay = DateTime.now().hour);
                        },
                      ),
                    ],
                    const SizedBox(width: 6),
                    _QuickTimeButton(
                      icon: Icons.nightlight_round,
                      label: '18:00',
                      isSelected: _selectedHourOfDay == 18,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedHourOfDay = 18);
                      },
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackShape: TacticalSliderTrackShape(
                            nowFraction: nowFraction,
                            referenceDate: weather.time,
                            latitude: _hidePinPosition.latitude,
                            longitude: _hidePinPosition.longitude,
                          ),
                        ),
                        child: Slider(
                          value: _selectedHourOfDay.toDouble(),
                          min: 0,
                          max: 23,
                          divisions: 23,
                          label: '$dayLabel, $hourStr',
                          onChanged: (val) {
                            final newHour = val.round();
                            if (newHour != _selectedHourOfDay) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedHourOfDay = newHour;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    _buildWeatherTelemetryPill(weather, astro),
                  ],
                ),
              ],

              // Tier 4: Aufklappbarer Detailbereich: 7-Tage-Vorplanung & Sensor-Telemetrie
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                child: _isDeckExpanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          // 7-Tage Vorplanungs-Leiste
                          SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: 7,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (context, dayIdx) {
                                final isSelected = dayIdx == _selectedDayOffset;
                                final forecastIdx = (dayIdx * 24 + 12).clamp(
                                  0,
                                  _hourlyForecast.isEmpty
                                      ? 0
                                      : _hourlyForecast.length - 1,
                                );
                                final dayWeather = _hourlyForecast.isNotEmpty
                                    ? _hourlyForecast[forecastIdx]
                                    : null;

                                IconData? dayIcon;
                                Color? dayIconColor;
                                if (dayWeather != null) {
                                  if (dayWeather.precipitationMm > 0.1) {
                                    dayIcon = Icons.water_drop_rounded;
                                    dayIconColor = WildScoutTheme.cyanWater;
                                  } else if (dayWeather.cloudCoverPercent >= 75) {
                                    dayIcon = Icons.cloud_rounded;
                                    dayIconColor = WildScoutTheme.textMuted;
                                  } else if (dayWeather.cloudCoverPercent >= 25) {
                                    dayIcon = Icons.cloud_queue_rounded;
                                    dayIconColor = const Color(0xFFBAE6FD);
                                  } else {
                                    dayIcon = Icons.wb_sunny_rounded;
                                    dayIconColor = WildScoutTheme.amberGold;
                                  }
                                }

                                return InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _selectedDayOffset = dayIdx);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? WildScoutTheme.emeraldBio
                                              .withValues(alpha: 0.22)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? WildScoutTheme.emeraldBio
                                            : WildScoutTheme.borderSubtle,
                                        width: isSelected ? 1.4 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _dayLabelForOffset(dayIdx),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: isSelected
                                                ? WildScoutTheme.emeraldBio
                                                : WildScoutTheme.textPrimary,
                                          ),
                                        ),
                                        if (dayWeather != null &&
                                            dayIcon != null) ...[
                                          const SizedBox(width: 5),
                                          Icon(
                                            dayIcon,
                                            size: 13,
                                            color: isSelected
                                                ? WildScoutTheme.emeraldBio
                                                : dayIconColor,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${dayWeather.temperatureCelsius.round()}°',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isSelected
                                                  ? WildScoutTheme.emeraldBio
                                                  : WildScoutTheme.textMuted,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Modular 2x2 Telemetrie Cards (Strukturiertes Apple HIG Grid)
                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _ModularTelemetryCard(
                                      category: 'Luftdruck',
                                      icon: baroInfo.$1,
                                      iconColor: baroInfo.$2,
                                      value: baroInfo.$3,
                                      detail: baroInfo.$4,
                                      detailColor: baroInfo.$2,
                                      tooltipMessage:
                                          assessment.barometerInsight,
                                      onTap: () {
                                        _showTelemetryExplainerSheet(
                                          title: 'Luftdruck & Wildaktivität',
                                          subtitle: '${weather.surfacePressureHpa.round()} hPa • Trend: ${weather.pressureDelta6hHpa >= 0 ? "+" : ""}${weather.pressureDelta6hHpa.toStringAsFixed(1)} hPa in 6h',
                                          icon: Icons.compress_rounded,
                                          iconColor: WildScoutTheme.amberGold,
                                          points: [
                                            (
                                              heading: 'Fress-Trigger bei Druckabfall',
                                              description: 'Fällt der Luftdruck vor einer Schlechtwetterfront rasch ab (Delta < -1.5 hPa), treten Rehe und Hirsche oft 1–2 Stunden früher auf Lichtungen aus, um vor dem Regen zu äsen.',
                                              icon: Icons.trending_down_rounded,
                                            ),
                                            (
                                              heading: 'Ruhiges Verhalten im Hochdruck',
                                              description: 'Bei beständigem Hochdruck (>1015 hPa) fühlt sich das Wild sicher, bleibt länger in der Deckung und zieht meist erst in der späten Dämmerung heraus.',
                                              icon: Icons.sunny,
                                            ),
                                            (
                                              heading: 'Optik & Frühnebel-Chancen',
                                              description: 'Klare Hochdrucknächte kühlen stark aus und erzeugen idealen Bodennebel in Tälern für atmosphärische Gegenlichtaufnahmen.',
                                              icon: Icons.foggy,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _ModularTelemetryCard(
                                      category: 'Licht',
                                      icon: astroInfo.$1,
                                      iconColor: astroInfo.$2,
                                      value: astroInfo.$3,
                                      detail: astroInfo.$4,
                                      tooltipMessage:
                                          assessment.lightQualityAdvice,
                                      onTap: () {
                                        _showTelemetryExplainerSheet(
                                          title: 'Licht & Solunar-Phase',
                                          subtitle: '${astro.sunElevationDegrees.toStringAsFixed(1)}° Sonnenhöhe • ${astro.lightPhaseLabel}',
                                          icon: astroInfo.$1,
                                          iconColor: astroInfo.$2,
                                          points: [
                                            (
                                              heading: 'Morgenrot / Abendrot',
                                              description: 'Flaches Streulicht an Wolkenunterkanten (-4° bis +5° Elevation). Perfekt für farbintensive Silhouetten und weiche Reflexe.',
                                              icon: Icons.wb_twilight_rounded,
                                            ),
                                            (
                                              heading: 'Goldene & Blaue Stunde',
                                              description: 'Klassisches warmes Streiflicht oder kühles Dämmerungslicht mit minimierten Schlagschatten für plastische Fellstrukturen.',
                                              icon: Icons.auto_awesome_rounded,
                                            ),
                                            (
                                              heading: 'Mondphase: ${astro.moonPhaseName}',
                                              description: '${(astro.moonIlluminationFraction * 100).round()}% Illumination. Nach dunklen Neumondnächten zieht Wild morgens besonders hungrig und länger im Hellen heraus.',
                                              icon: Icons.nightlight_round,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _ModularTelemetryCard(
                                      category: 'Himmel',
                                      icon: skyInfo.$1,
                                      iconColor: skyInfo.$2,
                                      value: skyInfo.$3,
                                      detail: skyInfo.$4,
                                      tooltipMessage: weather.precipitationMm > 0
                                          ? '${weather.precipitationMm.toStringAsFixed(1)} mm Niederschlag'
                                          : '${weather.cloudCoverPercent}% Wolkenbedeckung',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _ModularTelemetryCard(
                                      category: 'Wind',
                                      icon: windInfo.$1,
                                      iconColor: windInfo.$2,
                                      value: windInfo.$3,
                                      detail: '${windInfo.$4} • Kompass 360°',
                                      detailColor: windInfo.$2,
                                      tooltipMessage:
                                          '${assessment.windTacticalAdvice} (Tippen für 360° Witterungs-Kompass)',
                                      onTap: _openWindCompassSheet,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModularTelemetryCard extends StatelessWidget {
  final String category;
  final IconData icon;
  final Color iconColor;
  final String value;
  final String detail;
  final Color? detailColor;
  final String? tooltipMessage;
  final VoidCallback? onTap;

  const _ModularTelemetryCard({
    required this.category,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.detail,
    this.detailColor,
    this.tooltipMessage,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: detailColor != null && detailColor != WildScoutTheme.textMuted
              ? detailColor!.withValues(alpha: 0.35)
              : WildScoutTheme.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 5),
              Text(
                category.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: WildScoutTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: WildScoutTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            detail,
            maxLines: 2,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: detailColor ?? WildScoutTheme.textMuted,
              height: 1.25,
            ),
          ),
        ],
      ),
    );

    Widget content = card;
    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap!();
          },
          child: card,
        ),
      );
    }

    if (tooltipMessage != null && tooltipMessage!.isNotEmpty) {
      return Tooltip(
        message: tooltipMessage!,
        child: content,
      );
    }
    return content;
  }
}

/// Maßgeschneiderte Taktik-Slider-Spur (Apple HIG konform), die im Hintergrund
/// einen nahtlosen Farbverlauf für Nacht, Blaue Stunde, Goldene Stunde und Tageslicht
/// (berechnet über den offline Sonnenstands-Rechner) darstellt und bei 'Heute'
/// eine dezente vertikale Linie samt Pfeil & "JETZT"-Markierung für die
/// minutengenaue Echtzeit einzeichnet.
class TacticalSliderTrackShape extends RoundedRectSliderTrackShape {
  final double? nowFraction;
  final DateTime? referenceDate;
  final double? latitude;
  final double? longitude;

  const TacticalSliderTrackShape({
    this.nowFraction,
    this.referenceDate,
    this.latitude,
    this.longitude,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    // Falls das Slider-Theme 0-Höhe hat, frühzeitig abbrechen
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final trackLeft = trackRect.left;
    final trackWidth = trackRect.width;
    final canvas = context.canvas;
    final trackRRect = RRect.fromRectAndRadius(
      trackRect,
      Radius.circular(trackRect.height / 2),
    );

    // 1. Hintergrund-Track mit astronomischem Lichtphasen-Farbverlauf
    // (Nacht -> Blaue Stunde -> Goldene Stunde -> Tag -> Goldene Stunde -> Blaue Stunde -> Nacht)
    final gradientColors = <Color>[];
    final gradientStops = <double>[];

    final ref = referenceDate ?? DateTime.now();
    final lat = latitude ?? 51.1657;
    final lon = longitude ?? 10.4515;

    // Wir tasten den 24h-Tag ab und weisen jedem Zeitfenster die passende
    // Farbatmosphäre zu:
    // • Nacht: Tiefes Nacht-Anthrazit/Obsidian (#0D171F / #111A24)
    // • Blaue Stunde: Kühles Dämmerungs-Indigo/Saphirblau (#1E3A8A / #2563EB)
    // • Goldene Stunde: Warmes Bernstein-/Gold-Orange (#F59E0B / #D97706)
    // • Tageslicht: Sanftes, klares Licht-Smaragdgrün (#059669 / #10B981)
    const sampleCount = 24;
    for (int i = 0; i < sampleCount; i++) {
      final stop = i / (sampleCount - 1);
      final sampleTime = DateTime(ref.year, ref.month, ref.day, i, 30);
      final astroPos = SunMoonCalculator.calculate(
        dateTime: sampleTime,
        latitude: lat,
        longitude: lon,
      );

      Color color;
      if (astroPos.isGoldenHour) {
        color = const Color(0xFFF59E0B).withValues(alpha: 0.85); // Strahlendes Gold
      } else if (astroPos.isBlueHour) {
        color = const Color(0xFF2563EB).withValues(alpha: 0.85); // Intensives Blaue-Stunde-Blau
      } else if (astroPos.currentPeriod == ActivityPeriod.night) {
        color = const Color(0xFF0F172A).withValues(alpha: 0.70); // Tiefe Mitternachtsnacht
      } else {
        // Tag (volles Sonnenlicht)
        color = const Color(0xFF0D9488).withValues(alpha: 0.75); // Frisches Tages-Türkis/Smaragd
      }

      gradientColors.add(color);
      gradientStops.add(stop);
    }

    final gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: gradientColors,
        stops: gradientStops,
      ).createShader(trackRect);

    // Gestochen scharfer Clip auf den abgerundeten Track
    canvas.save();
    canvas.clipRRect(trackRRect);

    // Zeichne den Lichtphasen-Farbverlauf
    canvas.drawRRect(trackRRect, gradientPaint);

    // Dezentes dunkles Inset-Overlay auf der inaktiven rechten Seite
    final thumbX = thumbCenter.dx.clamp(trackLeft, trackRect.right);
    final inactiveWidth = trackRect.right - thumbX;
    if (inactiveWidth > 0) {
      final inactiveOverlayPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.55);
      canvas.drawRect(
        Rect.fromLTRB(thumbX, trackRect.top, trackRect.right, trackRect.bottom),
        inactiveOverlayPaint,
      );
    }

    // Feiner Licht-Glow-Streifen auf der aktiven linken Seite
    final activeWidth = thumbX - trackLeft;
    if (activeWidth > 0) {
      final activeOverlayPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.12);
      canvas.drawRect(
        Rect.fromLTRB(trackLeft, trackRect.top, thumbX, trackRect.bottom),
        activeOverlayPaint,
      );
    }

    canvas.restore();

    // 2. Subtiler Umrissrand (Apple HIG Outline) für perfekte Ablesbarkeit
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(trackRRect, borderPaint);

    // 3. Optional: JETZT-Indikator bei heutigem Datum
    if (nowFraction == null || nowFraction! < 0 || nowFraction! > 23) {
      return;
    }

    final padding = isRounded ? trackRect.height : 0.0;
    final visualPosition = (nowFraction! / 23.0).clamp(0.0, 1.0);
    final calculatedX = isDiscrete
        ? trackLeft + visualPosition * (trackWidth - padding) + padding / 2
        : trackLeft + visualPosition * trackWidth;

    // Wenn der Slider auf der Jetzt-Position steht, richten wir den Marker
    // exakt auf thumbCenter.dx aus, um Rundungsdifferenzen vollständig zu vermeiden.
    final nowX = (calculatedX - thumbCenter.dx).abs() < 1.0
        ? thumbCenter.dx
        : calculatedX;
    final trackCenterY = trackRect.center.dy;

    // 3.1 Sanfter Glow-Effekt für hohe Sichtbarkeit im Nacht- & Tarnmodus
    final glowPaint = Paint()
      ..color = WildScoutTheme.amberGold.withValues(alpha: 0.35)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(nowX, trackCenterY - 9),
      Offset(nowX, trackCenterY + 9),
      glowPaint,
    );

    // 3.2 Präzise vertikale Markierungslinie über den Schieberegler-Track
    final linePaint = Paint()
      ..color = WildScoutTheme.amberGold
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(nowX, trackCenterY - 8),
      Offset(nowX, trackCenterY + 8),
      linePaint,
    );

    // 3.3 Nach unten zeigender Markierungs-Pfeil (Indikator)
    final arrowPath = Path()
      ..moveTo(nowX, trackCenterY - 8)
      ..lineTo(nowX - 3.5, trackCenterY - 13)
      ..lineTo(nowX + 3.5, trackCenterY - 13)
      ..close();
    final arrowPaint = Paint()
      ..color = WildScoutTheme.amberGold
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, arrowPaint);

    // 3.4 Kompakter "JETZT"-Schriftzug über dem Pfeil
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'JETZT',
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: WildScoutTheme.amberGold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textX = (nowX - textPainter.width / 2).clamp(
      trackLeft,
      trackRect.right - textPainter.width,
    );
    textPainter.paint(canvas, Offset(textX, trackCenterY - 22));
  }
}

class _QuickTimeButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickTimeButton({
    this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? WildScoutTheme.emeraldBio.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? WildScoutTheme.emeraldBio
                : WildScoutTheme.borderSubtle,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: isSelected
                    ? WildScoutTheme.emeraldBio
                    : WildScoutTheme.textMuted,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: isSelected
                    ? WildScoutTheme.emeraldBio
                    : WildScoutTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable 46x46 Liquid Glass Button für die ergonomische Daumenzone (Apple HIG)
class _TacticalFloatingButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isLoading;
  final Color? iconColor;
  final Color? badgeColor;

  const _TacticalFloatingButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isLoading = false,
    this.iconColor,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 40,
                height: 40,
                decoration: WildScoutTheme.glassDecoration(
                  borderRadius: 13,
                  shadows: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: WildScoutTheme.emeraldBio,
                        ),
                      )
                    else
                      Icon(
                        icon,
                        size: 19,
                        color: iconColor ?? WildScoutTheme.textPrimary,
                      ),
                    if (badgeColor != null)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 6.5,
                          height: 6.5,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: badgeColor!.withValues(alpha: 0.65),
                                blurRadius: 3.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TacticalBestChanceButton extends StatelessWidget {
  final bool hasZones;
  final VoidCallback onTap;

  const _TacticalBestChanceButton({
    required this.hasZones,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Beste Chance: Wählt automatisch Top-Tag, Uhrzeit & Fotospot',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      WildScoutTheme.amberGold.withValues(alpha: 0.32),
                      WildScoutTheme.bgObsidian.withValues(alpha: 0.90),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: WildScoutTheme.amberGold.withValues(alpha: 0.75),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: WildScoutTheme.amberGold.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.auto_awesome,
                    color: WildScoutTheme.amberGold,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TacticalRadarSweep extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const _TacticalRadarSweep({
    required this.animation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(220, 220),
          painter: _RadarSweepPainter(
            progress: animation.value,
            color: color,
          ),
        );
      },
    );
  }
}

class _RadarSweepPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RadarSweepPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 1. Sanfter Hintergrund-Schimmer der Radarscheibe
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.14),
          color.withValues(alpha: 0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawCircle(center, maxRadius, bgPaint);

    // 2. Konzentrische taktische Distanzringe (38%, 68%, 100%)
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = color.withValues(alpha: 0.28);

    for (final factor in const [0.38, 0.68, 1.0]) {
      canvas.drawCircle(center, maxRadius * factor, ringPaint);
    }

    // 3. Pulsierende Sonar-Welle von innen nach außen
    final pulseRadius = maxRadius * (0.18 + 0.82 * progress);
    final pulseAlpha = (1.0 - progress).clamp(0.0, 1.0) * 0.55;
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = color.withValues(alpha: pulseAlpha);
    canvas.drawCircle(center, pulseRadius, pulsePaint);

    // 4. Dezentes Fadenkreuz (N / O / S / W)
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = color.withValues(alpha: 0.20);
    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius),
      Offset(center.dx, center.dy + maxRadius),
      crossPaint,
    );

    // 5. Rotierender Radar-Kegel (SweepGradient) + heller Leitstrahl
    final sweepAngle = progress * 2 * math.pi;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(sweepAngle);

    final rect = Rect.fromCircle(center: Offset.zero, radius: maxRadius);
    final sweepPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: 2 * math.pi,
        colors: [
          Colors.transparent,
          Colors.transparent,
          color.withValues(alpha: 0.04),
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.46),
        ],
        stops: const [0.0, 0.62, 0.75, 0.90, 1.0],
      ).createShader(rect);

    canvas.drawCircle(Offset.zero, maxRadius, sweepPaint);

    // Hell leuchtende Radar-Nadel an der Vorderkante (Winkel = 0 / 2*pi)
    final beamGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5)
      ..color = color.withValues(alpha: 0.65);
    canvas.drawLine(Offset.zero, Offset(maxRadius, 0), beamGlowPaint);

    final beamCorePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFA7F3D0);
    canvas.drawLine(Offset.zero, Offset(maxRadius, 0), beamCorePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
