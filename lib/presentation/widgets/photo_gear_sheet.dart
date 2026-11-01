import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/wildscout_theme.dart';
import '../../data/services/photo_gear_service.dart';
import '../../domain/models/photo_gear_profile.dart';

/// Modal-Sheet zur Konfiguration der Wildlife-Fotoausrüstung (Objektiv, Sensor, Telekonverter)
/// mit Live-Berechnung von Kleinbild-Äquivalenz, Bildwinkel (FOV),
/// Sichtfeldbreiten und Schärfentiefe nach Apple HIG.
class PhotoGearSheet extends StatefulWidget {
  final VoidCallback? onGearChanged;

  const PhotoGearSheet({
    super.key,
    this.onGearChanged,
  });

  /// Zeigt das Konfigurationsblatt modal an.
  static Future<void> show(
    BuildContext context, {
    VoidCallback? onGearChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PhotoGearSheet(onGearChanged: onGearChanged),
    );
  }

  @override
  State<PhotoGearSheet> createState() => _PhotoGearSheetState();
}

class _PhotoGearSheetState extends State<PhotoGearSheet> {
  late PhotoGearProfile _currentGear;
  bool _isLoading = true;

  static const List<double> _popularFocals = [
    200.0,
    300.0,
    400.0,
    500.0,
    600.0,
    800.0,
  ];

  static const List<double> _popularApertures = [
    2.8,
    4.0,
    5.6,
    6.3,
    7.1,
    8.0,
  ];

  @override
  void initState() {
    super.initState();
    _loadGear();
  }

  Future<void> _loadGear() async {
    final gear = await PhotoGearService.loadGear();
    if (!mounted) return;
    setState(() {
      _currentGear = gear;
      _isLoading = false;
    });
  }

  Future<void> _updateGear(PhotoGearProfile newGear) async {
    HapticFeedback.selectionClick();
    setState(() {
      _currentGear = newGear;
    });
    await PhotoGearService.saveGear(newGear);
    widget.onGearChanged?.call();
  }

  void _applyPreset(PhotoGearPreset preset) {
    HapticFeedback.mediumImpact();
    final updated = _currentGear.copyWith(
      lensName: preset.name,
      focalLengthMm: preset.focalLengthMm,
      maxAperture: preset.maxAperture,
    );
    _updateGear(updated);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.90;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: WildScoutTheme.bgObsidian.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildScoutTheme.borderSubtle, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 12,
        bottom: bottomPadding + 16,
      ),
      child: Material(
        color: Colors.transparent,
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
                  color: WildScoutTheme.cyanWater.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: WildScoutTheme.cyanWater,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Foto-Ausrüstung & Optik',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Objektiv, Sensor & Telekonverter konfigurieren',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: WildScoutTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 22,
                  color: WildScoutTheme.textMuted,
                ),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Schließen',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  color: WildScoutTheme.cyanWater,
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
                    // 1. Live-Optik Zusammenfassung (Physik-HUD)
                    _buildOpticalSummaryCard(_currentGear),
                    const SizedBox(height: 16),

                    // 2. Beliebte Wildlife-Objektive (Presets)
                    const Text(
                      'BELIEBTE WILDLIFE-OBJEKTIVE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: WildScoutTheme.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: PhotoGearPreset.popularPresets.map((preset) {
                          final isSelected = _currentGear.focalLengthMm ==
                                  preset.focalLengthMm &&
                              (_currentGear.maxAperture - preset.maxAperture)
                                      .abs() <
                                  0.2;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                preset.name.split(' (').first,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.black
                                      : WildScoutTheme.textPrimary,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (_) => _applyPreset(preset),
                              selectedColor: WildScoutTheme.cyanWater,
                              backgroundColor: WildScoutTheme.surfaceCard,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isSelected
                                      ? WildScoutTheme.cyanWater
                                      : WildScoutTheme.borderSubtle,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 3. Brennweite (Slider & Quick-Chips)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Physikalische Brennweite',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: WildScoutTheme.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                WildScoutTheme.cyanWater.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: WildScoutTheme.cyanWater
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            '${_currentGear.focalLengthMm.round()} mm',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: WildScoutTheme.cyanWater,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: WildScoutTheme.cyanWater,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: WildScoutTheme.cyanWater,
                        overlayColor:
                            WildScoutTheme.cyanWater.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: _currentGear.focalLengthMm.clamp(70.0, 1200.0),
                        min: 70.0,
                        max: 1200.0,
                        divisions: 113, // ~10mm Schritte
                        onChanged: (val) {
                          _updateGear(_currentGear.copyWith(
                            focalLengthMm: val.roundToDouble(),
                            lensName: '${val.round()} mm Tele',
                          ));
                        },
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _popularFocals.map((focal) {
                        final isSelected =
                            _currentGear.focalLengthMm == focal;
                        return InkWell(
                          onTap: () {
                            _updateGear(_currentGear.copyWith(
                              focalLengthMm: focal,
                              lensName: '${focal.round()} mm Tele',
                            ));
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? WildScoutTheme.cyanWater
                                      .withValues(alpha: 0.25)
                                  : WildScoutTheme.surfaceCard,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? WildScoutTheme.cyanWater
                                    : WildScoutTheme.borderSubtle,
                              ),
                            ),
                            child: Text(
                              '${focal.round()} mm',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isSelected
                                    ? WildScoutTheme.cyanWater
                                    : WildScoutTheme.textPrimary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // 4. Offenblende (Lichtstärke)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Maximale Offenblende',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: WildScoutTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'f/${_currentGear.maxAperture.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: WildScoutTheme.amberGold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _popularApertures.map((ap) {
                        final isSelected =
                            (_currentGear.maxAperture - ap).abs() < 0.1;
                        return InkWell(
                          onTap: () {
                            _updateGear(_currentGear.copyWith(maxAperture: ap));
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? WildScoutTheme.amberGold
                                      .withValues(alpha: 0.22)
                                  : WildScoutTheme.surfaceCard,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? WildScoutTheme.amberGold
                                    : WildScoutTheme.borderSubtle,
                              ),
                            ),
                            child: Text(
                              'f/$ap',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isSelected
                                    ? WildScoutTheme.amberGold
                                    : WildScoutTheme.textPrimary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // 5. Sensorformat / Crop-Faktor
                    const Text(
                      'Kamera-Sensorformat (Crop-Faktor)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: WildScoutTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...CameraSensorFormat.values.map((format) {
                      final isSelected = _currentGear.sensorFormat == format;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () {
                            _updateGear(_currentGear.copyWith(
                              sensorFormat: format,
                            ));
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? WildScoutTheme.emeraldBio
                                      .withValues(alpha: 0.16)
                                  : WildScoutTheme.surfaceCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? WildScoutTheme.emeraldBio
                                    : WildScoutTheme.borderSubtle,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  size: 18,
                                  color: isSelected
                                      ? WildScoutTheme.emeraldBio
                                      : WildScoutTheme.textMuted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        format.label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? Colors.white
                                              : WildScoutTheme.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        'Sensorfläche: ${format.sensorWidthMm.toStringAsFixed(1)} × ${format.sensorHeightMm.toStringAsFixed(1)} mm',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: WildScoutTheme.textMuted,
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
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${format.cropFactor.toStringAsFixed(1)}x',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 18),

                    // 6. Telekonverter (Extender)
                    const Text(
                      'Telekonverter (Brennweiten-Verlängerung)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: WildScoutTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: Teleconverter.values.map((tc) {
                        final isSelected = _currentGear.teleconverter == tc;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () {
                                _updateGear(
                                  _currentGear.copyWith(teleconverter: tc),
                                );
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? WildScoutTheme.cyanWater
                                          .withValues(alpha: 0.20)
                                      : WildScoutTheme.surfaceCard,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? WildScoutTheme.cyanWater
                                        : WildScoutTheme.borderSubtle,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      tc == Teleconverter.none
                                          ? '1.0x (Ohne)'
                                          : '${tc.factor.toStringAsFixed(1)}x',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: isSelected
                                            ? WildScoutTheme.cyanWater
                                            : WildScoutTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      tc.stopLossEv > 0
                                          ? '+${tc.stopLossEv.round()} Blende'
                                          : 'Volles Licht',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: WildScoutTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // 7. Bildstabilisator
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _currentGear.hasOpticalStabilization,
                      onChanged: (val) {
                        _updateGear(
                          _currentGear.copyWith(hasOpticalStabilization: val),
                        );
                      },
                      title: const Text(
                        'Optische Bildstabilisierung (IS / VR / OSS)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Berücksichtigt 2–3 Belichtungsstufen Puffer bei Freihand-Verschlusszeiten',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: WildScoutTheme.textMuted,
                        ),
                      ),
                      activeTrackColor: WildScoutTheme.emeraldBio,
                    ),
                    const SizedBox(height: 12),

                    // Werkseinstellungen zurücksetzen
                    Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          await PhotoGearService.resetToDefaults();
                          await _loadGear();
                          widget.onGearChanged?.call();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Auf Standard (400 mm Vollformat) zurücksetzen'),
                        style: TextButton.styleFrom(
                          foregroundColor: WildScoutTheme.textMuted,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
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

  /// Visuelle Zusammenfassung der physikalisch errechneten Optik-Daten
  Widget _buildOpticalSummaryCard(PhotoGearProfile gear) {
    final effFocal = gear.effectiveFocalLengthMm.round();
    final effAp = gear.effectiveAperture;
    final hFov = gear.horizontalFovDeg;
    final w25 = gear.fieldWidthAtDistanceMeters(25).toStringAsFixed(1);
    final w50 = gear.fieldWidthAtDistanceMeters(50).toStringAsFixed(1);
    final w100 = gear.fieldWidthAtDistanceMeters(100).toStringAsFixed(1);
    final dof30 = gear.depthOfFieldCm(30);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WildScoutTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: WildScoutTheme.cyanWater.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                size: 18,
                color: WildScoutTheme.cyanWater,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Errechnete optische Physik im Feld',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: WildScoutTheme.cyanWater,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: WildScoutTheme.cyanWater.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'FOV: ${hFov.toStringAsFixed(1)}°',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: WildScoutTheme.cyanWater,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2 Spalten: Effektive Brennweite & Effektive Blende
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'KB-Äquivalent',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: WildScoutTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$effFocal mm',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${gear.focalLengthMm.round()} mm × ${gear.sensorFormat.cropFactor}x',
                        style: const TextStyle(
                          fontSize: 10,
                          color: WildScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Effektive Blende',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: WildScoutTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'f/${effAp.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: WildScoutTheme.amberGold,
                        ),
                      ),
                      Text(
                        gear.teleconverter != Teleconverter.none
                            ? 'inkl. ${gear.teleconverter.factor}x Konverter'
                            : 'Nativ ohne Lichtverlust',
                        style: const TextStyle(
                          fontSize: 10,
                          color: WildScoutTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Sichtbreiten-Tabelle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildFieldWidthItem('Bei 25 m', '$w25 m Breite'),
                Container(width: 1, height: 24, color: Colors.white12),
                _buildFieldWidthItem('Bei 50 m', '$w50 m Breite'),
                Container(width: 1, height: 24, color: Colors.white12),
                _buildFieldWidthItem('Bei 100 m', '$w100 m Breite'),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Schärfentiefe & Freihand
          Row(
            children: [
              const Icon(
                Icons.center_focus_strong_outlined,
                size: 14,
                color: WildScoutTheme.emeraldBio,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dof30.isInfinite
                      ? 'Schärfebereich bei 30 m: Bis unendlich'
                      : 'Schärfebereich bei 30 m: nur ${dof30.round()} cm (präziser Fokus nötig!)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: WildScoutTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldWidthItem(String distance, String width) {
    return Column(
      children: [
        Text(
          distance,
          style: const TextStyle(
            fontSize: 10,
            color: WildScoutTheme.textMuted,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          width,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: WildScoutTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
