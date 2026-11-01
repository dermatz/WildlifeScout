import 'dart:math' as math;

/// Sensorformate mit ihren physikalischen Abmessungen, Crop-Faktoren
/// und standardisierten Unschärfekreisen (Circle of Confusion / CoC).
enum CameraSensorFormat {
  fullFrame(
    id: 'full_frame',
    label: 'Vollformat / Kleinbild',
    cropFactor: 1.0,
    sensorWidthMm: 36.0,
    sensorHeightMm: 24.0,
    circleOfConfusionMm: 0.030,
  ),
  apscSonyNikonFuji(
    id: 'apsc_standard',
    label: 'APS-C (Sony / Nikon / Fuji 1.5x)',
    cropFactor: 1.5,
    sensorWidthMm: 23.5,
    sensorHeightMm: 15.6,
    circleOfConfusionMm: 0.020,
  ),
  apscCanon(
    id: 'apsc_canon',
    label: 'APS-C (Canon 1.6x)',
    cropFactor: 1.6,
    sensorWidthMm: 22.2,
    sensorHeightMm: 14.8,
    circleOfConfusionMm: 0.019,
  ),
  microFourThirds(
    id: 'mft',
    label: 'Micro Four Thirds (MFT 2.0x)',
    cropFactor: 2.0,
    sensorWidthMm: 17.3,
    sensorHeightMm: 13.0,
    circleOfConfusionMm: 0.015,
  );

  final String id;
  final String label;
  final double cropFactor;
  final double sensorWidthMm;
  final double sensorHeightMm;
  final double circleOfConfusionMm;

  const CameraSensorFormat({
    required this.id,
    required this.label,
    required this.cropFactor,
    required this.sensorWidthMm,
    required this.sensorHeightMm,
    required this.circleOfConfusionMm,
  });

  static CameraSensorFormat fromId(String? id) {
    return CameraSensorFormat.values.firstWhere(
      (e) => e.id == id,
      orElse: () => CameraSensorFormat.fullFrame,
    );
  }
}

/// Telekonverter (Extender) für Teleobjektive mit Verlängerungsfaktor
/// und Blendenstufen-Verlust.
enum Teleconverter {
  none(
    id: 'none',
    label: 'Kein Konverter (1.0x)',
    factor: 1.0,
    stopLossEv: 0.0,
  ),
  tc14(
    id: 'tc14',
    label: '1.4x Telekonverter (+1 EV)',
    factor: 1.4,
    stopLossEv: 1.0,
  ),
  tc20(
    id: 'tc20',
    label: '2.0x Telekonverter (+2 EV)',
    factor: 2.0,
    stopLossEv: 2.0,
  );

  final String id;
  final String label;
  final double factor;
  final double stopLossEv;

  const Teleconverter({
    required this.id,
    required this.label,
    required this.factor,
    required this.stopLossEv,
  });

  static Teleconverter fromId(String? id) {
    return Teleconverter.values.firstWhere(
      (e) => e.id == id,
      orElse: () => Teleconverter.none,
    );
  }
}

/// Typische Teleobjektiv-Voreinstellungen aus der Wildlife-Fotografie.
class PhotoGearPreset {
  final String id;
  final String name;
  final double focalLengthMm;
  final double maxAperture;

  const PhotoGearPreset({
    required this.id,
    required this.name,
    required this.focalLengthMm,
    required this.maxAperture,
  });

  static const List<PhotoGearPreset> popularPresets = [
    PhotoGearPreset(
      id: 'supertele_zoom_600',
      name: '200–600 mm f/5.6–6.3 (Sony / Nikon / Sigma)',
      focalLengthMm: 600.0,
      maxAperture: 6.3,
    ),
    PhotoGearPreset(
      id: 'tele_zoom_100_500',
      name: '100–500 mm f/4.5–7.1 (Canon RF)',
      focalLengthMm: 500.0,
      maxAperture: 7.1,
    ),
    PhotoGearPreset(
      id: 'tele_zoom_100_400',
      name: '100–400 mm f/4.5–5.6 (Kompaktes Telezoom)',
      focalLengthMm: 400.0,
      maxAperture: 5.6,
    ),
    PhotoGearPreset(
      id: 'tele_zoom_70_200',
      name: '70–200 mm f/2.8 (Lichtstarkes Telezoom)',
      focalLengthMm: 200.0,
      maxAperture: 2.8,
    ),
    PhotoGearPreset(
      id: 'prime_300_f4',
      name: '300 mm f/4.0 Festbrennweite',
      focalLengthMm: 300.0,
      maxAperture: 4.0,
    ),
    PhotoGearPreset(
      id: 'prime_400_f28',
      name: '400 mm f/2.8 High-End Festbrennweite',
      focalLengthMm: 400.0,
      maxAperture: 2.8,
    ),
    PhotoGearPreset(
      id: 'prime_500_f4',
      name: '500 mm f/4.0 Festbrennweite',
      focalLengthMm: 500.0,
      maxAperture: 4.0,
    ),
    PhotoGearPreset(
      id: 'prime_600_f4',
      name: '600 mm f/4.0 Festbrennweite',
      focalLengthMm: 600.0,
      maxAperture: 4.0,
    ),
    PhotoGearPreset(
      id: 'prime_800_f56',
      name: '800 mm f/5.6 / f/6.3 Supertele',
      focalLengthMm: 800.0,
      maxAperture: 6.3,
    ),
  ];
}

/// Unveränderliches Datenmodell für das Foto- & Objektiv-Setup des Nutzers.
/// Berechnet physikalische Optik-Kennzahlen wie effektive Kleinbild-Brennweite,
/// Bildwinkel (Field of View), Schärfentiefe und Sichtfeld-Breiten.
class PhotoGearProfile {
  final String lensName;
  final double focalLengthMm;
  final double maxAperture;
  final CameraSensorFormat sensorFormat;
  final Teleconverter teleconverter;
  final bool hasOpticalStabilization;

  const PhotoGearProfile({
    this.lensName = '400 mm f/4.0 Tele',
    this.focalLengthMm = 400.0,
    this.maxAperture = 4.0,
    this.sensorFormat = CameraSensorFormat.fullFrame,
    this.teleconverter = Teleconverter.none,
    this.hasOpticalStabilization = true,
  });

  /// Effektive Brennweite unter Berücksichtigung von Telekonverter (physikalisch)
  double get opticalFocalLengthMm => focalLengthMm * teleconverter.factor;

  /// Effektive Kleinbild-äquivalente Brennweite (KB / 35mm-Äquivalent)
  double get effectiveFocalLengthMm =>
      opticalFocalLengthMm * sensorFormat.cropFactor;

  /// Effektive Offenblende (Lichtstärken-Verlust durch Konverter)
  double get effectiveAperture => maxAperture * teleconverter.factor;

  /// Horizontaler Bildwinkel (Field of View) in Grad.
  double get horizontalFovDeg {
    final physFocal = opticalFocalLengthMm;
    if (physFocal <= 0) return 45.0;
    final rad = 2 * math.atan(sensorFormat.sensorWidthMm / (2 * physFocal));
    return rad * (180.0 / math.pi);
  }

  /// Vertikaler Bildwinkel in Grad.
  double get verticalFovDeg {
    final physFocal = opticalFocalLengthMm;
    if (physFocal <= 0) return 30.0;
    final rad = 2 * math.atan(sensorFormat.sensorHeightMm / (2 * physFocal));
    return rad * (180.0 / math.pi);
  }

  /// Diagonaler Bildwinkel in Grad.
  double get diagonalFovDeg {
    final physFocal = opticalFocalLengthMm;
    if (physFocal <= 0) return 50.0;
    final diagonalMm = math.sqrt(
      sensorFormat.sensorWidthMm * sensorFormat.sensorWidthMm +
          sensorFormat.sensorHeightMm * sensorFormat.sensorHeightMm,
    );
    final rad = 2 * math.atan(diagonalMm / (2 * physFocal));
    return rad * (180.0 / math.pi);
  }

  /// Sichtfeld-Breite (Field of View Width) in Metern bei gegebener Entfernung.
  double fieldWidthAtDistanceMeters(double distanceMeters) {
    if (distanceMeters <= 0) return 0;
    final rad = (horizontalFovDeg / 2.0) * (math.pi / 180.0);
    return 2.0 * distanceMeters * math.tan(rad);
  }

  /// Sichtfeld-Höhe (Field of View Height) in Metern bei gegebener Entfernung.
  double fieldHeightAtDistanceMeters(double distanceMeters) {
    if (distanceMeters <= 0) return 0;
    final rad = (verticalFovDeg / 2.0) * (math.pi / 180.0);
    return 2.0 * distanceMeters * math.tan(rad);
  }

  /// Berechnet die Schärfentiefe (Depth of Field in Zentimetern) bei gegebener Distanz.
  /// Nutzt die hyperfokale Standard-Formel mit dem CoC des gewählten Sensors.
  double depthOfFieldCm(double distanceMeters) {
    if (distanceMeters <= 0) return 0;
    final f = opticalFocalLengthMm / 1000.0; // Brennweite in Metern
    final n = effectiveAperture; // Blende
    final c = sensorFormat.circleOfConfusionMm / 1000.0; // CoC in Metern

    // Hyperfokaldistanz in Metern
    final h = (f * f) / (n * c) + f;

    final d = distanceMeters;
    if (d >= h) {
      // Reicht bis unendlich
      return double.infinity;
    }

    final dNear = (h * d) / (h + (d - f));
    final dFar = (h * d) / (h - (d - f));

    final dofMeters = dFar - dNear;
    return dofMeters * 100.0; // Rückgabe in cm
  }

  /// Mindest-Verschlusszeit aus freier Hand (Faustregel: 1 / KB-Brennweite).
  /// Bei Bildstabilisator (IBIS / IS) um 2–3 Belichtungsstufen verlängert.
  String get recommendedHandheldShutterSpeed {
    final effFocal = effectiveFocalLengthMm;
    final baseSpeed = effFocal > 0 ? (1.0 / effFocal) : 1 / 400.0;
    if (hasOpticalStabilization) {
      // 2 Stufen Puffer mit Stabilisator
      final stabilizedSpeed = baseSpeed * 4.0;
      final denom = (1.0 / stabilizedSpeed).round();
      return '1/${denom.clamp(60, 2000)} s';
    } else {
      final denom = (1.0 / baseSpeed).round();
      return '1/${denom.clamp(125, 4000)} s';
    }
  }

  PhotoGearProfile copyWith({
    String? lensName,
    double? focalLengthMm,
    double? maxAperture,
    CameraSensorFormat? sensorFormat,
    Teleconverter? teleconverter,
    bool? hasOpticalStabilization,
  }) {
    return PhotoGearProfile(
      lensName: lensName ?? this.lensName,
      focalLengthMm: focalLengthMm ?? this.focalLengthMm,
      maxAperture: maxAperture ?? this.maxAperture,
      sensorFormat: sensorFormat ?? this.sensorFormat,
      teleconverter: teleconverter ?? this.teleconverter,
      hasOpticalStabilization:
          hasOpticalStabilization ?? this.hasOpticalStabilization,
    );
  }

  Map<String, dynamic> toJson() => {
        'lensName': lensName,
        'focalLengthMm': focalLengthMm,
        'maxAperture': maxAperture,
        'sensorFormat': sensorFormat.id,
        'teleconverter': teleconverter.id,
        'hasOpticalStabilization': hasOpticalStabilization,
      };

  factory PhotoGearProfile.fromJson(Map<String, dynamic> json) {
    return PhotoGearProfile(
      lensName: json['lensName']?.toString() ?? '400 mm f/4.0 Tele',
      focalLengthMm: (json['focalLengthMm'] as num?)?.toDouble() ?? 400.0,
      maxAperture: (json['maxAperture'] as num?)?.toDouble() ?? 4.0,
      sensorFormat: CameraSensorFormat.fromId(json['sensorFormat']?.toString()),
      teleconverter: Teleconverter.fromId(json['teleconverter']?.toString()),
      hasOpticalStabilization:
          json['hasOpticalStabilization'] as bool? ?? true,
    );
  }
}
