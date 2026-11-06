import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../core/privacy/coordinate_guard.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../data/api/gbif_occurrence_client.dart';
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
import '../widgets/field_map/field_scan_pulse.dart';
import '../widgets/field_map/field_slider_track_shape.dart';
import '../widgets/field_map/habitat_marker_widget.dart';
import '../widgets/field_map/hunting_stand_icon.dart';
import '../widgets/field_map/severe_weather_hud.dart';
import '../widgets/field_map/field_bottom_control_deck.dart';
import '../widgets/field_map/field_thumb_island.dart';
import '../widgets/field_map/field_top_bar.dart';
import '../widgets/field_map/telemetry_explainer_sheet.dart';

export '../widgets/field_map/field_slider_track_shape.dart';

typedef _ThumbCluster = ThumbCluster;

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
  bool _isDraggingPin = false;

  // 7-Tage Vorplanung (7 Tage x 24 Stunden = 168 Stunden)
  List<WeatherFrame> _hourlyForecast =
      OpenMeteoClient.buildOfflineFallbackForecast();
  int _selectedDayOffset = 0; // 0 = Heute, 1 = Morgen, ... bis 6
  int _selectedHourOfDay =
      DateTime.now().hour; // Standardmäßig aktuelle Stunde ("Jetzt")

  List<HabitatZone> _habitatZones = [];
  List<DisturbanceTrail> _disturbanceTrails = [];
  List<LatLng> _huntingStands = [];
  HabitatZone? _selectedZoneInfo;
  SoilSubstrateProfile? _currentSoilProfile;
  String _osmDataSourceStatus = 'Lade echte OpenStreetMap-Geometrien...';
  String? _bestChanceBannerInfo;
  String? _bestChanceZoneId;
  final Map<String, GbifRegionalPresence> _gbifPresenceBySpecies = {};

  // UI Toggles (hinter dem Karten-Elemente-Button gebündelt)
  bool _isNightVisionRedMode = false;
  bool _useSatelliteLayer = true;
  bool _showPlaceNames = true;
  bool _showRainRadarLayer = false;
  String? _rainRadarUrlTemplate;
  bool _showHabitatLayer = true;
  bool _showDisturbanceLayer = AppSettings.defaultShowDisturbanceLayer;
  bool _showHuntingStandsLayer = true;
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
      _huntingStands = immediate.huntingStands;
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
        _huntingStands = liveResult.huntingStands;
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
    _refreshGbifForPosition(pos);
    final frames = await _weatherClient.fetchHourlyForecast(
      latitude: pos.latitude,
      longitude: pos.longitude,
    );
    if (!mounted) return;
    setState(() {
      _hourlyForecast = frames;
    });
  }

  Future<void> _refreshGbifForPosition(LatLng pos) async {
    final primary = _primarySpecies;
    if (primary == null || primary.scientificName.isEmpty) return;
    try {
      final presence = await GbifOccurrenceClient.fetchRegionalPresence(
        latitude: pos.latitude,
        longitude: pos.longitude,
        scientificName: primary.scientificName,
      );
      if (!mounted) return;
      setState(() {
        _gbifPresenceBySpecies[primary.id] = presence;
      });
    } catch (_) {}
  }

  void _onMapTapped(TapPosition tapPosition, LatLng point) {
    const dist = Distance();
    final metersFromLastScan = dist.as(
      LengthUnit.Meter,
      _territoryOrigin,
      point,
    );

    // Liegt der getippte Punkt innerhalb des eben berechneten Sektors (~1.200 m Radius)
    // und wurden bereits Habitate ermittelt, verschieben wir nur den Ansitzmarker und
    // aktualisieren Witterungskegel & Windbeurteilung lokal – OHNE einen zeitraubenden
    // Neuscan auszulösen. Erst ein Antippen des Ansitzmarkers scannt gezielt neu.
    final bool isInsideCalculatedTerritory =
        _habitatZones.isNotEmpty && metersFromLastScan <= 1200.0;

    setState(() {
      _hidePinPosition = point;
      _selectedZoneInfo = null;
      _bestChanceBannerInfo = null;
      _bestChanceZoneId = null;
      _activeThumbCluster = _ThumbCluster.none;
    });

    DeviceLocationService.saveLastLocation(point, _currentRegionTitle);

    if (!isInsideCalculatedTerritory) {
      _recalculateHabitatZones(point);
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
            huntingStandCount: _huntingStands.length,
            useSatelliteLayer: _useSatelliteLayer,
            showHabitatLayer: _showHabitatLayer,
            showDisturbanceLayer: _showDisturbanceLayer,
            showHuntingStandsLayer: _showHuntingStandsLayer,
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
            onChangedHuntingStands: (val) {
              setState(() => _showHuntingStandsLayer = val);
              setSheetState(() {});
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
    TelemetryExplainerSheet.show(
      context: context,
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      points: points,
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
        biasCoordinate: _hidePinPosition,
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

  void _resetMapRotationToNorth() {
    HapticFeedback.mediumImpact();
    double currentZoom = 14.5;
    try {
      currentZoom = _mapController.camera.zoom;
    } catch (_) {}
    _mapController.moveAndRotate(_hidePinPosition, currentZoom, 0.0);
    setState(() {});
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
      gbifPresence: _gbifPresenceBySpecies[species.id],
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
        gbifPresence: _gbifPresenceBySpecies[primary.id],
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
      huntingStands: _huntingStands,
      showHuntingStands: _showHuntingStandsLayer,
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
              // 0b. OSM Hochsitze & Jägerstände (amenity=hunting_stand)
              if (_showHuntingStandsLayer && _huntingStands.isNotEmpty)
                MarkerLayer(
                  rotate: false,
                  markers: _huntingStands.map((stand) {
                    final distToHide = const Distance().as(
                      LengthUnit.Meter,
                      _hidePinPosition,
                      stand,
                    );
                    // Rote Warnstufe bei Gefahrenbereich (<= 200 m, typische Büchsen-Schussdistanz)
                    final isDangerClose = distToHide <= 200.0;
                    return Marker(
                      point: stand,
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      child: Tooltip(
                        message: 'Hochsitz / Jägerstand (${distToHide.round()}m entfernt)',
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Hochsitz in ${distToHide.round()}m Entfernung • Bewährter Wechsel / Ansitzbereich',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                duration: const Duration(seconds: 3),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: WildlifeScoutTheme.surfaceGlass,
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDangerClose
                                  ? const Color(0xFFDC2626).withValues(alpha: 0.95)
                                  : const Color(0xFF1E293B).withValues(alpha: 0.85),
                              border: Border.all(
                                color: isDangerClose
                                    ? Colors.white
                                    : const Color(0xFF94A3B8),
                                width: isDangerClose ? 1.8 : 1.1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(3.5),
                            child: Center(
                              child: HuntingStandIcon(
                                size: 13,
                                color: isDangerClose
                                    ? Colors.white
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
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
                              child: FieldScanPulse(
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
                        // Exakt zentrierter Fotospot-Pin (Scan-Button & frei verschiebbar)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            if (_isLoadingOsm) return;
                            _recalculateHabitatZones(_hidePinPosition);
                            _refreshWeatherForPosition(_hidePinPosition);
                          },
                          onPanStart: (_) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isDraggingPin = true;
                            });
                          },
                          onPanUpdate: (details) {
                            final currentOffset = _mapController.camera
                                .latLngToScreenOffset(_hidePinPosition);
                            final newOffset = currentOffset + details.delta;
                            final newLatLng = _mapController.camera
                                .screenOffsetToLatLng(newOffset);
                            setState(() {
                              _hidePinPosition = newLatLng;
                              _selectedZoneInfo = null;
                              _bestChanceBannerInfo = null;
                              _bestChanceZoneId = null;
                            });
                          },
                          onPanEnd: (_) {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _isDraggingPin = false;
                            });
                            DeviceLocationService.saveLastLocation(
                              _hidePinPosition,
                              _currentRegionTitle,
                            );
                          },
                          onPanCancel: () {
                            if (_isDraggingPin) {
                              setState(() {
                                _isDraggingPin = false;
                              });
                            }
                          },
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 140),
                            scale: _isDraggingPin ? 1.18 : 1.0,
                            child: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              color: Colors.transparent,
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
                                          ? WildlifeScoutTheme.emeraldBio
                                              .withValues(alpha: 0.55)
                                          : (severeWeatherAlert != null
                                              ? severeWeatherAlert.accentColor
                                                  .withValues(alpha: 0.6)
                                              : (_isDraggingPin
                                                  ? WildlifeScoutTheme.amberGold
                                                      .withValues(alpha: 0.45)
                                                  : Colors.black87)),
                                      blurRadius: (_isLoadingOsm || _isLocatingUser)
                                          ? 14
                                          : (_isDraggingPin
                                              ? 12
                                              : (severeWeatherAlert != null
                                                  ? 12
                                                  : 8)),
                                    ),
                                  ],
                                ),
                                child: (_isLoadingOsm || _isLocatingUser)
                                    ? RotationTransition(
                                        turns: _radarController,
                                        child: const Icon(
                                          Icons.radar_rounded,
                                          size: 17,
                                          color: WildlifeScoutTheme.emeraldBio,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.radar_rounded,
                                        size: 17,
                                        color: Colors.white,
                                      ),
                              ),
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
                  FieldTopBar(
                    primarySpecies: activeSpecies,
                    selectedSpeciesCount: _selectedSpeciesIds.length,
                    currentRegionTitle: _currentRegionTitle,
                    habitatZoneCount: _habitatZones.length,
                    osmDataSourceStatus: _osmDataSourceStatus,
                    isLoadingOsm: _isLoadingOsm,
                    isLocatingUser: _isLocatingUser,
                    radarAnimation: _radarController,
                    severeWeatherAlert: severeWeatherAlert,
                    onSpeciesSelectTap: _openSpeciesMultiSelectSheet,
                    onSettingsTap: _openSettingsSheet,
                    onEndSevereWeatherSession: () =>
                        setState(() => _isSessionActive = false),
                  ),
                  if (_isSessionActive && severeWeatherAlert != null) ...[
                    const SizedBox(height: 8),
                    SevereWeatherHUDBanner(
                      alert: severeWeatherAlert,
                      onEndSession: () => setState(() => _isSessionActive = false),
                    ),
                  ],
                  // Schwebender Nordpfeil-Kompass-Button direkt unter der TopBar, wenn Karte gedreht ist (Apple Maps / Google Maps UX)
                  if ((mapRotation % 360).abs() > 1.0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Tooltip(
                          message: 'Karte nach Norden ausrichten & zentrieren',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(13),
                              onTap: _resetMapRotationToNorth,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: WildlifeScoutTheme.surfaceCard
                                          .withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                        color: WildlifeScoutTheme.crimsonScent
                                            .withValues(alpha: 0.5),
                                        width: 1.2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Transform.rotate(
                                        // Der Pfeil zeigt immer zum echten Norden
                                        angle: -mapRotation * (3.141592653589793 / 180.0),
                                        child: const Icon(
                                          Icons.navigation_rounded,
                                          size: 22,
                                          color: WildlifeScoutTheme.crimsonScent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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
            child: FieldThumbIsland(
              activeCluster: _activeThumbCluster,
              onClusterChanged: (c) => setState(() => _activeThumbCluster = c),
              hasHabitatZones: _habitatZones.isNotEmpty,
              savedSpotCount: _savedSpots.length,
              isLocatingUser: _isLocatingUser,
              isNightVisionRedMode: _isNightVisionRedMode,
              showRainRadarLayer: _showRainRadarLayer,
              useSatelliteLayer: _useSatelliteLayer,
              currentWeather: currentWeather,
              effectiveFocalLengthMm: _currentPhotoGear.effectiveFocalLengthMm,
              mapRotation: mapRotation,
              onResetNorth: _resetMapRotationToNorth,
              onApplyBestChance: _applyBestChanceOpportunity,
              onOpenLayers: _openMapLayersSheet,
              onOpenSpotVault: () => _openSpotVaultSheet(currentWeather),
              onOpenLocationSearch: _openLocationSearchSheet,
              onLocateUser: _locateAndMoveToCurrentPosition,
              onOpenPhotoGear: () {
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
                      // Subtiler Jagd-/Hochsitz-Hinweis unten links über der Control Deck Leiste
                      if (_isSessionActive && _huntingStands.isNotEmpty) ...[
                        () {
                          const distance = Distance();
                          double nearestDist = double.infinity;
                          for (final stand in _huntingStands) {
                            final d = distance.as(
                              LengthUnit.Meter,
                              _hidePinPosition,
                              stand,
                            );
                            if (d < nearestDist) nearestDist = d;
                          }
                          final inHuntingStandZone = nearestDist <= 350.0;
                          // Zu nah = Gefahrenbereich / Schussdistanz (<= 200 m)
                          final isImmediateHuntingStand = nearestDist <= 200.0;

                          if (!inHuntingStandZone) return const SizedBox.shrink();

                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6, left: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isImmediateHuntingStand
                                      ? const Color(0xFFDC2626).withValues(alpha: 0.95)
                                      : const Color(0xFF1E293B).withValues(alpha: 0.90),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isImmediateHuntingStand
                                        ? const Color(0xFFFCA5A5)
                                        : const Color(0xFFF59E0B).withValues(alpha: 0.8),
                                    width: isImmediateHuntingStand ? 1.4 : 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    HuntingStandIcon(
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isImmediateHuntingStand
                                          ? 'Achtung: Hochsitz in ${nearestDist.round()}m! Jagdbetrieb möglich'
                                          : 'Hochsitz-Areal (${nearestDist.round()}m) • Auf Jäger/Schussfeld achten',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }(),
                      ],
                      if (isMobile && _appSettings.showHudCompassTape) ...[
                        HudCompassTape(
                          currentWeather: currentWeather,
                          initialHeading: _deviceHeading,
                          onTap: _openWindCompassSheet,
                        ),
                        const SizedBox(height: 6),
                      ],
                      FieldBottomControlDeck(
                        species: activeSpecies,
                        weather: currentWeather,
                        astro: astro,
                        assessment: assessment,
                        severeWeatherAlert: severeWeatherAlert,
                        selectedDayOffset: _selectedDayOffset,
                        selectedHourOfDay: _selectedHourOfDay,
                        hourlyForecast: _hourlyForecast,
                        isDeckExpanded: _isDeckExpanded,
                        isSessionActive: _isSessionActive,
                        latitude: _hidePinPosition.latitude,
                        longitude: _hidePinPosition.longitude,
                        onToggleExpanded: () =>
                            setState(() => _isDeckExpanded = !_isDeckExpanded),
                        onHourChanged: (newHour) =>
                            setState(() => _selectedHourOfDay = newHour),
                        onDayOffsetChanged: (newDay) =>
                            setState(() => _selectedDayOffset = newDay),
                        onEndSevereWeatherSession: () =>
                            setState(() => _isSessionActive = false),
                        onOpenWindCompass: _openWindCompassSheet,
                        onOpenTacticalWindy: (mode) => _openTacticalWindySheet(
                          initialMode: mode,
                        ),
                        onShowTelemetryExplainer: ({
                          required title,
                          required subtitle,
                          required icon,
                          required iconColor,
                          required points,
                        }) =>
                            _showTelemetryExplainerSheet(
                          title: title,
                          subtitle: subtitle,
                          icon: icon,
                          iconColor: iconColor,
                          points: points,
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
    );

    if (_isNightVisionRedMode) {
      return ColorFiltered(
        colorFilter: WildlifeScoutTheme.nightVisionRedMatrix,
        child: mainContent,
      );
    }

    return mainContent;
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
}

/// Rückwärtskompatible Aliase
typedef TacticalMapScreen = FieldMapScreen;
typedef TacticalSliderTrackShape = FieldSliderTrackShape;
