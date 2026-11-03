import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../data/services/compass_heading_service.dart';
import '../../domain/models/weather_frame.dart';

/// Minimalistisches horizontales HUD-Kompassband für Mobilgeräte im Gelände.
///
/// Sitzt direkt auf dem unteren Steuerungs-HUD auf und dreht sich flüssig in Echtzeit
/// mit der tatsächlichen Haltung & Drehung des Smartphones im Gelände mit.
///
/// Eigenschaften:
/// - Skalierung in 5°-Schritten (subtile Ticks alle 5°, mittlere bei 15°, Hauptmarken bei 30°).
/// - Prominente Anzeige aller Haupt- und Nebenhimmelsrichtungen nach deutschem Standard:
///   `N` (0° - rot hervorgehoben), `NO` (45°), `O` (90°), `SO` (135°),
///   `S` (180°), `SW` (225°), `W` (270°), `NW` (315°).
/// - Numerische Gradzahlen bei 30°-Schritten (`30`, `60`, `120`, `150`, `210`, `240`, `300`, `330`).
/// - Minimalistischer Zielzeiger (Center Reticle `▼`) in Bernsteingold mit digitaler Grad- & Himmelsrichtungs-Anzeige.
/// - Sanftes horizontales Ausfaden (ShaderMask Gradient) an den Außenrändern.
/// - Optionale taktile Anzeige der Wind-Einfallsrichtung (Scent-Detection).
/// - Touch-Interaktivität: Tippen öffnet den detaillierten 360°-Witterungskompass, Wischen erlaubt manuelle Vorschau.
class HudCompassTape extends StatefulWidget {
  final WeatherFrame? currentWeather;
  final double? initialHeading;
  final VoidCallback? onTap;
  final double height;

  const HudCompassTape({
    super.key,
    this.currentWeather,
    this.initialHeading,
    this.onTap,
    this.height = 38.0,
  });

  static String cardinalForHeading(double deg) {
    const directions = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
    final idx = ((deg + 22.5) % 360 / 45).floor();
    return directions[idx % 8];
  }

  @override
  State<HudCompassTape> createState() => _HudCompassTapeState();
}

class _HudCompassTapeState extends State<HudCompassTape>
    with SingleTickerProviderStateMixin {
  StreamSubscription<CompassHeadingData>? _headingSub;
  late AnimationController _animController;

  double _targetHeading = 0.0;
  double _currentSmoothedHeading = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.initialHeading != null) {
      _targetHeading = widget.initialHeading! % 360.0;
      _currentSmoothedHeading = _targetHeading;
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);

    _headingSub = CompassHeadingService.stream.listen((data) {
      if (!mounted) return;
      if (widget.initialHeading == null) {
        if (data.hasSensor) {
          _targetHeading = data.heading % 360.0;
          if (!_animController.isAnimating) {
            _animController.repeat();
          }
        }
      }
    });
  }

  void _onTick() {
    // Kürzeste Winkeldifferenz berechnen (-180° bis +180°)
    double diff = (_targetHeading - _currentSmoothedHeading) % 360.0;
    if (diff < -180.0) diff += 360.0;
    if (diff > 180.0) diff -= 360.0;

    if (diff.abs() > 0.04) {
      // Exponentielle Glättung für seidenweiche 60/120-fps Bewegung ohne Sensor-Zittern
      setState(() {
        _currentSmoothedHeading =
            (_currentSmoothedHeading + diff * 0.22) % 360.0;
        if (_currentSmoothedHeading < 0) {
          _currentSmoothedHeading += 360.0;
        }
      });
    } else {
      if (_currentSmoothedHeading != _targetHeading) {
        setState(() {
          _currentSmoothedHeading = _targetHeading;
        });
      }
      _animController.stop();
    }
  }

  @override
  void didUpdateWidget(covariant HudCompassTape oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialHeading != null &&
        widget.initialHeading != oldWidget.initialHeading) {
      _targetHeading = widget.initialHeading! % 360.0;
      if (!_animController.isAnimating) {
        _animController.repeat();
      }
    }
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roundedHeading = _currentSmoothedHeading.round() % 360;
    final cardinal = HudCompassTape.cardinalForHeading(_currentSmoothedHeading);
    final headingText =
        '${roundedHeading.toString().padLeft(3, '0')}° $cardinal';

    return Semantics(
      label:
          'Minimalistischer HUD-Kompass. Aktuelle Blickrichtung: $headingText.',
      hint:
          'Tippen zum Öffnen des 360° Witterungskompasses. Wischen zum manuellen Drehen.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap?.call();
        },
        onHorizontalDragUpdate: (details) {
          // Manuelles Wischen erlaubt intuitive Drehung auf Desktop/Simulator
          const pixelsPerDegree = 2.8;
          setState(() {
            _targetHeading =
                (_targetHeading - details.primaryDelta! / pixelsPerDegree) %
                    360.0;
            if (_targetHeading < 0) _targetHeading += 360.0;
            if (!_animController.isAnimating) {
              _animController.repeat();
            }
          });
        },
        child: Container(
          height: widget.height,
          constraints: const BoxConstraints(minHeight: 38.0),
          decoration: BoxDecoration(
            color: const Color(0xE010171E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Stack(
                children: [
                  // 1. Horizontales Skalenband mit weichem Rand-Ausblenden (ShaderMask)
                  Positioned.fill(
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        return const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            Colors.black,
                            Colors.black,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.12, 0.88, 1.0],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: CustomPaint(
                        painter: _HudCompassTapePainter(
                          heading: _currentSmoothedHeading,
                          windDeg: widget.currentWeather?.windDirectionDegrees,
                          windSpeedKmh: widget.currentWeather?.windSpeedKmh,
                        ),
                      ),
                    ),
                  ),

                  // 2. Minimalistischer Zielzeiger (Center Reticle) in Bernsteingold
                  Center(
                    child: IgnorePointer(
                      child: _buildCenterReticle(headingText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterReticle(String headingText) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Digitaler Grad- & Himmelsrichtungs-Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xF018222A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.65),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: WildlifeScoutTheme.amberGold.withValues(alpha: 0.20),
                blurRadius: 6,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headingText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.0,
                  fontWeight: FontWeight.w800,
                  color: WildlifeScoutTheme.amberGold,
                  letterSpacing: 0.4,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 1),
        // Scharfer Zielkeil / Dreiecks-Indikator ▼
        CustomPaint(
          size: const Size(8, 4.5),
          painter: _CenterArrowPainter(color: WildlifeScoutTheme.amberGold),
        ),
      ],
    );
  }
}

/// CustomPainter für den scharfen Reticle-Keil ▼
class _CenterArrowPainter extends CustomPainter {
  final Color color;

  const _CenterArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CenterArrowPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// CustomPainter für das minimalistische Kompassband:
/// Zeichnet Ticks alle 5° und Beschriftungen für 30°-Schritte und Himmelsrichtungen.
class _HudCompassTapePainter extends CustomPainter {
  final double heading;
  final double? windDeg;
  final double? windSpeedKmh;

  static const double pixelsPerDegree = 2.8;

  _HudCompassTapePainter({
    required this.heading,
    this.windDeg,
    this.windSpeedKmh,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0;

    final tickPaintSmall = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final tickPaintMedium = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final tickPaintMajor = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final tickPaintNorth = Paint()
      ..color = const Color(0xFFFF453A) // Signal-Rot für Norden
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    const tickTop = 18.0;

    // Zeichne Ticks & Beschriftungen in 5°-Schritten von 0° bis 355°
    for (int deg = 0; deg < 360; deg += 5) {
      double diff = (deg - heading) % 360.0;
      if (diff < -180.0) diff += 360.0;
      if (diff > 180.0) diff -= 360.0;

      final x = cx + diff * pixelsPerDegree;

      // Außerhalb des sichtbaren Canvas-Bereichs überspringen
      if (x < -40 || x > size.width + 40) continue;

      final isCardinal = (deg % 45 == 0);
      final isMajor30 = (deg % 30 == 0);
      final isMedium15 = (deg % 15 == 0);

      if (isCardinal) {
        final isNorth = (deg == 0);
        final tickHeight = isNorth ? 10.0 : 8.5;

        canvas.drawLine(
          Offset(x, tickTop),
          Offset(x, tickTop + tickHeight),
          isNorth ? tickPaintNorth : tickPaintMajor,
        );

        final label = _cardinalName(deg);
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: isNorth ? 11.0 : 10.0,
              fontWeight: FontWeight.w900,
              color: isNorth ? const Color(0xFFFF5252) : Colors.white,
              letterSpacing: -0.2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2.0, tickTop + tickHeight + 1.0),
        );
      } else if (isMajor30) {
        // 30°-Schritte mit dezenten numerischen Gradzahlen
        const tickHeight = 7.0;
        canvas.drawLine(
          Offset(x, tickTop),
          Offset(x, tickTop + tickHeight),
          tickPaintMedium,
        );

        final textPainter = TextPainter(
          text: TextSpan(
            text: '$deg',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.60),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2.0, tickTop + tickHeight + 1.5),
        );
      } else if (isMedium15) {
        // 15°-Zwischenstriche (ohne Text)
        const tickHeight = 5.5;
        canvas.drawLine(
          Offset(x, tickTop),
          Offset(x, tickTop + tickHeight),
          tickPaintMedium,
        );
      } else {
        // 5°-Minimale Ticks
        const tickHeight = 3.5;
        canvas.drawLine(
          Offset(x, tickTop),
          Offset(x, tickTop + tickHeight),
          tickPaintSmall,
        );
      }
    }

    // 3. Optionale Wind-Einfallsrichtung auf dem Band visualisieren
    if (windDeg != null) {
      double diff = (windDeg! - heading) % 360.0;
      if (diff < -180.0) diff += 360.0;
      if (diff > 180.0) diff -= 360.0;

      final wx = cx + diff * pixelsPerDegree;
      if (wx >= -20 && wx <= size.width + 20) {
        _paintWindIndicator(canvas, wx, tickTop);
      }
    }
  }

  void _paintWindIndicator(Canvas canvas, double x, double top) {
    final circlePaint = Paint()
      ..color = WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = WildlifeScoutTheme.emeraldBio
      ..style = PaintingStyle.fill;

    // Sanfte Wind-Böen-Marke (Aura + Punkt)
    canvas.drawCircle(Offset(x, top - 3.5), 4.5, circlePaint);
    canvas.drawCircle(Offset(x, top - 3.5), 2.2, dotPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'WIND',
        style: TextStyle(
          fontSize: 6.5,
          fontWeight: FontWeight.w800,
          color: WildlifeScoutTheme.emeraldBio,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(x - textPainter.width / 2.0, top - 11.0),
    );
  }

  static String _cardinalName(int deg) {
    switch (deg) {
      case 0:
        return 'N';
      case 45:
        return 'NO';
      case 90:
        return 'O';
      case 135:
        return 'SO';
      case 180:
        return 'S';
      case 225:
        return 'SW';
      case 270:
        return 'W';
      case 315:
        return 'NW';
      default:
        return '$deg';
    }
  }

  @override
  bool shouldRepaint(covariant _HudCompassTapePainter oldDelegate) {
    return heading != oldDelegate.heading ||
        windDeg != oldDelegate.windDeg ||
        windSpeedKmh != oldDelegate.windSpeedKmh;
  }
}
