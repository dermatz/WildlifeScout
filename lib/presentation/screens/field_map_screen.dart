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
import '../widgets/spot_vault_sheet.dart';
import '../widgets/field_overlay_builder.dart';
import '../widgets/score_explanation_sheet.dart';
import '../widgets/tactical_windy_weather_sheet.dart';
import '../widgets/wind_scent_compass_sheet.dart';
import '../widgets/field_map/best_chance_hud_card.dart';
import '../widgets/field_map/field_map_buttons.dart';
import '../widgets/field_map/field_scan_pulse.dart';
import '../widgets/field_map/field_slider_track_shape.dart';
import '../widgets/field_map/habitat_marker_widget.dart';
import '../widgets/field_map/modular_telemetry_card.dart';
import '../widgets/field_map/quick_time_button.dart';
import '../widgets/field_map/severe_weather_hud.dart';

export '../widgets/field_map/field_slider_track_shape.dart';

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
                    SevereWeatherHUDBanner(
                      alert: severeWeatherAlert,
                      onEndSession: () => setState(() => _isSessionActive = false),
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
                                child: BestChanceHUDCard(
                                  info: _bestChanceBannerInfo!,
                                  onClose: () {
                                    setState(() {
                                      _bestChanceBannerInfo = null;
                                      _bestChanceZoneId = null;
                                    });
                                  },
                                ),
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

    final tactical = _tacticalAssessmentForZone(
      zone: zone,
      zoneAssessment: zoneAssessment,
    );
    final chanceScore = tactical.situationalChanceScore;
    final chanceColor = _colorForChanceScore(chanceScore);
    final species = _speciesForId(zone.speciesId);
    final chanceRating = _ratingForChanceScore(chanceScore);

    return HabitatMarkerWidget(
      zone: zone,
      zoneAssessment: zoneAssessment,
      tactical: tactical,
      species: species,
      accentColor: accentColor,
      chanceScore: chanceScore,
      chanceColor: chanceColor,
      chanceRating: chanceRating,
      isSelected: isSelected,
      isBestChance: isBestChance,
      openDownward: openDownward,
      onSelect: () => setState(() => _selectedZoneInfo = zone),
      onClose: () => setState(() => _selectedZoneInfo = null),
      onShowExplanation: () => _showScoreExplanationSheet(
        zone: zone,
        zoneAssessment: zoneAssessment,
        chanceScore: chanceScore,
        tacticalAssessment: tactical,
      ),
      onOpenSpeciesInspector: (s) => _openSpeciesInspectorFor(s),
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
    final tactical = tacticalAssessment ??
        _tacticalAssessmentForZone(
          zone: zone,
          zoneAssessment: zoneAssessment,
        );
    final currentWeather = _hourlyForecast[_activeForecastIndex];

    ScoreExplanationSheet.show(
      context: context,
      zone: zone,
      zoneAssessment: zoneAssessment,
      chanceScore: chanceScore,
      tacticalAssessment: tactical,
      currentWeather: currentWeather,
      latitude: _hidePinPosition.latitude,
      longitude: _hidePinPosition.longitude,
      accentColor: accent,
      species: species,
      onOpenSpeciesInspector: (s) => _openSpeciesInspectorFor(s),
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
                DeckSevereWeatherCard(
                  alert: severeWeatherAlert,
                  onEndSession: () => setState(() => _isSessionActive = false),
                ),
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

typedef _ModularTelemetryCard = ModularTelemetryCard;
typedef _QuickTimeButton = QuickTimeButton;
typedef _FieldFloatingButton = FieldFloatingButton;
typedef _BestChanceFloatingButton = BestChanceFloatingButton;
typedef _FieldScanPulse = FieldScanPulse;

/// Rückwärtskompatible Aliase
typedef TacticalMapScreen = FieldMapScreen;
typedef TacticalSliderTrackShape = FieldSliderTrackShape;
