import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/privacy/coordinate_guard.dart';
import '../../core/theme/wildscout_theme.dart';
import '../../data/api/location_search_client.dart';
import '../../data/api/open_meteo_client.dart';
import '../../data/repositories/species_repository.dart';
import '../../data/repositories/spot_vault_repository.dart';
import '../../data/services/device_location_service.dart';
import '../../domain/models/habitat_zone.dart';
import '../../domain/models/secret_spot.dart';
import '../../domain/models/soil_substrate_profile.dart';
import '../../domain/models/species_profile.dart';
import '../../domain/models/weather_frame.dart';
import '../../domain/services/activity_score_calculator.dart';
import '../../domain/services/habitat_suitability_engine.dart';
import '../../domain/services/sun_moon_calculator.dart';
import '../widgets/location_search_sheet.dart';
import '../widgets/map_layers_sheet.dart';
import '../widgets/species_inspector_sheet.dart';
import '../widgets/species_multiselect_sheet.dart';
import '../widgets/species_photo_avatar.dart';
import '../widgets/spot_vault_sheet.dart';
import '../widgets/tactical_overlay_builder.dart';

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
  int _selectedHourOfDay = 6; // 06:00 Uhr Morgenansitz

  List<HabitatZone> _habitatZones = [];
  List<DisturbanceTrail> _disturbanceTrails = [];
  HabitatZone? _selectedZoneInfo;
  SoilSubstrateProfile? _currentSoilProfile;
  String _osmDataSourceStatus = 'Lade echte OpenStreetMap-Geometrien...';

  // UI Toggles (hinter dem Karten-Elemente-Button gebündelt)
  bool _isNightVisionRedMode = false;
  bool _useSatelliteLayer = true;
  bool _showHabitatLayer = true;
  bool _showDisturbanceLayer = true;
  bool _showScentCone = true;
  bool _isLoadingOsm = false;

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
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1850),
    )..repeat();
    _initializeAppData();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _initializeAppData() async {
    final loadedSpecies = await _speciesRepo.loadAllSpecies();
    final spots = await _vaultRepo.loadSpots();
    final lastSaved = await DeviceLocationService.loadLastSavedLocation();

    if (!mounted) return;
    setState(() {
      _speciesList = loadedSpecies;
      _selectedSpeciesIds = {'roe_deer'};
      _savedSpots = spots;
      if (lastSaved != null) {
        _territoryOrigin = lastSaved.coordinate;
        _hidePinPosition = lastSaved.coordinate;
        _currentRegionTitle = lastSaved.label ?? 'Aktueller Standort';
      }
    });

    if (lastSaved != null) {
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

  String _dayLabelForOffset(int dayOffset) {
    final date = DateTime.now().add(Duration(days: dayOffset));
    if (dayOffset == 0) return 'Heute';
    if (dayOffset == 1) return 'Morgen';
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final wd = weekdays[(date.weekday - 1) % 7];
    return '$wd ${date.day}.${date.month}.';
  }

  @override
  Widget build(BuildContext context) {
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
            ),
            children: [
              TileLayer(
                urlTemplate: _useSatelliteLayer
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'dev.wildlifescout.app',
              ),
              Container(
                color: Colors.black.withValues(
                  alpha: _useSatelliteLayer ? 0.16 : 0.34,
                ),
              ),
              PolylineLayer(polylines: polylines),
              PolygonLayer(polygons: polygons),
              // Echte OSM Habitat-Hotspot-Pins zum Antippen (hochkontrastige, lesbare Taktik-Pills)
              if (_showHabitatLayer)
                MarkerLayer(
                  markers: _habitatZones
                      .map(
                        (zone) => Marker(
                          point: zone.center,
                          width: 260,
                          height: 44,
                          alignment: Alignment.center,
                          child: _buildHabitatMarker(zone),
                        ),
                      )
                      .toList(),
                ),
              // Tarnzelt / Ansitz-Pin des Fotografen + Taktischer Radar-Sweep beim Scannen
              MarkerLayer(
                markers: [
                  Marker(
                    point: _hidePinPosition,
                    width: 240,
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
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
                        // ANSITZ / SCANNT Badge direkt über dem runden Pin
                        Positioned(
                          top: 240 / 2 - 17 - 22,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (_isLoadingOsm || _isLocatingUser)
                                  ? WildScoutTheme.emeraldBio
                                  : (assessment.hasScentCollision
                                      ? WildScoutTheme.crimsonScent
                                      : WildScoutTheme.emeraldBio),
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
                                  : 'ANSITZ',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ),
                        // Exakt zentrierter Ansitz-Pin
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: WildScoutTheme.bgObsidian,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: (_isLoadingOsm || _isLocatingUser)
                                  ? WildScoutTheme.emeraldBio
                                  : (assessment.hasScentCollision
                                      ? WildScoutTheme.crimsonScent
                                      : WildScoutTheme.amberGold),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isLoadingOsm || _isLocatingUser)
                                    ? WildScoutTheme.emeraldBio.withValues(
                                        alpha: 0.55,
                                      )
                                    : Colors.black87,
                                blurRadius:
                                    (_isLoadingOsm || _isLocatingUser) ? 14 : 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt_outlined,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Aufgeräumtes Top Tactical HUD (nur noch EINE kompakte Leiste!)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(activeSpecies, currentWeather),
                  if (_selectedZoneInfo != null) ...[
                    const SizedBox(height: 10),
                    _buildZoneInfoCard(_selectedZoneInfo!),
                  ],
                ],
              ),
            ),
          ),

          // 3. Bottom Thumb-Zone Tactical Control Deck (inkl. 7-Tage-Vorplanung)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: _buildBottomTacticalDeck(
                  species: activeSpecies,
                  weather: currentWeather,
                  astro: astro,
                  assessment: assessment,
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

  Widget _buildTopBar(SpeciesProfile primarySpecies, WeatherFrame currentWeather) {
    final extraCount = _selectedSpeciesIds.length - 1;
    final speciesButtonLabel = extraCount > 0
        ? '${primarySpecies.name} +$extraCount'
        : primarySpecies.name;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: WildScoutTheme.surfaceGlass,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: WildScoutTheme.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [WildScoutTheme.emeraldBio, Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: RotationTransition(
                  turns: (_isLoadingOsm || _isLocatingUser)
                      ? _radarController
                      : const AlwaysStoppedAnimation(0.0),
                  child: const Icon(
                    Icons.radar,
                    color: Colors.black,
                    size: 19,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WILDLIFESCOUT',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      _isLoadingOsm
                          ? 'Scanne echte OpenStreetMap-Polygone...'
                          : '$_currentRegionTitle • $_osmDataSourceStatus',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: WildScoutTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // 1. Kompakter Button: Tier-Auswahl (Fokus: Rehwild + Multi-Select + Lizenzfreies Unsplash-Foto)
              Tooltip(
                message: 'Wildarten, Verhalten & Praxis-Tipps öffnen',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _openSpeciesMultiSelectSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: primarySpecies.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: primarySpecies.accentColor.withValues(alpha: 0.65),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SpeciesPhotoAvatar(
                          species: primarySpecies,
                          width: 24,
                          height: 24,
                          borderRadius: 7,
                          borderWidth: 1.2,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          speciesButtonLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: WildScoutTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          size: 15,
                          color: WildScoutTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 2. Kompakter Button: Karten-Elemente & Ebenen
              Tooltip(
                message: 'Karten-Elemente, Störwege & Basiskarte einstellen',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _openMapLayersSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: WildScoutTheme.cyanWater.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: WildScoutTheme.cyanWater.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          size: 15,
                          color: WildScoutTheme.cyanWater,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Karten-Ebenen',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: WildScoutTheme.textPrimary,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 15,
                          color: WildScoutTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 3. Kompakter Button: Aktueller Standort (GPS)
              Tooltip(
                message: 'Zum aktuellen Standort springen',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _locateAndMoveToCurrentPosition(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WildScoutTheme.borderSubtle),
                    ),
                    child: _isLocatingUser
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: WildScoutTheme.emeraldBio,
                            ),
                          )
                        : const Icon(
                            Icons.my_location,
                            size: 17,
                            color: WildScoutTheme.emeraldBio,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 4. Kompakter Button: Ort / Gebiet suchen
              Tooltip(
                message: 'Ort, Waldgebiet oder GPS-Koordinate suchen',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _openLocationSearchSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WildScoutTheme.borderSubtle),
                    ),
                    child: const Icon(
                      Icons.search,
                      size: 17,
                      color: WildScoutTheme.emeraldBio,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 5. Kompakter Button: Geheimer Spot-Tresor
              Tooltip(
                message: 'Geheimer Spot-Tresor (100% Lokal)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openSpotVaultSheet(currentWeather),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: WildScoutTheme.amberGold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: WildScoutTheme.amberGold.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bookmark_border,
                          size: 16,
                          color: WildScoutTheme.amberGold,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${_savedSpots.length}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: WildScoutTheme.amberGold,
                          ),
                        ),
                      ],
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

  Widget _buildHabitatMarker(HabitatZone zone) {
    final isSelected = _selectedZoneInfo?.id == zone.id;
    final accentColor = zone.type == HabitatZoneType.waterSuhle
        ? WildScoutTheme.cyanWater
        : _accentForSpeciesId(zone.speciesId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedZoneInfo = zone),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 250),
          padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
          decoration: BoxDecoration(
            color: WildScoutTheme.bgObsidian.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.white : accentColor,
              width: isSelected ? 2.0 : 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              if (isSelected)
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.55),
                  blurRadius: 14,
                  spreadRadius: 1.5,
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Runder / abgerundeter Prozent-Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.5,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.6),
                    width: 0.9,
                  ),
                ),
                child: Text(
                  '${zone.suitabilityScore.round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: accentColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  zone.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoneInfoCard(HabitatZone zone) {
    final accent = _accentForSpeciesId(zone.speciesId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: WildScoutTheme.bgObsidian.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${zone.suitabilityScore.round()}% ${zone.speciesName}',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zone.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  zone.subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: WildScoutTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _selectedZoneInfo = null),
            visualDensity: VisualDensity.compact,
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
        '⚡ Fällt (${delta.toStringAsFixed(1)})',
      );
    } else if (delta <= -0.7) {
      return (
        Icons.trending_down_rounded,
        WildScoutTheme.amberGold,
        valStr,
        'Fällt (${delta.toStringAsFixed(1)})',
      );
    } else if (delta >= 1.5) {
      return (
        Icons.trending_up_rounded,
        WildScoutTheme.cyanWater,
        valStr,
        'Steigt (+${delta.toStringAsFixed(1)})',
      );
    } else {
      return (
        Icons.trending_flat_rounded,
        WildScoutTheme.textMuted,
        valStr,
        'Stabil',
      );
    }
  }

  (IconData icon, Color color, String val, String detail) _getAstroTelemetry(
    SunMoonPosition astro,
  ) {
    if (astro.isGoldenHour) {
      return (
        Icons.wb_twilight_rounded,
        WildScoutTheme.amberGold,
        'Goldene Std.',
        '${astro.sunElevationDegrees.toStringAsFixed(0)}° Streiflicht',
      );
    } else if (astro.isBlueHour) {
      return (
        Icons.wb_twilight_rounded,
        WildScoutTheme.cyanWater,
        'Blaue Std.',
        'Dämmerung',
      );
    } else if (astro.currentPeriod == ActivityPeriod.night) {
      return (
        Icons.nightlight_round,
        const Color(0xFFC7D2FE),
        '${(astro.moonIlluminationFraction * 100).round()}% Mond',
        'Nacht',
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

  Widget _buildBottomTacticalDeck({
    required SpeciesProfile species,
    required WeatherFrame weather,
    required SunMoonPosition astro,
    required TacticalAssessment assessment,
  }) {
    final dayLabel = _dayLabelForOffset(_selectedDayOffset);
    final hourStr =
        '${_selectedHourOfDay.toString().padLeft(2, '0')}:00 Uhr';

    final scoreColor = assessment.activityScorePercent >= 78
        ? WildScoutTheme.emeraldBio
        : (assessment.activityScorePercent >= 55
            ? WildScoutTheme.amberGold
            : WildScoutTheme.textMuted);

    final baroInfo = _getBarometerTelemetry(weather);
    final astroInfo = _getAstroTelemetry(astro);
    final skyInfo = _getSkyTelemetry(weather, astro);
    final windInfo = _getWindTelemetry(weather);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: WildScoutTheme.surfaceGlass,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: assessment.hasScentCollision
                  ? WildScoutTheme.crimsonScent.withValues(alpha: 0.85)
                  : WildScoutTheme.borderSubtle,
              width: assessment.hasScentCollision ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 7-Tage Vorplanungs-Leiste mit Mini-Wetter-Icons
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 7,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, dayIdx) {
                    final isSelected = dayIdx == _selectedDayOffset;
                    final forecastIdx = (dayIdx * 24 + 12).clamp(
                      0,
                      _hourlyForecast.isEmpty ? 0 : _hourlyForecast.length - 1,
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

                    return GestureDetector(
                      onTap: () => setState(() => _selectedDayOffset = dayIdx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? WildScoutTheme.emeraldBio.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? WildScoutTheme.emeraldBio
                                : WildScoutTheme.borderSubtle,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _dayLabelForOffset(dayIdx),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? WildScoutTheme.emeraldBio
                                    : WildScoutTheme.textMuted,
                              ),
                            ),
                            if (dayWeather != null && dayIcon != null) ...[
                              const SizedBox(width: 5),
                              Icon(
                                dayIcon,
                                size: 12,
                                color: isSelected
                                    ? WildScoutTheme.emeraldBio
                                    : dayIconColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${dayWeather.temperatureCelsius.round()}°',
                                style: TextStyle(
                                  fontSize: 10.5,
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

              // 2. Live Witterungs-Status Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: assessment.hasScentCollision
                      ? WildScoutTheme.crimsonScent.withValues(alpha: 0.22)
                      : WildScoutTheme.emeraldBio.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: assessment.hasScentCollision
                        ? WildScoutTheme.crimsonScent.withValues(alpha: 0.6)
                        : WildScoutTheme.emeraldBio.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      assessment.hasScentCollision
                          ? Icons.warning_amber_rounded
                          : (weather.windSpeedKmh < 4.0
                              ? Icons.air_rounded
                              : Icons.check_circle_outline),
                      size: 18,
                      color: assessment.hasScentCollision
                          ? WildScoutTheme.crimsonScent
                          : WildScoutTheme.emeraldBio,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        assessment.windTacticalAdvice,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: assessment.hasScentCollision
                              ? const Color(0xFFFFB4C0)
                              : WildScoutTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 3. Aktivitäts-Score + Icon-gestützte Wetter-Telemetrie (schnelle visuelle Erfassung)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scoreColor.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${assessment.activityScorePercent}%',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                          ),
                        ),
                        const Text(
                          'AKTIVITÄT',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: WildScoutTheme.textMuted,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
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
                              '$dayLabel, $hourStr (${species.name})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scoreColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: scoreColor.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                assessment.ratingLabel,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: scoreColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: [
                            Tooltip(
                              message: assessment.barometerInsight,
                              child: _WeatherTelemetryChip(
                                icon: baroInfo.$1,
                                iconColor: baroInfo.$2,
                                label: baroInfo.$3,
                                detail: baroInfo.$4,
                                detailColor: baroInfo.$2,
                              ),
                            ),
                            Tooltip(
                              message: assessment.lightQualityAdvice,
                              child: _WeatherTelemetryChip(
                                icon: astroInfo.$1,
                                iconColor: astroInfo.$2,
                                label: astroInfo.$3,
                                detail: astroInfo.$4,
                              ),
                            ),
                            Tooltip(
                              message: weather.precipitationMm > 0
                                  ? '${weather.precipitationMm.toStringAsFixed(1)} mm Niederschlag'
                                  : '${weather.cloudCoverPercent}% Wolkenbedeckung',
                              child: _WeatherTelemetryChip(
                                icon: skyInfo.$1,
                                iconColor: skyInfo.$2,
                                label: skyInfo.$3,
                                detail: skyInfo.$4,
                              ),
                            ),
                            Tooltip(
                              message: assessment.windTacticalAdvice,
                              child: _WeatherTelemetryChip(
                                icon: windInfo.$1,
                                iconColor: windInfo.$2,
                                label: windInfo.$3,
                                detail: windInfo.$4,
                                detailColor: windInfo.$2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 4. Zeitschieberegler (Time-Scrubber mit Icon-unterstütztem Wetter-Badge)
              Row(
                children: [
                  _QuickTimeButton(
                    icon: Icons.wb_twilight_rounded,
                    label: '06:00',
                    isSelected: _selectedHourOfDay == 6,
                    onTap: () => setState(() => _selectedHourOfDay = 6),
                  ),
                  const SizedBox(width: 6),
                  _QuickTimeButton(
                    icon: Icons.nightlight_round,
                    label: '18:00',
                    isSelected: _selectedHourOfDay == 18,
                    onTap: () => setState(() => _selectedHourOfDay = 18),
                  ),
                  Expanded(
                    child: Slider(
                      value: _selectedHourOfDay.toDouble(),
                      min: 0,
                      max: 23,
                      divisions: 23,
                      label: hourStr,
                      onChanged: (val) {
                        setState(() {
                          _selectedHourOfDay = val.round();
                        });
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
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
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Container(
                          width: 1,
                          height: 11,
                          color: WildScoutTheme.borderSubtle,
                        ),
                        const SizedBox(width: 7),
                        const Icon(
                          Icons.air_rounded,
                          size: 13,
                          color: WildScoutTheme.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${weather.windSpeedKmh.round()} km/h',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Transform.rotate(
                          angle: weather.scentBlowDirectionDegrees *
                              (math.pi / 180.0),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherTelemetryChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? detail;
  final Color? detailColor;

  const _WeatherTelemetryChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.detail,
    this.detailColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: detailColor != null && detailColor != WildScoutTheme.textMuted
              ? detailColor!.withValues(alpha: 0.4)
              : WildScoutTheme.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: iconColor),
          const SizedBox(width: 4.5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: WildScoutTheme.textPrimary,
            ),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              detail!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: detailColor ?? WildScoutTheme.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? WildScoutTheme.amberGold.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? WildScoutTheme.amberGold
                : WildScoutTheme.borderSubtle,
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
                    ? WildScoutTheme.amberGold
                    : WildScoutTheme.amberGold.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? WildScoutTheme.amberGold
                    : WildScoutTheme.textPrimary,
              ),
            ),
          ],
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
