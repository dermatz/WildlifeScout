import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/privacy/coordinate_guard.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../domain/models/weather_frame.dart';

enum WindyOverlayMode {
  clouds(
    id: 'clouds',
    label: 'Wolken & Wind',
    icon: Icons.cloud_outlined,
    description: 'Farbige Wolkenbänder mit fließenden Windpartikeln (ECMWF)',
  ),
  wind(
    id: 'wind',
    label: 'Windfeld & Böen',
    icon: Icons.air,
    description: 'Strömungsvektoren & Windstärken mit Farbgradienten',
  ),
  satellite(
    id: 'satellite',
    label: 'Satellit (IR)',
    icon: Icons.satellite_alt_outlined,
    description: 'Echtzeit-Infrarot-Wolkenfilm von EUMETSAT',
  ),
  rain(
    id: 'rain',
    label: 'Regen & Radar',
    icon: Icons.water_drop_outlined,
    description: 'Hochauflösende Niederschlags- & Gewitterfronten',
  );

  final String id;
  final String label;
  final IconData icon;
  final String description;

  const WindyOverlayMode({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
  });
}

/// Taktischer Großwetter-, Wolken- & Windströmungs-Viewer
/// basierend auf dem europäischen ECMWF-Leitmodell und animierten Windpartikeln.
///
/// Alle Koordinaten werden vor der Übergabe über den [CoordinateGuard]
/// automatisch auf 2 km gerundet, um sensible Ansitz-Spots zu schützen (DSGVO).
class TacticalWindyWeatherSheet extends StatefulWidget {
  final LatLng coordinate;
  final WeatherFrame currentWeather;
  final WindyOverlayMode initialMode;
  final int initialZoom;
  final bool initialShowLocationPin;

  const TacticalWindyWeatherSheet({
    super.key,
    required this.coordinate,
    required this.currentWeather,
    this.initialMode = WindyOverlayMode.clouds,
    this.initialZoom = 10,
    this.initialShowLocationPin = true,
  });

  @override
  State<TacticalWindyWeatherSheet> createState() =>
      _TacticalWindyWeatherSheetState();
}

class _TacticalWindyWeatherSheetState extends State<TacticalWindyWeatherSheet> {
  late WindyOverlayMode _selectedMode;
  WebViewController? _webViewController;
  bool _isLoading = true;
  late int _zoom;
  late bool _showLocationPin;

  bool get _isMobileWebviewSupported =>
      !kIsWeb &&
      WebViewPlatform.instance != null &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
    _zoom = widget.initialZoom;
    _showLocationPin = widget.initialShowLocationPin;
    if (_isMobileWebviewSupported) {
      _initWebViewController();
    }
  }

  void _initWebViewController() {
    final url = _buildWindyEmbedUrl();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(WildlifeScoutTheme.bgObsidian)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  String _buildWindyEmbedUrl() {
    final lat = _showLocationPin
        ? widget.coordinate.latitude
        : CoordinateGuard.obfuscateForWeatherApi(
            widget.coordinate.latitude,
            widget.coordinate.longitude,
          ).lat;
    final lon = _showLocationPin
        ? widget.coordinate.longitude
        : CoordinateGuard.obfuscateForWeatherApi(
            widget.coordinate.latitude,
            widget.coordinate.longitude,
          ).lon;

    final latStr = lat.toStringAsFixed(_showLocationPin ? 4 : 2);
    final lonStr = lon.toStringAsFixed(_showLocationPin ? 4 : 2);
    final markerParam = _showLocationPin ? 'true' : '';

    return 'https://embed.windy.com/embed2.html'
        '?lat=$latStr'
        '&lon=$lonStr'
        '&detailLat=$latStr'
        '&detailLon=$lonStr'
        '&width=650'
        '&height=450'
        '&zoom=$_zoom'
        '&level=surface'
        '&overlay=${_selectedMode.id}'
        '&product=ecmwf'
        '&menu='
        '&message='
        '&marker=$markerParam'
        '&calendar=now'
        '&pressure='
        '&type=map'
        '&location=coordinates'
        '&detail='
        '&metricWind=km%2Fh'
        '&metricTemp=%C2%B0C'
        '&radarRange=-1';
  }

  void _onModeChanged(WindyOverlayMode mode) {
    if (_selectedMode == mode) return;
    setState(() {
      _selectedMode = mode;
      _isLoading = true;
    });
    if (_isMobileWebviewSupported && _webViewController != null) {
      _webViewController!.loadRequest(Uri.parse(_buildWindyEmbedUrl()));
    }
  }

  void _setZoom(int newZoom) {
    final clamped = newZoom.clamp(4, 11);
    if (_zoom == clamped) return;
    setState(() {
      _zoom = clamped;
      _isLoading = true;
    });
    if (_isMobileWebviewSupported && _webViewController != null) {
      _webViewController!.loadRequest(Uri.parse(_buildWindyEmbedUrl()));
    }
  }

  void _toggleLocationPin() {
    setState(() {
      _showLocationPin = !_showLocationPin;
      _isLoading = true;
    });
    if (_isMobileWebviewSupported && _webViewController != null) {
      _webViewController!.loadRequest(Uri.parse(_buildWindyEmbedUrl()));
    }
  }

  Future<void> _launchExternalWindy() async {
    final uri = Uri.parse(_buildWindyEmbedUrl());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weather = widget.currentWeather;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildlifeScoutTheme.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.air_rounded,
                    color: WildlifeScoutTheme.cyanWater,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Atmosphärischer Wolken- & Windfilm',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ECMWF LEITMODELL',
                              style: TextStyle(
                                color: WildlifeScoutTheme.emeraldBio,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showLocationPin
                                ? '• 📍 Spot sichtbar'
                                : '• 🛡️ 2 km DSGVO-Raster',
                            style: const TextStyle(
                              color: WildlifeScoutTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  tooltip: 'Schließen',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Segmented Filter / Mode Tabs (Apple HIG)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: WindyOverlayMode.values.map((mode) {
                final isSelected = _selectedMode == mode;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => _onModeChanged(mode),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? WildlifeScoutTheme.cyanWater.withValues(alpha: 0.22)
                            : WildlifeScoutTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? WildlifeScoutTheme.cyanWater
                              : WildlifeScoutTheme.borderSubtle,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            mode.icon,
                            size: 16,
                            color: isSelected
                                ? WildlifeScoutTheme.cyanWater
                                : WildlifeScoutTheme.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            mode.label,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : WildlifeScoutTheme.textMuted,
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Zoom & Maßstabs-Steuerung (Apple HIG)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.zoom_in_rounded,
                  size: 15,
                  color: WildlifeScoutTheme.textMuted,
                ),
                const SizedBox(width: 5),
                const Text(
                  'Zoom:',
                  style: TextStyle(
                    color: WildlifeScoutTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildZoomChip(label: 'Großraum (6)', zoom: 6),
                        const SizedBox(width: 5),
                        _buildZoomChip(label: 'Region (8)', zoom: 8),
                        const SizedBox(width: 5),
                        _buildZoomChip(label: 'Revier (10)', zoom: 10),
                        const SizedBox(width: 5),
                        _buildZoomChip(label: 'Nahfeld (11)', zoom: 11),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _zoom > 4 ? () => _setZoom(_zoom - 1) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: WildlifeScoutTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: WildlifeScoutTheme.borderSubtle),
                    ),
                    child: Icon(
                      Icons.remove,
                      size: 14,
                      color: _zoom > 4 ? Colors.white70 : Colors.white24,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: _zoom < 11 ? () => _setZoom(_zoom + 1) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: WildlifeScoutTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: WildlifeScoutTheme.borderSubtle),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 14,
                      color: _zoom < 11 ? Colors.white70 : Colors.white24,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Optionaler Spot-Pin Toggle
                InkWell(
                  onTap: _toggleLocationPin,
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _showLocationPin
                          ? WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.22)
                          : WildlifeScoutTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _showLocationPin
                            ? WildlifeScoutTheme.crimsonScent
                            : WildlifeScoutTheme.borderSubtle,
                        width: _showLocationPin ? 1.2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showLocationPin
                              ? Icons.location_on_rounded
                              : Icons.location_off_outlined,
                          size: 13,
                          color: _showLocationPin
                              ? WildlifeScoutTheme.crimsonScent
                              : WildlifeScoutTheme.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _showLocationPin ? 'Spot: An' : 'Spot: Aus',
                          style: TextStyle(
                            color: _showLocationPin
                                ? Colors.white
                                : WildlifeScoutTheme.textMuted,
                            fontSize: 11,
                            fontWeight: _showLocationPin
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Interactive Map / Viewer Container
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D141C),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: WildlifeScoutTheme.borderSubtle,
                        width: 1,
                      ),
                    ),
                    child: _isMobileWebviewSupported && _webViewController != null
                        ? WebViewWidget(controller: _webViewController!)
                        : _buildFallbackPreview(context),
                  ),
                ),
                if (_isMobileWebviewSupported && _isLoading)
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: WildlifeScoutTheme.cyanWater,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Lade ECMWF Strömungsfeld...',
                              style: TextStyle(
                                color: WildlifeScoutTheme.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
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
          const SizedBox(height: 12),

          // 3-Stockwerke-Wolkenschichtung & Licht-Inspector (Apple HIG)
          _buildCloudStratificationInspector(weather),
          const SizedBox(height: 8),

          // Footer Action & External Launch
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedMode.description,
                    style: const TextStyle(
                      color: WildlifeScoutTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WildlifeScoutTheme.cyanWater,
                    side: const BorderSide(
                      color: WildlifeScoutTheme.cyanWater,
                      width: 1,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _launchExternalWindy,
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text(
                    'Vollbild',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackPreview(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: WildlifeScoutTheme.cyanWater.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.air_rounded,
                color: WildlifeScoutTheme.cyanWater,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'ECMWF Live-Wolken & Windpartikel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Für die flüssigste Darstellung der animierten Wind-Streamlines und thermodynamischen Wolkenschichten kannst du den Viewer im interaktiven Vollbild-Modus öffnen.',
              style: TextStyle(
                color: WildlifeScoutTheme.textMuted,
                fontSize: 12,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: WildlifeScoutTheme.cyanWater,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _launchExternalWindy,
              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
              label: const Text(
                'Interaktiven Live-Film öffnen',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudStratificationInspector(WeatherFrame weather) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WildlifeScoutTheme.surfaceCard.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WildlifeScoutTheme.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lens_blur_rounded,
                color: WildlifeScoutTheme.amberGold,
                size: 16,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Fotografisches Wolkenprofil (3 Schichten)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    weather.photographicLightQuality,
                    style: const TextStyle(
                      color: WildlifeScoutTheme.amberGold,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildCloudLayerColumn(
                  level: 'Hohe Cirren',
                  altitude: '6–12 km',
                  percent: weather.cloudCoverHighPercent,
                  color: const Color(0xFFF59E0B),
                  impact: 'Abendrot & Rayleigh',
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: WildlifeScoutTheme.borderSubtle,
              ),
              Expanded(
                child: _buildCloudLayerColumn(
                  level: 'Mittlere Wolken',
                  altitude: '2–6 km',
                  percent: weather.cloudCoverMidPercent,
                  color: const Color(0xFF38BDF8),
                  impact: 'Softbox für Porträts',
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: WildlifeScoutTheme.borderSubtle,
              ),
              Expanded(
                child: _buildCloudLayerColumn(
                  level: 'Tiefer Stratus',
                  altitude: '0–2 km',
                  percent: weather.cloudCoverLowPercent,
                  color: const Color(0xFF94A3B8),
                  impact: 'Flachlicht & Nebel',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCloudLayerColumn({
    required String level,
    required String altitude,
    required int percent,
    required Color color,
    required String impact,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                level,
                style: const TextStyle(
                  color: WildlifeScoutTheme.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: percent / 100.0,
              minHeight: 4,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            impact,
            style: const TextStyle(
              color: WildlifeScoutTheme.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildZoomChip({required String label, required int zoom}) {
    final isSelected = _zoom == zoom;
    return InkWell(
      onTap: () => _setZoom(zoom),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? WildlifeScoutTheme.cyanWater.withValues(alpha: 0.22)
              : WildlifeScoutTheme.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? WildlifeScoutTheme.cyanWater
                : WildlifeScoutTheme.borderSubtle,
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : WildlifeScoutTheme.textMuted,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
