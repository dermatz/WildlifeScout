import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../data/api/location_search_client.dart';
import '../../data/services/app_settings_service.dart';
import '../../data/services/nearby_nature_regions_service.dart';
import '../../data/services/voice_search_service.dart';

class LocationSearchSheet extends StatefulWidget {
  final ValueChanged<LocationSearchResult> onLocationSelected;
  final VoidCallback onUseCurrentLocation;
  final LatLng? biasCoordinate;
  final VoiceSearchService? voiceSearchService;

  const LocationSearchSheet({
    super.key,
    required this.onLocationSelected,
    required this.onUseCurrentLocation,
    this.biasCoordinate,
    this.voiceSearchService,
  });

  @override
  State<LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<LocationSearchSheet> {
  final LocationSearchClient _client = LocationSearchClient();
  final TextEditingController _searchCtrl = TextEditingController();
  late final VoiceSearchService _voice;
  List<LocationSearchResult> _results = const [];
  List<NearbyNatureRegionEntry> _nearbyRegions = const [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _voiceErrorMessage;

  @override
  void initState() {
    super.initState();
    _voice = widget.voiceSearchService ?? VoiceSearchService.shared;
    _loadNearbyRegions();
  }

  void _loadNearbyRegions() {
    final center = widget.biasCoordinate ?? const LatLng(52.5200, 13.4050);
    final radius = AppSettingsService.searchRadiusNotifier.value;
    setState(() {
      _nearbyRegions = NearbyNatureRegionsService.findNearby(
        userCoordinate: center,
        maxRadiusKm: radius,
        limit: 8,
      );
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _hasSearched = false;
      });
      return;
    }

    // Sofortige Auswertung, falls es direkte Koordinaten sind
    final direct = _client.parseDirectCoordinates(trimmed);
    if (direct != null) {
      setState(() {
        _results = [
          LocationSearchResult(
            title: 'Direkte GPS-Koordinate',
            subtitle:
                '${direct.latitude.toStringAsFixed(5)}, ${direct.longitude.toStringAsFixed(5)}',
            coordinate: direct,
            categoryLabel: 'GPS-Direkt',
          ),
        ];
        _hasSearched = true;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    final res = await _client.search(trimmed);
    if (!mounted) return;
    setState(() {
      _results = res;
      _isSearching = false;
    });
  }

  void _onQueryChanged(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _hasSearched = false;
      });
      return;
    }

    final direct = _client.parseDirectCoordinates(trimmed);
    if (direct != null) {
      setState(() {
        _results = [
          LocationSearchResult(
            title: 'Direkte GPS-Koordinate',
            subtitle:
                '${direct.latitude.toStringAsFixed(5)}, ${direct.longitude.toStringAsFixed(5)}',
            coordinate: direct,
            categoryLabel: 'GPS-Direkt',
          ),
        ];
        _hasSearched = true;
      });
    }
  }

  Future<void> _startVoiceInput() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _voiceErrorMessage = null;
    });

    final ok = await _voice.initialize(
      onError: (msg) {
        if (mounted) {
          setState(() {
            _voiceErrorMessage = msg;
          });
        }
      },
    );

    if (!ok) {
      if (mounted) {
        setState(() {
          _voiceErrorMessage =
              _voice.lastError ?? 'Mikrofon-Berechtigung verweigert oder Dienst nicht verfügbar.';
        });
      }
      return;
    }

    await _voice.startListening(
      onResult: (spokenText) {
        if (!mounted) return;
        _searchCtrl.text = spokenText;
        _performSearch(spokenText);
      },
      onError: (msg) {
        if (mounted) {
          setState(() {
            _voiceErrorMessage = msg;
          });
        }
      },
      onListeningFinished: () {
        if (mounted) {
          setState(() {});
        }
      },
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _stopVoiceInput() async {
    HapticFeedback.lightImpact();
    await _voice.stopListening();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildlifeScoutTheme.borderSubtle, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.travel_explore,
                  color: WildlifeScoutTheme.emeraldBio,
                  size: 24,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ort, Wald oder Naturgebiet suchen',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Gib einen Ortsnamen, ein Waldgebiet oder GPS-Koordinaten ein',
                        style: TextStyle(
                          fontSize: 12,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onUseCurrentLocation();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: WildlifeScoutTheme.emeraldBio,
                  side: BorderSide(
                    color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.6),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text(
                  'Eigenen GPS-Standort laden',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Voice error banner
            if (_voiceErrorMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _voiceErrorMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WildlifeScoutTheme.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _startVoiceInput,
                      child: const Text('Erneut', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),
            ],

            // Voice listening active banner
            if (_voice.isListening) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.graphic_eq_rounded,
                      color: WildlifeScoutTheme.emeraldBio,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Ich höre zu... Sprich jetzt (z. B. "Schwarzwald" oder "Harz")',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: WildlifeScoutTheme.emeraldBio,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Aufnahme beenden',
                      child: TextButton(
                        onPressed: _stopVoiceInput,
                        child: const Text(
                          'Fertig',
                          style: TextStyle(
                            color: WildlifeScoutTheme.emeraldBio,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            TextField(
              controller: _searchCtrl,
              autofocus: false,
              textInputAction: TextInputAction.search,
              onSubmitted: _performSearch,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Ort, Waldgebiet oder GPS-Koordinaten eingeben...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: WildlifeScoutTheme.emeraldBio,
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Eingabe löschen',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _results = const [];
                            _hasSearched = false;
                          });
                        },
                      ),
                    Tooltip(
                      message: 'Per Sprache suchen',
                      child: IconButton(
                        icon: Icon(
                          _voice.isListening ? Icons.mic : Icons.mic_none,
                          color: _voice.isListening
                              ? Colors.redAccent
                              : WildlifeScoutTheme.emeraldBio,
                        ),
                        onPressed: _voice.isListening
                            ? _stopVoiceInput
                            : _startVoiceInput,
                      ),
                    ),
                    IconButton(
                      icon: _isSearching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward),
                      onPressed: () => _performSearch(_searchCtrl.text),
                    ),
                  ],
                ),
                filled: true,
                fillColor: WildlifeScoutTheme.surfaceCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: WildlifeScoutTheme.borderSubtle),
                ),
              ),
            ),

            if (!_hasSearched) ...[
              const SizedBox(height: 16),
              const Text(
                'Häufige Gebiete & Wälder:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SuggestionChip(
                    label: 'Schwarzwald',
                    onTap: () {
                      _searchCtrl.text = 'Schwarzwald';
                      _performSearch('Schwarzwald');
                    },
                  ),
                  _SuggestionChip(
                    label: 'Harz',
                    onTap: () {
                      _searchCtrl.text = 'Harz';
                      _performSearch('Harz');
                    },
                  ),
                  _SuggestionChip(
                    label: 'Bayerischer Wald',
                    onTap: () {
                      _searchCtrl.text = 'Bayerischer Wald';
                      _performSearch('Bayerischer Wald');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Gebiete in deiner Nähe:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
              Text(
                '(${AppSettingsService.searchRadiusNotifier.value.round()} km GPS-Umkreis)',
                style: const TextStyle(
                  fontSize: 11,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _nearbyRegions.map((entry) {
                  return ActionChip(
                    avatar: const Icon(Icons.forest_outlined, size: 16, color: WildlifeScoutTheme.emeraldBio),
                    label: Text(
                      '${entry.region.name} (${entry.distanceKm.round()} km)',
                      style: const TextStyle(fontSize: 11.5, color: WildlifeScoutTheme.textPrimary),
                    ),
                    backgroundColor: WildlifeScoutTheme.surfaceCard,
                    side: const BorderSide(color: WildlifeScoutTheme.borderSubtle),
                    onPressed: () {
                      final item = LocationSearchResult(
                        title: entry.region.name,
                        subtitle: '${entry.region.state} • ${entry.distanceKm.round()} km entfernt',
                        coordinate: entry.region.coordinate,
                        categoryLabel: entry.region.categoryLabel,
                      );
                      widget.onLocationSelected(item);
                      Navigator.of(context).maybePop();
                    },
                  );
                }).toList(),
              ),
            ],

            if (_hasSearched) ...[
              const SizedBox(height: 14),
              Text(
                'Gefundene Orte (${_results.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WildlifeScoutTheme.amberGold,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 310),
                child: _results.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Kein Ort gefunden. Versuche einen anderen Namen oder GPS-Koordinaten.',
                            style: TextStyle(color: WildlifeScoutTheme.textMuted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          final isGps = item.categoryLabel == 'GPS-Direkt';
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              widget.onLocationSelected(item);
                              Navigator.of(context).maybePop();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: WildlifeScoutTheme.surfaceCard,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: WildlifeScoutTheme.borderSubtle,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: WildlifeScoutTheme.emeraldBio.withValues(
                                        alpha: 0.16,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isGps ? Icons.gps_fixed : Icons.place_outlined,
                                      color: WildlifeScoutTheme.emeraldBio,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        Text(
                                          item.subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: WildlifeScoutTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.categoryLabel,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: WildlifeScoutTheme.amberGold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: WildlifeScoutTheme.surfaceCard,
      side: const BorderSide(color: WildlifeScoutTheme.borderSubtle),
      onPressed: onTap,
    );
  }
}
