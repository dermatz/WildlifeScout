import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/wildlifescout_theme.dart';

/// Visueller Blickrichtungs-Fächer (Flashlight Beam / Peilstrahl) am Fotospot-Marker.
/// Zeigt in Echtzeit auf der Karte an, in welche Himmelsrichtung das Smartphone
/// im Gelände blickt (nach Vorbild von Apple Maps / Precision GPS).
class DeviceHeadingBeam extends StatelessWidget {
  final double headingDeg; // 0 = oben, 90 = rechts, 180 = unten, 270 = links
  final double beamLength;
  final double beamAngleDeg;
  final Color accentColor;

  const DeviceHeadingBeam({
    super.key,
    required this.headingDeg,
    this.beamLength = 58.0,
    this.beamAngleDeg = 50.0,
    this.accentColor = WildlifeScoutTheme.cyanWater,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 240,
        height: 240,
        child: CustomPaint(
          painter: _DeviceHeadingBeamPainter(
            headingDeg: headingDeg,
            beamLength: beamLength,
            beamAngleDeg: beamAngleDeg,
            accentColor: accentColor,
          ),
        ),
      ),
    );
  }
}

class _DeviceHeadingBeamPainter extends CustomPainter {
  final double headingDeg;
  final double beamLength;
  final double beamAngleDeg;
  final Color accentColor;

  _DeviceHeadingBeamPainter({
    required this.headingDeg,
    required this.beamLength,
    required this.beamAngleDeg,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Pin-Radius (34 px Durchmesser -> 17 px Radius)
    const pinRadius = 17.0;
    final outerRadius = pinRadius + beamLength;

    // Gradmaß zu Canvas-Bogenmaß (0° oben = -pi/2)
    final centerRad = (headingDeg - 90.0) * (math.pi / 180.0);
    final halfApertureRad = (beamAngleDeg / 2.0) * (math.pi / 180.0);
    final startRad = centerRad - halfApertureRad;
    final sweepRad = halfApertureRad * 2.0;

    // 1. Blickrichtungs-Fächer (Flashlight Cone mit Radialgradient)
    final conePath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: outerRadius),
        startRad,
        sweepRad,
        false,
      )
      ..close();

    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accentColor.withValues(alpha: 0.65),
          accentColor.withValues(alpha: 0.30),
          accentColor.withValues(alpha: 0.0),
        ],
        stops: const [0.15, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.fill;
    canvas.drawPath(conePath, fillPaint);

    // 2. Feine flankierende Randstrahlen des Sichtkegels
    final rayPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.45)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final ray1Start = Offset(
      center.dx + (pinRadius - 2) * math.cos(startRad),
      center.dy + (pinRadius - 2) * math.sin(startRad),
    );
    final ray1End = Offset(
      center.dx + outerRadius * math.cos(startRad),
      center.dy + outerRadius * math.sin(startRad),
    );
    canvas.drawLine(ray1Start, ray1End, rayPaint);

    final ray2Start = Offset(
      center.dx + (pinRadius - 2) * math.cos(startRad + sweepRad),
      center.dy + (pinRadius - 2) * math.sin(startRad + sweepRad),
    );
    final ray2End = Offset(
      center.dx + outerRadius * math.cos(startRad + sweepRad),
      center.dy + outerRadius * math.sin(startRad + sweepRad),
    );
    canvas.drawLine(ray2Start, ray2End, rayPaint);

    // 3. Äußerer weicher Bogen
    final arcPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.50)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      startRad,
      sweepRad,
      false,
      arcPaint,
    );

    // 4. Zentraler Laser-Peilstrahl (Exakte Blickrichtungslinie)
    final laserPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final laserStart = Offset(
      center.dx + (pinRadius + 2) * math.cos(centerRad),
      center.dy + (pinRadius + 2) * math.sin(centerRad),
    );
    final laserEnd = Offset(
      center.dx + (outerRadius + 6) * math.cos(centerRad),
      center.dy + (outerRadius + 6) * math.sin(centerRad),
    );
    canvas.drawLine(laserStart, laserEnd, laserPaint);

    // 5. Peilungs-Pfeil (Chevron / Arrowhead) an der Spitze
    final tipPoint = Offset(
      center.dx + (outerRadius + 11) * math.cos(centerRad),
      center.dy + (outerRadius + 11) * math.sin(centerRad),
    );

    final arrowPath = Path()
      ..moveTo(tipPoint.dx, tipPoint.dy)
      ..lineTo(
        tipPoint.dx - 9 * math.cos(centerRad - 0.55),
        tipPoint.dy - 9 * math.sin(centerRad - 0.55),
      )
      ..lineTo(
        tipPoint.dx - 5 * math.cos(centerRad),
        tipPoint.dy - 5 * math.sin(centerRad),
      )
      ..lineTo(
        tipPoint.dx - 9 * math.cos(centerRad + 0.55),
        tipPoint.dy - 9 * math.sin(centerRad + 0.55),
      )
      ..close();

    final arrowPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, arrowPaint);

    // Dezent leuchtender Glühpunkt hinter der Pfeilspitze
    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(laserEnd, 6.0, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _DeviceHeadingBeamPainter oldDelegate) {
    return oldDelegate.headingDeg != headingDeg ||
        oldDelegate.beamLength != beamLength ||
        oldDelegate.beamAngleDeg != beamAngleDeg ||
        oldDelegate.accentColor != accentColor;
  }
}
