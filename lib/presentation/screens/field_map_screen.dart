import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../core/privacy/coordinate_guard.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../data/api/location_search_client.dart';
import '../../data/api/open_meteo_client.dart';
import '../../data/repositories/species_repository.dart';
import '../../data/repositories/spot_vault_repository.dart';
import '../../data/services/app_settings_service.dart';
import '../../data/services/compass_heading_service.dart';
import '../../data/services/device_location_service.dart';
import '../../data/services/photo_gear_service.dart';
import '../../data/services/rain_radar_service.dart';
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
import '../../domain/services/wildlife_tactical_engine.dart';
import '../widgets/app_settings_sheet.dart';
import '../widgets/device_heading_beam.dart';
import '../widgets/hud_compass_tape.dart';
import '../widgets/location_search_sheet.dart';
import '../widgets/map_layers_sheet.dart';
import '../widgets/photo_gear_sheet.dart';
import '../widgets/severe_weather_alert_sheet.dart';
import '../widgets/species_inspector_sheet.dart';
import '../widgets/species_multiselect_sheet.dart';
import '../widgets/species_photo_avatar.dart';
import '../widgets/spot_vault_sheet.dart';
import '../widgets/field_overlay_builder.dart';
import '../widgets/tactical_windy_weather_sheet.dart';
import '../widgets/wind_scent_compass_sheet.dart';

enum _ThumbCluster {
  none,
  navigation,
  tools,
}

class FieldMapScreen extends StatefulWidget {
  const FieldMapScreen({super.key});

  @override
  State<FieldMapScreen> createState() => _FieldMapScreenState();
}

class _FieldMapScreenState extends State<FieldMapScreen>
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
  String? _bestChanceZoneId;

  // UI Toggles (hinter dem Karten-Elemente-Button gebündelt)
  bool _isNightVisionRedMode = false;
  bool _useSatelliteLayer = true;
  bool _showPlaceNames = true;
  bool _showRainRadarLayer = false;
  String? _rainRadarUrlTemplate;
  bool _showHabitatLayer = true;
  bool _showDisturbanceLayer = AppSettings.defaultShowDisturbanceLayer;
  bool _showScentCone = true;
  bool _isLoadingOsm = false;
  bool _isDeckExpanded = false;
  _ThumbCluster _activeThumbCluster = _ThumbCluster.none;
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
    AppSettingsService.settingsNotifier.addListener(_onAppSettingsChanged);
    _initializeAppData();
  }

  @override
  void dispose() {
    AppSettingsService.settingsNotifier.removeListener(_onAppSettingsChanged);
    PhotoGearService.gearNotifier.removeListener(_onPhotoGearChanged);
    _radarController.dispose();
    _headingSubscription?.cancel();
    super.dispose();
  }

  void _onAppSettingsChanged() {
    if (!mounted) return;
    final settings = AppSettingsService.settingsNotifier.value;
    setState(() {
      _appSettings = settings;
      _showPlaceNames = settings.showPlaceNamesOnSatellite;
      _showRainRadarLayer = settings.showRainRadarLayer;
      _showScentCone = settings.showWindScentCone;
      _showDisturbanceLayer = settings.showDisturbanceLayer;
    });
    if (settings.showRainRadarLayer && _rainRadarUrlTemplate == null) {
      _refreshRainRadarTemplate();
    }
  }

  Future<void> _refreshRainRadarTemplate() async {
    final template = await RainRadarService.fetchLatestRadarUrlTemplate();
    if (mounted && template != null) {
      setState(() => _rainRadarUrlTemplate = template);
    }
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
      _showDisturbanceLayer = settings.showDisturbanceLayer;
      if (settings.showRainRadarLayer) {
        _refreshRainRadarTemplate();
      }
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
      _bestChanceBannerInfo = null;
      _bestChanceZoneId = null;
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
      _bestChanceBannerInfo = null;
      _bestChanceZoneId = null;
      _activeThumbCluster = _ThumbCluster.none;
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
            showRainRadarLayer: _showRainRadarLayer,
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
              AppSettingsService.setShowDisturbanceLayer(val);
            },
            onChangedRainRadar: (val) {
              setState(() => _showRainRadarLayer = val);
              setSheetState(() {});
              AppSettingsService.setShowRainRadarLayer(val);
              if (val && _rainRadarUrlTemplate == null) {
                _refreshRainRadarTemplate();
              }
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
            onOpenTacticalWindy: () => _openTacticalWindySheet(
              initialMode: WindyOverlayMode.clouds,
            ),
          );
        },
      ),
    );
  }

  void _openTacticalWindySheet({
    WindyOverlayMode initialMode = WindyOverlayMode.clouds,
  }) {
    final currentWeather = _hourlyForecast.isNotEmpty
        ? _hourlyForecast[_activeForecastIndex]
        : OpenMeteoClient.buildOfflineFallbackForecast()[0];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TacticalWindyWeatherSheet(
        coordinate: _hidePinPosition,
        currentWeather: currentWeather,
        initialMode: initialMode,
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
          color: WildlifeScoutTheme.surfaceGlass,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: WildlifeScoutTheme.borderSubtle),
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
                          color: WildlifeScoutTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WildlifeScoutTheme.textMuted,
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
                              color: WildlifeScoutTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.description,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: WildlifeScoutTheme.textMuted,
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
        backgroundColor: WildlifeScoutTheme.surfaceCard,
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
    return WildlifeScoutTheme.emeraldBio;
  }

  SpeciesProfile? _speciesForId(String id) {
    for (final sp in _speciesList) {
      if (sp.id == id) return sp;
    }
    return _primarySpecies;
  }

  Color _colorForActivityScore(int score) {
    if (score >= 78) return WildlifeScoutTheme.emeraldBio;
    if (score >= 55) return WildlifeScoutTheme.amberGold;
    return WildlifeScoutTheme.textMuted;
  }

  Color _colorForChanceScore(int score) {
    if (score >= 70) return WildlifeScoutTheme.emeraldBio;
    if (score >= 45) return WildlifeScoutTheme.amberGold;
    return WildlifeScoutTheme.textMuted;
  }

  String _ratingForChanceScore(int score) {
    if (score >= 80) return 'Exzellent';
    if (score >= 68) return 'Sehr gut';
    if (score >= 50) return 'Gut';
    if (score >= 35) return 'Mäßig';
    return 'Gering';
  }

  FieldAssessment _assessmentForZone({
    required HabitatZone zone,
    required WeatherFrame weather,
    required SunMoonPosition astro,
    required FieldAssessment primaryAssessment,
    required Map<String, FieldAssessment> cachedAssessments,
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

  ZoneTacticalAssessment _tacticalAssessmentForZone({
    required HabitatZone zone,
    required FieldAssessment zoneAssessment,
    WeatherFrame? weather,
    SunMoonPosition? astro,
  }) {
    final activeWeather = weather ?? _hourlyForecast[_activeForecastIndex];
    final activeAstro = astro ??
        SunMoonCalculator.calculate(
          dateTime: activeWeather.time,
          latitude: _hidePinPosition.latitude,
          longitude: _hidePinPosition.longitude,
        );
    final match = _speciesList.where((s) => s.id == zone.speciesId);
    final species = match.isNotEmpty ? match.first : _primarySpecies!;
    return WildlifeTacticalEngine.assessZone(
      zone: zone,
      species: species,
      weather: activeWeather,
      astro: activeAstro,
      baseActivityScore: zoneAssessment.activityScorePercent,
    );
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
          backgroundColor: WildlifeScoutTheme.bgObsidian,
          content: const Row(
            children: [
              Icon(Icons.info_outline, color: WildlifeScoutTheme.amberGold, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Noch keine Habitate geladen. Bitte scanne zuerst einen Sektor.',
                  style: TextStyle(color: WildlifeScoutTheme.textPrimary, fontSize: 13),
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
    FieldAssessment? bestAssessment;

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

      final tactical = WildlifeTacticalEngine.assessZone(
        zone: targetZone,
        species: primary,
        weather: weather,
        astro: astro,
        baseActivityScore: assessment.activityScorePercent,
      );

      // Score-Berechnung:
      // Basis: Situativer Chance-Score (0-100) inklusive Taktik & Mikroklima
      // Bonus für Golden Hour / Blaue Stunde (+10)
      // Starker Abzug bei Witterungskollision (-35)
      // Abzug bei Sturm / Regen
      double compositeScore = tactical.situationalChanceScore.toDouble();
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
      _bestChanceZoneId = targetZone.id;
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

    final assessmentsBySpecies = <String, FieldAssessment>{
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

    final polygons = FieldOverlayBuilder.buildMapPolygons(
      hidePosition: _hidePinPosition,
      species: activeSpecies,
      weather: currentWeather,
      habitatZones: _habitatZones,
      showHabitatZones: _showHabitatLayer,
      showScentCone: _showScentCone,
      hasScentCollision: assessment.hasScentCollision,
    );

    final polylines = FieldOverlayBuilder.buildMapPolylines(
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
          // 1. Vollbild Satelliten- & Feld-Karte (100% Echte OSM-Geometrie)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _hidePinPosition,
              initialZoom: 14.5,
              minZoom: 6.0,
              maxZoom: 18.5,
              backgroundColor: WildlifeScoutTheme.bgObsidian,
              onTap: _onMapTapped,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  if (_activeThumbCluster != _ThumbCluster.none) {
                    setState(() {
                      _activeThumbCluster = _ThumbCluster.none;
                    });
                  } else {
                    setState(() {});
                  }
                }
              },
            ),
            children: [
              TileLayer(
                key: ValueKey('base_tile_layer_$_useSatelliteLayer'),
                urlTemplate: _useSatelliteLayer
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'dev.wildlifescout.app',
                maxNativeZoom: 18,
                panBuffer: 1,
                keepBuffer: 2,
                tileProvider: NetworkTileProvider(
                  silenceExceptions: false,
                  attemptDecodeOfHttpErrorResponses: true,
                ),
                evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
                errorTileCallback: (tile, error, stackTrace) {
                  debugPrint('MAP TILE ERROR: ${tile.coordinates} -> $error');
                },
              ),
              // Optionales hybrides Ortsnamen- & Straßennetz-Overlay über Satellit (ArcGIS Reference & Transportation)
              if (_useSatelliteLayer && _showPlaceNames) ...[
                TileLayer(
                  key: const ValueKey('arcgis_boundaries_overlay'),
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'dev.wildlifescout.app',
                  maxNativeZoom: 18,
                  panBuffer: 1,
                  keepBuffer: 2,
                  tileProvider: NetworkTileProvider(
                    silenceExceptions: true,
                    attemptDecodeOfHttpErrorResponses: true,
                  ),
                  evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
                  errorTileCallback: (tile, error, stackTrace) {
                    // Graceful degradation bei Netzwerk-Timeouts
                  },
                ),
                TileLayer(
                  key: const ValueKey('arcgis_transportation_overlay'),
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'dev.wildlifescout.app',
                  maxNativeZoom: 18,
                  panBuffer: 1,
                  keepBuffer: 2,
                  tileProvider: NetworkTileProvider(
                    silenceExceptions: true,
                    attemptDecodeOfHttpErrorResponses: true,
                  ),
                  evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
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
              // Live-Niederschlags- & Unwetterradar (Offener Radar-Verbund inkl. DWD via Edge-Tile-Cache)
              if (_showRainRadarLayer && _rainRadarUrlTemplate != null)
                TileLayer(
                  urlTemplate: _rainRadarUrlTemplate!,
                  userAgentPackageName: 'dev.wildlifescout.app',
                  maxNativeZoom: 7,
                  maxZoom: 18.0,
                  panBuffer: 0,
                  keepBuffer: 1,
                  tileProvider: NetworkTileProvider(
                    silenceExceptions: true,
                    attemptDecodeOfHttpErrorResponses: false,
                  ),
                  evictErrorTileStrategy: EvictErrorTileStrategy.none,
                  errorTileCallback: (tile, error, stackTrace) {
                    // Graceful degradation bei Netzwerk-Timeouts
                  },
                  tileBuilder: (context, tileWidget, tile) => Opacity(
                    opacity: 0.85,
                    child: tileWidget,
                  ),
                ),
              PolylineLayer(polylines: polylines),
              PolygonLayer(polygons: polygons),
              // 1. Nicht ausgewählte OSM Habitat-Hotspot-Pins zum Antippen
              if (_showHabitatLayer)
                MarkerLayer(
                  rotate: true,
                  markers: _habitatZones
                      .where((zone) => zone.id != _selectedZoneInfo?.id)
                      .map((zone) {
                        final zoneAssessment = _assessmentForZone(
                          zone: zone,
                          weather: currentWeather,
                          astro: astro,
                          primaryAssessment: assessment,
                          cachedAssessments: assessmentsBySpecies,
                        );
                        final isBest = zone.id == _bestChanceZoneId;
                        return Marker(
                          point: zone.center,
                          width: 124,
                          height: 44,
                          rotate: true,
                          alignment: Alignment.center,
                          child: _buildHabitatMarker(
                            zone,
                            zoneAssessment,
                            isBestChance: isBest,
                          ),
                        );
                      }).toList(),
                ),
              // Tarnzelt / Fotospot-Pin des Fotografen + Feld-Scan-Puls beim Scannen
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
                            accentColor: WildlifeScoutTheme.cyanWater,
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
                              child: _FieldScanPulse(
                                animation: _radarController,
                                color: WildlifeScoutTheme.emeraldBio,
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
                                    ? WildlifeScoutTheme.emeraldBio
                                    : (severeWeatherAlert != null
                                        ? severeWeatherAlert.accentColor
                                        : (assessment.hasScentCollision
                                            ? WildlifeScoutTheme.crimsonScent
                                            : (_isSessionActive
                                                ? WildlifeScoutTheme.emeraldBio
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
                                  fontSize: 10.5,
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
                              color: WildlifeScoutTheme.bgObsidian,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: (_isLoadingOsm || _isLocatingUser)
                                    ? WildlifeScoutTheme.emeraldBio
                                    : (severeWeatherAlert != null
                                        ? severeWeatherAlert.accentColor
                                        : (assessment.hasScentCollision
                                            ? WildlifeScoutTheme.crimsonScent
                                            : (_isSessionActive
                                                ? WildlifeScoutTheme.amberGold
                                                : Colors.white38))),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isLoadingOsm || _isLocatingUser)
                                      ? WildlifeScoutTheme.emeraldBio.withValues(
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
              // 3. Ausgewähltes Habitat: Detailkarte & Callout-Pin
              // Liegt als oberste Kartenebene IMMER im Vordergrund über dem Ansitz-Pin und anderen Markern.
              if (_showHabitatLayer && _selectedZoneInfo != null)
                MarkerLayer(
                  rotate: true,
                  markers: () {
                    final zone = _selectedZoneInfo!;
                    final isBest = zone.id == _bestChanceZoneId;
                    final zoneAssessment = _assessmentForZone(
                      zone: zone,
                      weather: currentWeather,
                      astro: astro,
                      primaryAssessment: assessment,
                      cachedAssessments: assessmentsBySpecies,
                    );

                    // Smarte Ausrichtung: Wenn der Ansitz-Pin nördlich liegt (oder der obere
                    // Bildschirmrand zu nah ist), öffnet sich der Callout nach unten,
                    // damit die Detailanzeige und der Ansitz-Pin sich gegenseitig nicht überlagern.
                    bool openDownward = false;
                    try {
                      final zoneOffset =
                          _mapController.camera.latLngToScreenOffset(zone.center);
                      final hideOffset = _mapController.camera
                          .latLngToScreenOffset(_hidePinPosition);
                      final dy = hideOffset.dy -
                          zoneOffset.dy; // < 0 bedeutet Ansitz-Pin liegt oberhalb
                      final dx = (hideOffset.dx - zoneOffset.dx).abs();

                      final collidesWithHidePin =
                          dy < 0 && dy > -180 && dx < 160;
                      final tooCloseToTop = zoneOffset.dy < 190;
                      final hasSpaceBelow = zoneOffset.dy <
                          (_mapController.camera.size.height - 180);

                      if ((collidesWithHidePin || tooCloseToTop) &&
                          hasSpaceBelow) {
                        openDownward = true;
                      }
                    } catch (_) {
                      final isNorth =
                          _hidePinPosition.latitude >= zone.center.latitude;
                      const dist = Distance();
                      final meters = dist.as(
                          LengthUnit.Meter, _hidePinPosition, zone.center);
                      if (isNorth && meters < 180) {
                        openDownward = true;
                      }
                    }

                    return [
                      Marker(
                        point: zone.center,
                        width: 304,
                        height: 196,
                        rotate: true,
                        alignment: openDownward
                            ? const Alignment(0.0, -0.755)
                            : const Alignment(0.0, 0.755),
                        child: _buildHabitatMarker(
                          zone,
                          zoneAssessment,
                          openDownward: openDownward,
                          isBestChance: isBest,
                        ),
                      ),
                    ];
                  }(),
                ),
            ],
          ),

          // 2. Aufgeräumtes Top Field HUD (schlanke Liquid Glass Leiste)
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

          // 3. Daumenzone: Vertikale schwebende Funktions-Insel (Rechts)
          // Dynamischer Abstand nach unten, damit die Daumen-Navigation niemals von der unteren Box überdeckt wird
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            right: 14,
            bottom: (_isDeckExpanded
                    ? (isMobile ? 524.0 : 440.0)
                    : (isMobile
                        ? (260.0 +
                            (_appSettings.showHudCompassTape ? 44.0 : 0.0))
                        : 250.0)) +
                MediaQuery.of(context).padding.bottom,
            child: _buildFloatingFieldIsland(currentWeather),
          ),

          // 4. Bottom Thumb-Zone Control Deck (Adaptive Progressive Disclosure)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 10 : 16,
                  0,
                  isMobile ? 10 : 16,
                  isMobile ? 10 : 14,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMobile && _appSettings.showHudCompassTape) ...[
                        HudCompassTape(
                          currentWeather: currentWeather,
                          initialHeading: _deviceHeading,
                          onTap: _openWindCompassSheet,
                        ),
                        const SizedBox(height: 6),
                      ],
                      _buildBottomControlDeck(
                        species: activeSpecies,
                        weather: currentWeather,
                        astro: astro,
                        assessment: assessment,
                        severeWeatherAlert: severeWeatherAlert,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (_isNightVisionRedMode) {
      return ColorFiltered(
        colorFilter: WildlifeScoutTheme.nightVisionRedMatrix,
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    final speciesMaxWidth = screenWidth < 340
        ? 55.0
        : (screenWidth < 400 ? 75.0 : (isMobile ? 95.0 : 150.0));

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: WildlifeScoutTheme.glassDecoration(
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
                    colors: [WildlifeScoutTheme.emeraldBio, Color(0xFF059669)],
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
                          fontSize: 15.0,
                          letterSpacing: 0.6,
                          color: WildlifeScoutTheme.textPrimary,
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
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
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
                              horizontal: 6,
                              vertical: 2,
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
                                  size: 11,
                                  color: severeWeatherAlert.accentColor,
                                ),
                                const SizedBox(width: 3.5),
                                Text(
                                  severeWeatherAlert.isDanger
                                      ? 'ALARM'
                                      : 'UNWETTER',
                                  style: TextStyle(
                                    fontSize: 10.0,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.4,
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
                        color: WildlifeScoutTheme.surfaceCard,
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
                                    maxWidth: speciesMaxWidth,
                                  ),
                                  child: Text(
                                    speciesButtonLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
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
              const SizedBox(width: 8),

              // App-Einstellungen & Suchradius im Header direkt rechts neben der Tierauswahl
              Tooltip(
                message: 'App-Einstellungen & Suchradius',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _openSettingsSheet();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: WildlifeScoutTheme.surfaceCard.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.tune_rounded,
                          size: 19,
                          color: WildlifeScoutTheme.textPrimary,
                        ),
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

  /// Schwebende Funktions-Insel in der ergonomischen Daumenzone (Rechts)
  Widget _buildFloatingFieldIsland(WeatherFrame currentWeather) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 1. Navigation & Orte (Standort, Suche, Gemerkte Punkte) – Ganz oben
        _buildNavigationCluster(currentWeather),
        const SizedBox(height: 6),

        // 2. Quick Action: "Beste Chance" (Top-Tag, Uhrzeit & Fotospot) – Position 2
        _BestChanceFloatingButton(
          hasZones: _habitatZones.isNotEmpty,
          onTap: () {
            if (_activeThumbCluster != _ThumbCluster.none) {
              setState(() => _activeThumbCluster = _ThumbCluster.none);
            }
            _applyBestChanceOpportunity();
          },
        ),
        const SizedBox(height: 6),

        // 3. Karten-Ebenen & Nachtmodus (1-Tap Direktzugriff)
        _FieldFloatingButton(
          icon: Icons.layers_rounded,
          tooltip: 'Karten-Ebenen & Nachtsicht',
          badgeColor: _isNightVisionRedMode
              ? WildlifeScoutTheme.crimsonScent
              : (_showRainRadarLayer
                  ? WildlifeScoutTheme.cyanWater
                  : (!_useSatelliteLayer ? WildlifeScoutTheme.cyanWater : null)),
          onTap: () {
            HapticFeedback.lightImpact();
            if (_activeThumbCluster != _ThumbCluster.none) {
              setState(() => _activeThumbCluster = _ThumbCluster.none);
            }
            _openMapLayersSheet();
          },
        ),
        const SizedBox(height: 6),

        // 4. Ansitz- & Feld-Tools (Witterungs-Kompass & Sensor-Optik)
        _buildToolsCluster(currentWeather),
      ],
    );
  }

  Widget _buildNavigationCluster(WeatherFrame currentWeather) {
    final isExpanded = _activeThumbCluster == _ThumbCluster.navigation;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerRight,
          child: isExpanded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Gemerkte Punkte (Spot-Tresor)
                    _FieldFloatingButton(
                      icon: Icons.bookmark_rounded,
                      tooltip: 'Geheimer Spot-Tresor (${_savedSpots.length})',
                      badgeColor: _savedSpots.isNotEmpty
                          ? WildlifeScoutTheme.amberGold
                          : null,
                      iconColor: WildlifeScoutTheme.amberGold,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _activeThumbCluster = _ThumbCluster.none);
                        _openSpotVaultSheet(currentWeather);
                      },
                    ),
                    const SizedBox(width: 6),

                    // Ort / Waldgebiet suchen
                    _FieldFloatingButton(
                      icon: Icons.search_rounded,
                      tooltip: 'Ort, Waldgebiet oder Koordinaten suchen',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _activeThumbCluster = _ThumbCluster.none);
                        _openLocationSearchSheet();
                      },
                    ),
                    const SizedBox(width: 6),

                    // GPS / Standort zentrieren
                    _FieldFloatingButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'Zum aktuellen Standort springen',
                      isLoading: _isLocatingUser,
                      iconColor: WildlifeScoutTheme.emeraldBio,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _activeThumbCluster = _ThumbCluster.none);
                        _locateAndMoveToCurrentPosition();
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        // Trigger Button für Navigation
        _FieldFloatingButton(
          icon: isExpanded ? Icons.close_rounded : Icons.near_me_rounded,
          tooltip: isExpanded
              ? 'Navigation schließen'
              : 'Navigation & Orte (Standort, Suche, Spots)',
          isActive: isExpanded,
          activeBorderColor: WildlifeScoutTheme.emeraldBio,
          activeBgColor: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.22),
          iconColor: isExpanded
              ? WildlifeScoutTheme.emeraldBio
              : WildlifeScoutTheme.textPrimary,
          badgeColor: (!isExpanded && _savedSpots.isNotEmpty)
              ? WildlifeScoutTheme.amberGold
              : null,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _activeThumbCluster = isExpanded
                  ? _ThumbCluster.none
                  : _ThumbCluster.navigation;
            });
          },
        ),
      ],
    );
  }

  Widget _buildToolsCluster(WeatherFrame currentWeather) {
    final isExpanded = _activeThumbCluster == _ThumbCluster.tools;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerRight,
          child: isExpanded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Witterungs- & Wind-Kompass (mit offiziellem Kompass-Symbol)
                    _FieldFloatingButton(
                      icon: Icons.explore_rounded,
                      tooltip:
                          '360° Witterungs- & Wind-Kompass (${currentWeather.windCardinalLabel}, ${currentWeather.windSpeedKmh.round()} km/h)',
                      badgeColor: WildlifeScoutTheme.cyanWater,
                      iconColor: WildlifeScoutTheme.cyanWater,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _activeThumbCluster = _ThumbCluster.none);
                        _openWindCompassSheet();
                      },
                    ),
                    const SizedBox(width: 6),

                    // 2. Foto-Ausrüstung & Wildlife-Optik (Optik/Fokus-Symbol statt Kamera)
                    _FieldFloatingButton(
                      icon: Icons.center_focus_strong_rounded,
                      tooltip:
                          'Optik- & Sensor-Setup (${_currentPhotoGear.effectiveFocalLengthMm.round()} mm KB)',
                      badgeColor: WildlifeScoutTheme.cyanWater,
                      iconColor: WildlifeScoutTheme.cyanWater,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _activeThumbCluster = _ThumbCluster.none);
                        PhotoGearSheet.show(
                          context,
                          onGearChanged: () {
                            setState(() {
                              _currentPhotoGear =
                                  PhotoGearService.gearNotifier.value;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        // Trigger Button für Ansitz- & Feld-Tools (Sensorik & Optik)
        _FieldFloatingButton(
          icon: isExpanded ? Icons.close_rounded : Icons.sensors_rounded,
          tooltip: isExpanded
              ? 'Tools schließen'
              : 'Ansitz-Tools (Witterungs-Kompass & Sensor-Optik)',
          isActive: isExpanded,
          activeBorderColor: WildlifeScoutTheme.cyanWater,
          activeBgColor: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.22),
          iconColor: isExpanded
              ? WildlifeScoutTheme.cyanWater
              : WildlifeScoutTheme.textPrimary,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _activeThumbCluster =
                  isExpanded ? _ThumbCluster.none : _ThumbCluster.tools;
            });
          },
        ),
      ],
    );
  }

  Widget _buildHabitatMarker(
    HabitatZone zone,
    FieldAssessment zoneAssessment, {
    bool openDownward = false,
    bool isBestChance = false,
  }) {
    final isSelected = _selectedZoneInfo?.id == zone.id;
    final accentColor = zone.type == HabitatZoneType.waterSuhle
        ? WildlifeScoutTheme.cyanWater
        : _accentForSpeciesId(zone.speciesId);

    final activityScore = zoneAssessment.activityScorePercent;
    final activityColor = _colorForActivityScore(activityScore);
    final tactical = _tacticalAssessmentForZone(
      zone: zone,
      zoneAssessment: zoneAssessment,
    );
    final chanceScore = tactical.situationalChanceScore;
    final chanceColor = _colorForChanceScore(chanceScore);
    final species = _speciesForId(zone.speciesId);
    final chanceRating = _ratingForChanceScore(chanceScore);

    if (isSelected) {
      // Ausgewähltes Habitat: Vertikaler Callout-Pin mit Aufklapp-Details (Aktivität & Biotop)
      // Je nach Platzierung schwebt die Karte oberhalb oder unterhalb des Pins,
      // um Kollisionen mit dem Ansitz-Pin oder dem Bildschirmrand zu verhindern.
      return SizedBox(
        width: 304,
        height: 196,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Text-Callout über oder unter dem Pin
            Positioned(
              top: openDownward ? 50 : 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showScoreExplanationSheet(
                    zone: zone,
                    zoneAssessment: zoneAssessment,
                    chanceScore: chanceScore,
                    tacticalAssessment: tactical,
                  );
                },
                child: Container(
                  width: 300,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isBestChance
                          ? WildlifeScoutTheme.amberGold
                          : Colors.white.withValues(alpha: 0.85),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.85),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: (isBestChance
                                ? WildlifeScoutTheme.amberGold
                                : chanceColor)
                            .withValues(alpha: 0.38),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Tier-Foto + Titel + Spezies-Badge + Schließen-Button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (species != null)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _openSpeciesInspectorFor(species);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: isBestChance
                                        ? WildlifeScoutTheme.amberGold
                                        : accentColor.withValues(alpha: 0.6),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accentColor.withValues(alpha: 0.25),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SpeciesPhotoAvatar(
                                    species: species,
                                    width: 48,
                                    height: 48,
                                    borderRadius: 10,
                                    borderWidth: 0,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Oberste Zeile: Tag / Badge & Close
                                Row(
                                  children: [
                                    if (isBestChance) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: WildlifeScoutTheme.amberGold
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                            color: WildlifeScoutTheme.amberGold,
                                            width: 0.9,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.auto_awesome,
                                              size: 9.5,
                                              color:
                                                  WildlifeScoutTheme.amberGold,
                                            ),
                                            SizedBox(width: 2.5),
                                            Text(
                                              'BESTE CHANCE',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                color: WildlifeScoutTheme
                                                    .amberGold,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else if (species != null) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accentColor
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                            color: accentColor
                                                .withValues(alpha: 0.4),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          species.name,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: accentColor,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        setState(
                                            () => _selectedZoneInfo = null);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(2.5),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),

                                // Spot-Titel
                                Text(
                                  zone.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                const SizedBox(height: 1),

                                // Chance & Rating Zeile
                                Row(
                                  children: [
                                    Icon(
                                      isBestChance
                                          ? Icons.auto_awesome
                                          : Icons.track_changes_rounded,
                                      size: 11.5,
                                      color: isBestChance
                                          ? WildlifeScoutTheme.amberGold
                                          : chanceColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$chanceScore% Chance',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: isBestChance
                                            ? WildlifeScoutTheme.amberGold
                                            : chanceColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '•  $chanceRating',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: WildlifeScoutTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),

                      // Wichtige Kern-Faktoren (Tieraktivität & Biotop-Güte)
                      Row(
                        children: [
                          // Faktor 1: Live-Aktivität
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: activityColor.withValues(alpha: 0.25),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 14,
                                    color: activityColor,
                                  ),
                                  const SizedBox(width: 3.5),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$activityScore% Aktivität',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: activityColor,
                                          ),
                                        ),
                                        const Text(
                                          'Zeit & Wetter',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w500,
                                            color: WildlifeScoutTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),

                          // Faktor 2: Biotop-Eignung
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: accentColor.withValues(alpha: 0.25),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    zone.type == HabitatZoneType.waterSuhle
                                        ? Icons.water_drop_rounded
                                        : Icons.park_rounded,
                                    size: 14,
                                    color: accentColor,
                                  ),
                                  const SizedBox(width: 3.5),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${zone.suitabilityScore.round()}% Biotop',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: accentColor,
                                          ),
                                        ),
                                        const Text(
                                          'Gelände & Äsung',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w500,
                                            color: WildlifeScoutTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Interaktiver Detail-Aufruf (Ersetzt die alte Rechenformel)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4.5,
                        ),
                        decoration: BoxDecoration(
                          color: chanceColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: chanceColor.withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.insights_rounded,
                              size: 13,
                              color: chanceColor,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                tactical.badges.isNotEmpty
                                    ? '${tactical.badges.first.icon} ${tactical.badges.first.title}'
                                    : 'Vor-Ort-Faktoren & Taktik',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: chanceColor,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            Text(
                              'Details anzeigen',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: chanceColor.withValues(alpha: 0.95),
                              ),
                            ),
                            const SizedBox(width: 1),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 13,
                              color: chanceColor.withValues(alpha: 0.85),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. Kleiner Verbindungszeiger (oben oder unten)
            Positioned(
              top: openDownward ? 40 : 146,
              child: Container(
                width: 2,
                height: 10,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),

            // 3. Highlighted Pin (exakt zentriert auf der Koordinate)
            Positioned(
              top: openDownward ? 8 : 156,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showScoreExplanationSheet(
                    zone: zone,
                    zoneAssessment: zoneAssessment,
                    chanceScore: chanceScore,
                    tacticalAssessment: tactical,
                  );
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: WildlifeScoutTheme.bgObsidian,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isBestChance
                              ? WildlifeScoutTheme.amberGold
                              : Colors.white,
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isBestChance
                                    ? WildlifeScoutTheme.amberGold
                                    : chanceColor)
                                .withValues(alpha: 0.85),
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
                            isBestChance
                                ? Icons.auto_awesome
                                : Icons.track_changes_rounded,
                            size: 13,
                            color: isBestChance
                                ? WildlifeScoutTheme.amberGold
                                : chanceColor,
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            '$chanceScore%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: isBestChance
                                  ? WildlifeScoutTheme.amberGold
                                  : chanceColor,
                            ),
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            'Chance',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isBestChance)
                      Positioned(
                        top: -8.5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: WildlifeScoutTheme.bgObsidian,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: WildlifeScoutTheme.amberGold,
                              width: 1.1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: WildlifeScoutTheme.amberGold
                                    .withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 9,
                                color: WildlifeScoutTheme.amberGold,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'BESTE CHANCE',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: WildlifeScoutTheme.amberGold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
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

    // Standard-Zustand: Selbsterklärender Feld-Marker mit kombiniertem Chance-Score
    // In die obere Border ist vertikal mittig der Tiername bzw. "Beste Chance" eingetragen
    final badgeColor =
        isBestChance ? WildlifeScoutTheme.amberGold : chanceColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedZoneInfo = zone);
      },
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Haupt-Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
              decoration: BoxDecoration(
                color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: badgeColor,
                  width: isBestChance ? 2.2 : 1.8,
                ),
                boxShadow: [
                  const BoxShadow(
                    color: Colors.black87,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                  BoxShadow(
                    color: badgeColor.withValues(
                      alpha: isBestChance ? 0.55 : 0.28,
                    ),
                    blurRadius: isBestChance ? 10 : 7,
                    spreadRadius: isBestChance ? 1 : 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isBestChance
                        ? Icons.auto_awesome
                        : Icons.track_changes_rounded,
                    size: 13,
                    color: badgeColor,
                  ),
                  const SizedBox(width: 3.5),
                  Text(
                    '$chanceScore%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: badgeColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 3.5),
                  Text(
                    'Chance',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),

            // Tiername bzw. "Beste Chance" vertikal mittig auf der oberen Border positioniert
            Positioned(
              top: -8.0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.bgObsidian,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.8),
                    width: 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBestChance) ...[
                      const Icon(
                        Icons.auto_awesome,
                        size: 9,
                        color: WildlifeScoutTheme.amberGold,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      isBestChance
                          ? 'BESTE CHANCE'
                          : zone.speciesName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: badgeColor,
                        letterSpacing: 0.5,
                        height: 1.15,
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

  Widget _buildBestChanceHUDCard(String info) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.75),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.22),
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
                    color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: WildlifeScoutTheme.amberGold,
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
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: WildlifeScoutTheme.amberGold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: WildlifeScoutTheme.textPrimary,
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
                      setState(() {
                        _bestChanceBannerInfo = null;
                        _bestChanceZoneId = null;
                      });
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
                        color: WildlifeScoutTheme.textPrimary,
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


  void _showScoreExplanationSheet({
    required HabitatZone zone,
    required FieldAssessment zoneAssessment,
    required int chanceScore,
    ZoneTacticalAssessment? tacticalAssessment,
  }) {
    HapticFeedback.lightImpact();
    final accent = zone.type == HabitatZoneType.waterSuhle
        ? WildlifeScoutTheme.cyanWater
        : _accentForSpeciesId(zone.speciesId);
    final species = _speciesForId(zone.speciesId);
    final activityScore = zoneAssessment.activityScorePercent;
    final activityColor = _colorForActivityScore(activityScore);
    final tactical = tacticalAssessment ??
        _tacticalAssessmentForZone(
          zone: zone,
          zoneAssessment: zoneAssessment,
        );
    final effectiveSuitability = tactical.effectiveSuitabilityScore;
    final finalChanceScore = tactical.situationalChanceScore;
    final chanceColor = _colorForChanceScore(finalChanceScore);
    final chanceRating = _ratingForChanceScore(finalChanceScore);

    final currentWeather = _hourlyForecast[_activeForecastIndex];
    final astro = SunMoonCalculator.calculate(
      dateTime: currentWeather.time,
      latitude: _hidePinPosition.latitude,
      longitude: _hidePinPosition.longitude,
    );

    String? soilDetail;
    String? slopeDetail;
    for (final part in zone.subtitle.split(' • ')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('Boden:') || trimmed.contains('Boden')) {
        soilDetail = trimmed.replaceFirst('Boden:', '').trim();
      } else if (trimmed.startsWith('Hang') || trimmed.contains('Hang')) {
        slopeDetail = trimmed;
      }
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.98),
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
          child: SingleChildScrollView(
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

                // Header: Tier-Foto + Titel + Chance Badge
                Row(
                  children: [
                    if (species != null)
                      GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _openSpeciesInspectorFor(species);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.6),
                              width: 1.3,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SpeciesPhotoAvatar(
                              species: species,
                              width: 48,
                              height: 48,
                              borderRadius: 12,
                              borderWidth: 0,
                            ),
                          ),
                        ),
                      )
                    else
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
                          Row(
                            children: [
                              Text(
                                'Sichtungs-Chance: $finalChanceScore%',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  color: chanceColor,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: chanceColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: chanceColor.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  chanceRating,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: chanceColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${species?.name ?? 'Wildart'} • ${zone.title}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: WildlifeScoutTheme.textMuted,
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

                // Button: Voller Steckbrief
                if (species != null) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _openSpeciesInspectorFor(species);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.45),
                          width: 1.1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_stories_rounded,
                            size: 18,
                            color: accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Voller Steckbrief: ${species.name}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(height: 1.5),
                                const Text(
                                  'Biologie, Sinne, Fluchtdistanz, Äsung & Foto-Tipps',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: WildlifeScoutTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Öffnen',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 11,
                                  color: accent,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Erklärung: Was bedeutet die Chance?
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: chanceColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: chanceColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.help_outline_rounded,
                            size: 16,
                            color: chanceColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Was bedeutet $finalChanceScore% Chance?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: chanceColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Keine pauschale Wahrscheinlichkeit, sondern deine konkrete Sichtungs-Chance zu dieser Stunde an genau diesem Ort. Sie verbindet die beiden Kernfragen „Wann?“ und „Wo?“ zu einem Gesamtwert:',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
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
                            child: Row(
                              children: [
                                Text(
                                  '1. Live-Wildaktivität: $activityScore%',
                                  style: TextStyle(
                                    fontSize: 13.5,
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Konkrete Einflussfaktoren zu dieser Stunde (${currentWeather.time.hour.toString().padLeft(2, '0')}:00 Uhr):',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Aufzählung aller Aktivitäts-Faktoren:
                      _buildFactorRow(
                        icon: Icons.wb_twilight_rounded,
                        iconColor: activityColor,
                        label: 'Dämmerung & Tageszeit',
                        value:
                            '${astro.lightPhaseLabel}${astro.isGoldenHour ? ' (Goldene Stunde)' : astro.isBlueHour ? ' (Blaue Stunde)' : ''}',
                        detail: species != null &&
                                species.behavior.primaryActivityPeriods
                                    .contains(astro.currentPeriod)
                            ? 'Hauptaktivitätsphase für ${species.name} (hohe Austrittschance)'
                            : 'Nebenzeiten (typische Einstands- und Ruhephase)',
                      ),
                      _buildFactorRow(
                        icon: Icons.speed_rounded,
                        iconColor: activityColor,
                        label: 'Luftdruck & Barometer',
                        value:
                            '${currentWeather.surfacePressureHpa.round()} hPa (${currentWeather.pressureDelta6hHpa >= 0 ? '+' : ''}${currentWeather.pressureDelta6hHpa.toStringAsFixed(1)} hPa in 6h)',
                        detail: zoneAssessment.barometerInsight.isNotEmpty
                            ? zoneAssessment.barometerInsight
                            : 'Stabiler Luftdrucktrend',
                      ),
                      _buildFactorRow(
                        icon: Icons.air_rounded,
                        iconColor: activityColor,
                        label: 'Wind & Wind-Komfort',
                        value:
                            '${currentWeather.windSpeedKmh.round()} km/h aus ${currentWeather.windCardinalLabel} (Böen: ${currentWeather.windGustsKmh.round()} km/h)',
                        detail: zoneAssessment.windAdvice,
                      ),
                      _buildFactorRow(
                        icon: Icons.thermostat_rounded,
                        iconColor: activityColor,
                        label: 'Temperatur',
                        value:
                            '${currentWeather.temperatureCelsius.toStringAsFixed(1)} °C',
                        detail: currentWeather.temperatureCelsius >= 8 &&
                                currentWeather.temperatureCelsius <= 22
                            ? 'Angenehme Wohlfühltemperatur für das Wild'
                            : currentWeather.temperatureCelsius < 8
                                ? 'Kühle Witterung regt die Nahrungsaufnahme an'
                                : 'Warme Witterung, Wild meidet pralle Sonne',
                      ),
                      _buildFactorRow(
                        icon: Icons.nightlight_round,
                        iconColor: activityColor,
                        label: 'Mondphase & Nachtlicht',
                        value:
                            '${astro.moonPhaseName} (${(astro.moonIlluminationFraction * 100).round()}% Licht)',
                        detail: astro.moonIlluminationFraction < 0.25
                            ? 'Dunkle Neumondnacht: Wild zieht morgens früher und hungriger auf Freiflächen'
                            : 'Helles Mondlicht begünstigt Nachtäsungszyklen',
                      ),
                      _buildFactorRow(
                        icon: Icons.cloud_outlined,
                        iconColor: activityColor,
                        label: 'Bewölkung & Niederschlag',
                        value: '${currentWeather.cloudCoverPercent}% Bewölkung',
                        detail: currentWeather.isHeavyRain
                            ? 'Starkregen hemmt Bewegung (Wild meidet offenes Gelände)'
                            : currentWeather.precipitationMm > 0
                                ? 'Leichter Niederschlag (${currentWeather.precipitationMm.toStringAsFixed(1)} mm) dämpft Geräusche'
                                : 'Trockene Witterung begünstigt vertrauten Austritt',
                        isLast: true,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
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
                            child: Row(
                              children: [
                                Text(
                                  '2. Biotop-Güte: ${zone.suitabilityScore.round()}%',
                                  style: TextStyle(
                                    fontSize: 13.5,
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gelände- & Habitatkriterien für diesen Spot (${zone.title}):',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Aufzählung aller Biotop-Faktoren:
                      _buildFactorRow(
                        icon: Icons.directions_walk_rounded,
                        iconColor: accent,
                        label: 'Wanderweg-Abstand & Ruhelage',
                        value:
                            '${zone.distanceToNearestTrailMeters.round()} m zum Pfad',
                        detail: zone.distanceToNearestTrailMeters >= 150
                            ? 'Störungsarme Ruhelage: Großer Pufferabstand zu Freizeitwegen'
                            : zone.distanceToNearestTrailMeters >= 80
                                ? 'Moderater Abstand: Wild verhält sich vorsichtig sichernd'
                                : 'Geringer Abstand: Fluchtrisiko bei Fußgängern und Hunden',
                      ),
                      _buildFactorRow(
                        icon: Icons.water_drop_outlined,
                        iconColor: accent,
                        label: 'Wasserstelle & Suhlen',
                        value: zone.distanceToWaterMeters < 15
                            ? 'Direkt am Wasser (<15 m)'
                            : '${zone.distanceToWaterMeters.round()} m zum Gewässer',
                        detail: zone.distanceToWaterMeters <= 50
                            ? 'Unmittelbare Tränke- & Suhlennähe (starker Anziehungspunkt)'
                            : zone.distanceToWaterMeters <= 150
                                ? 'Gute Erreichbarkeit im Nahbereich'
                                : 'Größere Distanz, primär reiner Äsungsbereich',
                      ),
                      _buildFactorRow(
                        icon: Icons.forest_outlined,
                        iconColor: accent,
                        label: 'Deckung & Waldgrenze',
                        value:
                            '${zone.distanceToForestMeters.round()} m zum Saum (${zone.type.label})',
                        detail: zone.distanceToForestMeters <= 15
                            ? 'Idealer Waldsaum: Schnelle Deckung im dichten Bestand'
                            : 'Offeneres Feld mit längeren Fluchtwegen zum Bestand',
                      ),
                      if (slopeDetail != null)
                        _buildFactorRow(
                          icon: Icons.terrain_rounded,
                          iconColor: accent,
                          label: 'Topographie & Hang',
                          value: slopeDetail,
                          detail:
                              'Hangprofil und Neigung bestimmen Witterungsschutz und Sonneneinstrahlung',
                        ),
                      if (soilDetail != null)
                        _buildFactorRow(
                          icon: Icons.layers_rounded,
                          iconColor: accent,
                          label: 'Boden-Substrat & Vegetation',
                          value: soilDetail,
                          detail:
                              'Nährstoffreiches Substrat begünstigt schmackhafte Äsungspflanzen',
                          isLast: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Faktor 3: Mikroklima & Taktik (Luv/Lee, Sonne, Phänologie, Wege-Ruhe)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (tactical.tacticalScoreAdjustment >= 0
                              ? WildlifeScoutTheme.emeraldBio
                              : WildlifeScoutTheme.amberGold)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: (tactical.tacticalScoreAdjustment >= 0
                                      ? WildlifeScoutTheme.emeraldBio
                                      : WildlifeScoutTheme.amberGold)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              tactical.tacticalScoreAdjustment >= 0
                                  ? Icons.air_rounded
                                  : Icons.warning_amber_rounded,
                              color: tactical.tacticalScoreAdjustment >= 0
                                  ? WildlifeScoutTheme.emeraldBio
                                  : WildlifeScoutTheme.amberGold,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  '3. Mikroklima & Taktik: ${tactical.tacticalScoreAdjustment >= 0 ? '+' : ''}${tactical.tacticalScoreAdjustment.round()}%',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: tactical.tacticalScoreAdjustment >= 0
                                        ? WildlifeScoutTheme.emeraldBio
                                        : WildlifeScoutTheme.amberGold,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Vor Ort',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: (tactical.tacticalScoreAdjustment >=
                                                0
                                            ? WildlifeScoutTheme.emeraldBio
                                            : WildlifeScoutTheme.amberGold)
                                        .withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Konkrete Vor-Ort-Einflüsse an dieser Kante:',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (tactical.badges.isNotEmpty)
                        ...tactical.badges.map(
                          (b) => Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4.5),
                                  decoration: BoxDecoration(
                                    color: (b.isPositive
                                            ? WildlifeScoutTheme.emeraldBio
                                            : WildlifeScoutTheme.amberGold)
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    b.icon,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            b.title,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            b.deltaLabel,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                              color: b.isPositive
                                                  ? WildlifeScoutTheme
                                                      .emeraldBio
                                                  : WildlifeScoutTheme
                                                      .amberGold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 1.5),
                                      Text(
                                        b.description,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          height: 1.25,
                                          color: WildlifeScoutTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Neutrale Bedingungen: Keine extremen Windeinflüsse oder akuten Störungen an diesem Kantenabschnitt.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                        ),
                      _buildFactorRow(
                        icon: Icons.calendar_month_rounded,
                        iconColor: WildlifeScoutTheme.amberGold,
                        label: 'Jahreszeitliche Phänologie',
                        value:
                            '${tactical.phenology.emoji} ${tactical.phenology.phaseName}',
                        detail: tactical.phenology.description,
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Erfolgs-Synthese
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
                        Icons.insights_rounded,
                        size: 15,
                        color: chanceColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Erfolgs-Synthese: Live-Wildaktivität ($activityScore%) & Vor-Ort-Biotop (${effectiveSuitability.round()}%) ergeben $finalChanceScore% Sichtungs-Chance.',
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
                const SizedBox(height: 10),

                // Interaktiver Tipp zur Zeitleiste
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 15,
                        color: WildlifeScoutTheme.amberGold,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tipp: Verstelle unten den Zeitstrahl auf 06:00 oder 18:00 Uhr. Weil Wild in der Dämmerung aktiver ist, klettert auch die Chance an diesem Spot sofort nach oben!',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: WildlifeScoutTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (species != null) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _openSpeciesInspectorFor(species);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent.withValues(alpha: 0.18),
                        foregroundColor: accent,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.5),
                            width: 1.1,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.auto_stories_rounded, size: 18),
                      label: Text(
                        'Voller Steckbrief: ${species.name}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildFactorRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String detail,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 7.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4.5),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 12.5, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1.5),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    color: WildlifeScoutTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    if (weather.precipitationMm > 0.1) return WildlifeScoutTheme.cyanWater;
    if (weather.cloudCoverPercent >= 75) return WildlifeScoutTheme.textMuted;
    if (astro.currentPeriod == ActivityPeriod.night) {
      return const Color(0xFFC7D2FE);
    }
    return WildlifeScoutTheme.amberGold;
  }

  (IconData icon, Color color, String val, String detail) _getBarometerTelemetry(
    WeatherFrame weather,
  ) {
    final delta = weather.pressureDelta6hHpa;
    final valStr = '${weather.surfacePressureHpa.round()} hPa';
    if (delta <= -2.0) {
      return (
        Icons.trending_down_rounded,
        WildlifeScoutTheme.amberGold,
        valStr,
        '⚡ Fällt (${delta.toStringAsFixed(1)}) • Fress-Schub',
      );
    } else if (delta <= -0.7) {
      return (
        Icons.trending_down_rounded,
        WildlifeScoutTheme.amberGold,
        valStr,
        'Fällt (${delta.toStringAsFixed(1)}) • Mehr Aktivität',
      );
    } else if (delta >= 1.5) {
      return (
        Icons.trending_up_rounded,
        WildlifeScoutTheme.cyanWater,
        valStr,
        'Steigt (+${delta.toStringAsFixed(1)}) • Ruhiges Wild',
      );
    } else {
      return (
        Icons.trending_flat_rounded,
        WildlifeScoutTheme.textMuted,
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

      // Wolken-Faktor (Ideal: ca. 45% Bewölkung, besonders hohe Cirren begünstigen Streulicht)
      final cloud = weather.cloudCoverPercent;
      double cloudFactor = 0.0;
      if (weather.cloudCoverLowPercent >= 75) {
        cloudFactor = 0.0; // Tiefe dichte Decke schluckt das Abendlicht
      } else if (weather.cloudCoverHighPercent >= 35 &&
          weather.cloudCoverLowPercent <= 30) {
        cloudFactor = 1.0; // Perfekter Cirrus-Schleierschirm für feuerrotes Streulicht
      } else if (cloud >= 10 && cloud <= 80) {
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
        WildlifeScoutTheme.amberGold,
        isMorning ? 'Morgen-Gold' : 'Abend-Gold',
        '${astro.sunElevationDegrees.toStringAsFixed(0)}° Streiflicht',
      );
    } else if (astro.isBlueHour) {
      return (
        Icons.wb_twilight_rounded,
        WildlifeScoutTheme.cyanWater,
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
        WildlifeScoutTheme.amberGold,
        'Sonne',
        '${astro.sunElevationDegrees.round()}°',
      );
    } else {
      return (
        Icons.wb_sunny_outlined,
        WildlifeScoutTheme.textMuted,
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
        WildlifeScoutTheme.cyanWater,
        '${weather.precipitationMm.toStringAsFixed(1)} mm',
        'Regen',
      );
    } else if (weather.isFog ||
        (weather.visibilityMeters != null && weather.visibilityMeters! < 1000)) {
      return (
        Icons.cloud_queue_rounded,
        const Color(0xFFCBD5E1),
        'Nebel',
        weather.visibilityMeters != null
            ? 'Sicht ${(weather.visibilityMeters! / 1000).toStringAsFixed(1)} km'
            : 'Sicht < 1 km',
      );
    } else if (weather.cloudCoverPercent >= 75) {
      final detailStr = weather.cloudCoverLowPercent >= 70
          ? 'Tiefe Decke'
          : weather.cloudCoverHighPercent >= 60
              ? 'Cirrenschleier'
              : 'Bedeckt';
      return (
        Icons.cloud_rounded,
        WildlifeScoutTheme.textMuted,
        '${weather.cloudCoverPercent}%',
        detailStr,
      );
    } else if (weather.cloudCoverPercent >= 25) {
      final detailStr = weather.cloudCoverMidPercent >= 35
          ? 'Softbox-Licht'
          : weather.cloudCoverHighPercent >= 30
              ? 'Streulicht'
              : 'Leicht bewölkt';
      return (
        Icons.cloud_queue_rounded,
        const Color(0xFFBAE6FD),
        '${weather.cloudCoverPercent}%',
        detailStr,
      );
    } else {
      return (
        astro.currentPeriod == ActivityPeriod.night
            ? Icons.nightlight_round
            : Icons.wb_sunny_rounded,
        astro.currentPeriod == ActivityPeriod.night
            ? const Color(0xFFC7D2FE)
            : WildlifeScoutTheme.amberGold,
        'Klar',
        astro.currentPeriod == ActivityPeriod.night
            ? 'Klarer Sternenhimmel'
            : 'Klares Sonnenlicht',
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
        WildlifeScoutTheme.amberGold,
        valStr,
        'Thermik-Risiko',
      );
    } else if (weather.windSpeedKmh > 25.0) {
      return (
        Icons.air_rounded,
        WildlifeScoutTheme.crimsonScent,
        valStr,
        'Böig',
      );
    } else {
      return (
        Icons.air_rounded,
        WildlifeScoutTheme.emeraldBio,
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
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: color,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• ${alert.timeLabel}',
                          style: const TextStyle(
                            fontSize: 11,
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
                        fontSize: 13,
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
                        fontSize: 11.5,
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
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: color,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          alert.timeLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WildlifeScoutTheme.textMuted,
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
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: WildlifeScoutTheme.textPrimary,
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
    SunMoonPosition astro, {
    bool isMobile = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.lightImpact();
          _openWindCompassSheet();
        },
        child: Container(
          constraints: BoxConstraints(minHeight: isMobile ? 36 : 38),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 7 : 9,
            vertical: isMobile ? 5.5 : 6.5,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WildlifeScoutTheme.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getWeatherIcon(weather, astro),
                size: isMobile ? 14 : 16,
                color: _getWeatherIconColor(weather, astro),
              ),
              const SizedBox(width: 4),
              Text(
                '${weather.temperatureCelsius.toStringAsFixed(0)}°C',
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.w800,
                  color: WildlifeScoutTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 1,
                height: isMobile ? 11 : 14,
                color: WildlifeScoutTheme.borderSubtle,
              ),
              const SizedBox(width: 6),
              Transform.rotate(
                angle: weather.scentBlowDirectionDegrees * (math.pi / 180.0),
                child: Icon(
                  Icons.navigation_rounded,
                  size: isMobile ? 11 : 13,
                  color: WildlifeScoutTheme.emeraldBio,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                weather.windCardinalLabel,
                style: TextStyle(
                  fontSize: isMobile ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SliderThemeData _buildTimeSliderTheme(
    BuildContext context, {
    required double? nowFraction,
    required DateTime referenceDate,
    bool isMobile = true,
  }) {
    return SliderTheme.of(context).copyWith(
      trackHeight: isMobile ? 14.0 : 16.0,
      thumbColor: WildlifeScoutTheme.amberGold,
      overlayColor: WildlifeScoutTheme.amberGold.withValues(alpha: 0.18),
      thumbShape: RoundSliderThumbShape(
        enabledThumbRadius: isMobile ? 11.0 : 12.0,
        elevation: 3.0,
        pressedElevation: 6.0,
      ),
      overlayShape: RoundSliderOverlayShape(overlayRadius: isMobile ? 20.0 : 22.0),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1.2),
      activeTickMarkColor: Colors.white.withValues(alpha: 0.40),
      inactiveTickMarkColor: Colors.white.withValues(alpha: 0.30),
      trackShape: FieldSliderTrackShape(
        nowFraction: nowFraction,
        referenceDate: referenceDate,
        latitude: _hidePinPosition.latitude,
        longitude: _hidePinPosition.longitude,
      ),
    );
  }

  Widget _buildBriefingCard({
    required FieldAssessment assessment,
    required WeatherFrame weather,
    required Color scoreColor,
    required bool isMobile,
  }) {
    final hasCollision = assessment.hasScentCollision;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: hasCollision
            ? WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasCollision
              ? WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.55)
              : WildlifeScoutTheme.borderSubtle,
          width: hasCollision ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zeile 1: Aktivitäts-Score + Bewertung + Details-Aufklapp-Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _isDeckExpanded = !_isDeckExpanded);
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 10 : 14,
                  isMobile ? 8 : 10,
                  isMobile ? 8 : 12,
                  isMobile ? 7 : 9,
                ),
                child: Row(
                  children: [
                    // Kompakte Score-Badge mit farblichem Akzentpunkt
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 7 : 9,
                        vertical: isMobile ? 2.5 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
                        border: Border.all(
                          color: scoreColor.withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: isMobile ? 6 : 7,
                            height: isMobile ? 6 : 7,
                            decoration: BoxDecoration(
                              color: scoreColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: isMobile ? 4.5 : 6),
                          Text(
                            '${assessment.activityScorePercent}%',
                            style: TextStyle(
                              fontSize: isMobile ? 13 : 14,
                              fontWeight: FontWeight.w900,
                              color: scoreColor,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isMobile ? 8 : 12),

                    // Bewertungs-Label in klarem, ruhigem Text
                    Expanded(
                      child: Text(
                        assessment.ratingLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 13.5 : 14.5,
                          fontWeight: FontWeight.w700,
                          color: WildlifeScoutTheme.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Aufklapp-Button für erweiterte Wetter- & Umgebungs-Telemetrie
                    Container(
                      constraints: BoxConstraints(minHeight: isMobile ? 28 : 36),
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 8 : 12,
                        vertical: isMobile ? 4 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
                        border: Border.all(
                          color: WildlifeScoutTheme.borderSubtle,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isDeckExpanded
                                ? 'Weniger'
                                : (isMobile ? 'Details' : 'Wetter & Details'),
                            style: TextStyle(
                              fontSize: isMobile ? 12 : 13,
                              fontWeight: FontWeight.w600,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: _isDeckExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 250),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: isMobile ? 16 : 18,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Feine Trennlinie (Hairline Divider)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),

          // Zeile 2: Witterungs- & Wind-Status (Tippen öffnet 360° Kompass)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(14)),
              onTap: () {
                HapticFeedback.lightImpact();
                _openWindCompassSheet();
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 10 : 14,
                  isMobile ? 7 : 9,
                  isMobile ? 8 : 12,
                  isMobile ? 8 : 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      hasCollision
                          ? Icons.warning_amber_rounded
                          : (weather.windSpeedKmh < 4.0
                              ? Icons.air_rounded
                              : Icons.check_circle_outline_rounded),
                      size: isMobile ? 16 : 18,
                      color: hasCollision
                          ? WildlifeScoutTheme.crimsonScent
                          : WildlifeScoutTheme.emeraldBio,
                    ),
                    SizedBox(width: isMobile ? 7 : 10),
                    Expanded(
                      child: Text(
                        assessment.windAdvice,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 12.5 : 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: hasCollision
                              ? const Color(0xFFFFB4C0)
                              : WildlifeScoutTheme.textPrimary
                                  .withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: BoxConstraints(minHeight: isMobile ? 26 : 36),
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 7 : 12,
                        vertical: isMobile ? 3 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: hasCollision
                            ? WildlifeScoutTheme.crimsonScent
                                .withValues(alpha: 0.18)
                            : WildlifeScoutTheme.emeraldBio
                                .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(isMobile ? 6 : 10),
                        border: Border.all(
                          color: hasCollision
                              ? WildlifeScoutTheme.crimsonScent
                                  .withValues(alpha: 0.4)
                              : WildlifeScoutTheme.emeraldBio
                                  .withValues(alpha: 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.explore_rounded,
                            size: isMobile ? 13 : 16,
                            color: hasCollision
                                ? WildlifeScoutTheme.crimsonScent
                                : WildlifeScoutTheme.emeraldBio,
                          ),
                          SizedBox(width: isMobile ? 4 : 6),
                          Text(
                            'Kompass',
                            style: TextStyle(
                              fontSize: isMobile ? 11.5 : 12.5,
                              fontWeight: FontWeight.w700,
                              color: hasCollision
                                  ? const Color(0xFFFFB4C0)
                                  : WildlifeScoutTheme.emeraldBio,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControlDeck({
    required SpeciesProfile species,
    required WeatherFrame weather,
    required SunMoonPosition astro,
    required FieldAssessment assessment,
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
          padding: EdgeInsets.fromLTRB(
            isMobile ? 12 : 18,
            isMobile ? 10 : 12,
            isMobile ? 12 : 18,
            isMobile ? 12 : 14,
          ),
          decoration: WildlifeScoutTheme.glassDecoration(
            borderRadius: 24,
            borderColor: assessment.hasScentCollision
                ? WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.85)
                : WildlifeScoutTheme.borderSubtle,
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
              // 1. Drag Handle (Zentrierter Griffindikator zum Auf-/Zuklappen)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _isDeckExpanded = !_isDeckExpanded);
                },
                child: Padding(
                  padding: EdgeInsets.only(bottom: isMobile ? 7 : 9),
                  child: Center(
                    child: Container(
                      width: isMobile ? 36 : 44,
                      height: isMobile ? 4 : 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),

              // Unwetter-Alarm Card im Deck (bei aktiver Fotosession und Sturm/Gewitter)
              if (_isSessionActive && severeWeatherAlert != null) ...[
                _buildDeckSevereWeatherCard(severeWeatherAlert),
                SizedBox(height: isMobile ? 8 : 10),
              ],

              // Aufgeräumte Briefing-Card: Aktivitäts-Index & Witterungs-Lage konsolidiert
              _buildBriefingCard(
                assessment: assessment,
                weather: weather,
                scoreColor: scoreColor,
                isMobile: isMobile,
              ),
              SizedBox(height: isMobile ? 8 : 12),

              // Tier 3: Zeitschieberegler (Time-Scrubber: Ergonomisch optimiert für Touchscreen)
              if (isMobile) ...[
                // Zeile 1: Schnellauswahl-Tasten & Wetter-Telemetrie-Pill (Überlaufssicher verpackt)
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _QuickTimeButton(
                              icon: Icons.wb_twilight_rounded,
                              label: '06:00',
                              isSelected: _selectedHourOfDay == 6,
                              isMobile: true,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedHourOfDay = 6);
                              },
                            ),
                            if (_selectedDayOffset == 0) ...[
                              const SizedBox(width: 4),
                              _QuickTimeButton(
                                icon: Icons.schedule_rounded,
                                label: 'Jetzt',
                                isSelected:
                                    _selectedHourOfDay == DateTime.now().hour,
                                isMobile: true,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedHourOfDay =
                                      DateTime.now().hour);
                                },
                              ),
                            ],
                            const SizedBox(width: 4),
                            _QuickTimeButton(
                              icon: Icons.nightlight_round,
                              label: '18:00',
                              isSelected: _selectedHourOfDay == 18,
                              isMobile: true,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedHourOfDay = 18);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildWeatherTelemetryPill(weather, astro, isMobile: true),
                  ],
                ),
                const SizedBox(height: 4),

                // Zeile 2: Skalen-Header & Zeitanzeige
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '00:00 Morgenfrühe',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WildlifeScoutTheme.textMuted,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '23:00 Nacht',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WildlifeScoutTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Zeile 3: Volle Breite Zeitschieberegler mit astronomischem Lichtphasen-Verlauf & Live-Markierung
                SizedBox(
                  width: double.infinity,
                  child: SliderTheme(
                    data: _buildTimeSliderTheme(
                      context,
                      nowFraction: nowFraction,
                      referenceDate: weather.time,
                      isMobile: true,
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
                // Desktop / Tablet: Ergonomisch optimiertes Layout mit Apple HIG Touch-Targets und klarer Trennung
                // Zeile 1: Schnellauswahl-Tasten + Prominenter Live-Zeit Badge + Wetter-Telemetrie Pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Schnellauswahl-Tasten für markante Zeiten
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _QuickTimeButton(
                          icon: Icons.wb_twilight_rounded,
                          label: '06:00',
                          isSelected: _selectedHourOfDay == 6,
                          isMobile: false,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedHourOfDay = 6);
                          },
                        ),
                        const SizedBox(width: 6),
                        if (_selectedDayOffset == 0) ...[
                          _QuickTimeButton(
                            icon: Icons.schedule_rounded,
                            label: 'Jetzt',
                            isSelected:
                                _selectedHourOfDay == DateTime.now().hour,
                            isMobile: false,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedHourOfDay =
                                  DateTime.now().hour);
                            },
                          ),
                          const SizedBox(width: 6),
                        ],
                        _QuickTimeButton(
                          icon: Icons.nightlight_round,
                          label: '18:00',
                          isSelected: _selectedHourOfDay == 18,
                          isMobile: false,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedHourOfDay = 18);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),

                    // Zentrierte Live-Zeitanzeige Badge für perfekte Ablesbarkeit auf dem Tablet
                    Flexible(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.45),
                            width: 1.1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_filled_rounded,
                              size: 14,
                              color: WildlifeScoutTheme.amberGold,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '$dayLabel • $hourStr',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: WildlifeScoutTheme.amberGold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Wetter-Telemetrie Pill
                    _buildWeatherTelemetryPill(weather, astro, isMobile: false),
                  ],
                ),
                const SizedBox(height: 10),

                // Zeile 2: Skalen-Header mit Morgenfrühe, Mittag und Nacht
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '00:00 Morgenfrühe',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      Text(
                        '12:00 Mittag',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                      Text(
                        '23:00 Nacht',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),

                // Zeile 3: Volle Breite Zeitschieberegler mit ergonomischem Touch-Padding
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: SliderTheme(
                      data: _buildTimeSliderTheme(
                        context,
                        nowFraction: nowFraction,
                        referenceDate: weather.time,
                        isMobile: false,
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
                                    dayIconColor = WildlifeScoutTheme.cyanWater;
                                  } else if (dayWeather.cloudCoverPercent >= 75) {
                                    dayIcon = Icons.cloud_rounded;
                                    dayIconColor = WildlifeScoutTheme.textMuted;
                                  } else if (dayWeather.cloudCoverPercent >= 25) {
                                    dayIcon = Icons.cloud_queue_rounded;
                                    dayIconColor = const Color(0xFFBAE6FD);
                                  } else {
                                    dayIcon = Icons.wb_sunny_rounded;
                                    dayIconColor = WildlifeScoutTheme.amberGold;
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
                                          ? WildlifeScoutTheme.emeraldBio
                                              .withValues(alpha: 0.22)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? WildlifeScoutTheme.emeraldBio
                                            : WildlifeScoutTheme.borderSubtle,
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
                                                ? WildlifeScoutTheme.emeraldBio
                                                : WildlifeScoutTheme.textPrimary,
                                          ),
                                        ),
                                        if (dayWeather != null &&
                                            dayIcon != null) ...[
                                          const SizedBox(width: 5),
                                          Icon(
                                            dayIcon,
                                            size: 13,
                                            color: isSelected
                                                ? WildlifeScoutTheme.emeraldBio
                                                : dayIconColor,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${dayWeather.temperatureCelsius.round()}°',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isSelected
                                                  ? WildlifeScoutTheme.emeraldBio
                                                  : WildlifeScoutTheme.textMuted,
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
                                          iconColor: WildlifeScoutTheme.amberGold,
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
                                          ? '${weather.precipitationMm.toStringAsFixed(1)} mm • Tippen für ECMWF-Film'
                                          : '${weather.cloudStratificationSummary} • Tippen für ECMWF-Film',
                                      onTap: () => _openTacticalWindySheet(
                                        initialMode: WindyOverlayMode.clouds,
                                      ),
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
                                          '${assessment.windAdvice} (Tippen für 360° Witterungs-Kompass)',
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
          color: detailColor != null && detailColor != WildlifeScoutTheme.textMuted
              ? detailColor!.withValues(alpha: 0.35)
              : WildlifeScoutTheme.borderSubtle,
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
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: WildlifeScoutTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            detail,
            maxLines: 2,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: detailColor ?? WildlifeScoutTheme.textMuted,
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

/// Maßgeschneiderte Feld-Slider-Spur (Apple HIG konform), die im Hintergrund
/// einen nahtlosen Farbverlauf für Nacht, Blaue Stunde, Goldene Stunde und Tageslicht
/// (berechnet über den offline Sonnenstands-Rechner) über die volle Breite darstellt
/// und bei 'Heute' eine dezente vertikale Linie samt Pfeil & "JETZT"-Markierung für
/// die minutengenaue Echtzeit einzeichnet.
class FieldSliderTrackShape extends RoundedRectSliderTrackShape {
  final double? nowFraction;
  final DateTime? referenceDate;
  final double? latitude;
  final double? longitude;

  const FieldSliderTrackShape({
    this.nowFraction,
    this.referenceDate,
    this.latitude,
    this.longitude,
  });

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 14.0;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    // Der Slider nutzt die volle verfügbare Breite des Containers ohne künstlichen Overlay-Versatz
    return Rect.fromLTWH(
      offset.dx,
      trackTop,
      parentBox.size.width,
      trackHeight,
    );
  }

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

    // 49 Stützstellen (alle 30 Min.) für einen seidig-weichen, leuchtenden Übergang
    const sampleCount = 49;
    for (int i = 0; i < sampleCount; i++) {
      final stop = i / (sampleCount - 1);
      final minutesFromMidnight =
          (i * (24 * 60 - 1) / (sampleCount - 1)).round();
      final sampleHour = minutesFromMidnight ~/ 60;
      final sampleMin = minutesFromMidnight % 60;
      final sampleTime =
          DateTime(ref.year, ref.month, ref.day, sampleHour, sampleMin);
      final astroPos = SunMoonCalculator.calculate(
        dateTime: sampleTime,
        latitude: lat,
        longitude: lon,
      );

      Color color;
      if (astroPos.isGoldenHour) {
        color = const Color(0xFFF59E0B); // Strahlendes Gold / Bernstein (Dämmerung)
      } else if (astroPos.isBlueHour) {
        color = const Color(0xFF2563EB); // Intensives Dämmerungs-Blau (Blaue Stunde)
      } else if (astroPos.currentPeriod == ActivityPeriod.night) {
        color = const Color(0xFF1E293B); // Nacht-Anthrazit / Slate (klar erkennbare Nacht)
      } else {
        color = const Color(0xFF0D9488); // Frisches Tages-Türkis / Smaragd (volles Tageslicht)
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

    // Zeichne den Lichtphasen-Farbverlauf über die volle Breite (ohne abdunkelndes Overlay,
    // damit der gesamte 24h-Tageslichtzyklus auf einen Blick klar sichtbar ist)
    canvas.drawRRect(trackRRect, gradientPaint);

    canvas.restore();

    // 2. Subtiler Umrissrand (Apple HIG Outline) für perfekte Konturenschärfe
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(trackRRect, borderPaint);

    final padding = isRounded ? trackRect.height : 0.0;
    final trackCenterY = trackRect.center.dy;
    final halfTrackH = trackRect.height / 2;

    // 3. Optional: JETZT-Indikator bei heutigem Datum
    if (nowFraction != null && nowFraction! >= 0 && nowFraction! <= 23) {
      final visualPosition = (nowFraction! / 23.0).clamp(0.0, 1.0);
      final calculatedX = isDiscrete
          ? trackLeft + visualPosition * (trackWidth - padding) + padding / 2
          : trackLeft + visualPosition * trackWidth;

      // Wenn der Slider auf der Jetzt-Position steht, richten wir den Marker
      // exakt auf thumbCenter.dx aus, um Rundungsdifferenzen vollständig zu vermeiden.
      final nowX = (calculatedX - thumbCenter.dx).abs() < 1.0
          ? thumbCenter.dx
          : calculatedX;
      final markerTop = trackCenterY - halfTrackH - 2.5;
      final markerBottom = trackCenterY + halfTrackH + 2.5;

      // 3.1 Sanfter Glow-Effekt für hohe Sichtbarkeit im Nacht- & Tarnmodus
      final glowPaint = Paint()
        ..color = WildlifeScoutTheme.amberGold.withValues(alpha: 0.35)
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(nowX, markerTop - 1.0),
        Offset(nowX, markerBottom + 1.0),
        glowPaint,
      );

      // 3.2 Präzise vertikale Markierungslinie über den Schieberegler-Track
      final linePaint = Paint()
        ..color = WildlifeScoutTheme.amberGold
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(nowX, markerTop),
        Offset(nowX, markerBottom),
        linePaint,
      );

      // 3.3 Nach unten zeigender Markierungs-Pfeil (Indikator)
      final arrowTipY = markerTop;
      final arrowBaseY = arrowTipY - 5.0;
      final arrowPath = Path()
        ..moveTo(nowX, arrowTipY)
        ..lineTo(nowX - 3.5, arrowBaseY)
        ..lineTo(nowX + 3.5, arrowBaseY)
        ..close();
      final arrowPaint = Paint()
        ..color = WildlifeScoutTheme.amberGold
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowPath, arrowPaint);

      // 3.4 Kompakter "JETZT"-Schriftzug über dem Pfeil
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'JETZT',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            color: WildlifeScoutTheme.amberGold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final textX = (nowX - textPainter.width / 2).clamp(
        trackLeft,
        trackRect.right - textPainter.width,
      );
      textPainter.paint(
        canvas,
        Offset(textX, arrowBaseY - textPainter.height - 2.0),
      );
    }

    // 4. Astronomische Markierungen für Sonnenaufgang & Sonnenuntergang
    final sunTimes = SunMoonCalculator.calculateSunTimes(
      date: ref,
      latitude: lat,
      longitude: lon,
    );

    void drawSunMarker({
      required DateTime time,
      required bool isSunrise,
    }) {
      final timeFraction = (time.hour + time.minute / 60.0).clamp(0.0, 23.0);
      final visualPosition = (timeFraction / 23.0).clamp(0.0, 1.0);
      final markerX = isDiscrete
          ? trackLeft + visualPosition * (trackWidth - padding) + padding / 2
          : trackLeft + visualPosition * trackWidth;

      final markerColor = isSunrise
          ? const Color(0xFFFDE047) // Strahlendes Morgensonne-Goldgelb
          : const Color(0xFFFB923C); // Warmes Abendrot-Orange

      final markerTop = trackCenterY - halfTrackH;
      final markerBottom = trackCenterY + halfTrackH;

      // 4.1 Weicher Glow für hohe Ablesbarkeit
      final markerGlow = Paint()
        ..color = markerColor.withValues(alpha: 0.35)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(markerX, markerTop - 1.0),
        Offset(markerX, markerBottom + 1.0),
        markerGlow,
      );

      // 4.2 Präzise vertikale Haarlinie über den Schieberegler
      final markerLinePaint = Paint()
        ..color = markerColor
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(markerX, markerTop),
        Offset(markerX, markerBottom),
        markerLinePaint,
      );

      // 4.3 Nach oben zeigender Indikator-Pfeil unterhalb der Spur
      final arrowTipY = markerBottom + 1.5;
      final arrowBaseY = arrowTipY + 4.0;
      final arrowPath = Path()
        ..moveTo(markerX, arrowTipY)
        ..lineTo(markerX - 3.0, arrowBaseY)
        ..lineTo(markerX + 3.0, arrowBaseY)
        ..close();
      final arrowPaint = Paint()
        ..color = markerColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowPath, arrowPaint);

      // 4.4 Zeit-Badge unter dem Pfeil (z.B. "☼ 07:05" bzw. "☾ 16:34")
      final timeStr =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      final symbol = isSunrise ? '☼' : '☾';

      final labelPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$symbol ',
              style: TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.w900,
                color: markerColor,
              ),
            ),
            TextSpan(
              text: timeStr,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: markerColor,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final textX = (markerX - labelPainter.width / 2).clamp(
        trackLeft,
        trackRect.right - labelPainter.width,
      );
      labelPainter.paint(
        canvas,
        Offset(textX, arrowBaseY + 1.5),
      );
    }

    if (sunTimes.sunrise != null) {
      drawSunMarker(time: sunTimes.sunrise!, isSunrise: true);
    }
    if (sunTimes.sunset != null) {
      drawSunMarker(time: sunTimes.sunset!, isSunrise: false);
    }
  }
}

class _QuickTimeButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isMobile;

  const _QuickTimeButton({
    this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isMobile = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: isMobile ? 36 : 38),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 7.5 : 9.5,
          vertical: isMobile ? 6 : 6.5,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? WildlifeScoutTheme.emeraldBio
                : WildlifeScoutTheme.borderSubtle,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: isMobile ? 13 : 15,
                color: isSelected
                    ? WildlifeScoutTheme.emeraldBio
                    : WildlifeScoutTheme.textMuted,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: isMobile ? 11.5 : 12.5,
                fontWeight: FontWeight.w800,
                color: isSelected
                    ? WildlifeScoutTheme.emeraldBio
                    : WildlifeScoutTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable 40x40 Liquid Glass Button für die ergonomische Daumenzone (Apple HIG)
class _FieldFloatingButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isLoading;
  final Color? iconColor;
  final Color? badgeColor;
  final bool isActive;
  final Color? activeBorderColor;
  final Color? activeBgColor;

  const _FieldFloatingButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isLoading = false,
    this.iconColor,
    this.badgeColor,
    this.isActive = false,
    this.activeBorderColor,
    this.activeBgColor,
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isActive
                      ? (activeBgColor ??
                          WildlifeScoutTheme.surfaceCard.withValues(alpha: 0.85))
                      : WildlifeScoutTheme.surfaceCard.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: isActive
                        ? (activeBorderColor ?? WildlifeScoutTheme.emeraldBio)
                        : Colors.white.withValues(alpha: 0.14),
                    width: isActive ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isActive && activeBorderColor != null
                          ? activeBorderColor!.withValues(alpha: 0.35)
                          : Colors.black45,
                      blurRadius: isActive ? 8 : 6,
                      offset: const Offset(0, 2),
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
                          color: WildlifeScoutTheme.emeraldBio,
                        ),
                      )
                    else
                      Icon(
                        icon,
                        size: 19,
                        color: iconColor ?? WildlifeScoutTheme.textPrimary,
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

class _BestChanceFloatingButton extends StatelessWidget {
  final bool hasZones;
  final VoidCallback onTap;

  const _BestChanceFloatingButton({
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
                      WildlifeScoutTheme.amberGold.withValues(alpha: 0.32),
                      WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.90),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.75),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.stars_rounded,
                    color: WildlifeScoutTheme.amberGold,
                    size: 21,
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

class _FieldScanPulse extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const _FieldScanPulse({
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

    // 2. Konzentrische Distanzringe (38%, 68%, 100%)
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

/// Rückwärtskompatible Aliase
typedef TacticalMapScreen = FieldMapScreen;
typedef TacticalSliderTrackShape = FieldSliderTrackShape;
