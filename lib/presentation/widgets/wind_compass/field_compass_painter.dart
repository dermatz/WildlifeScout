import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import 'wind_compass_models.dart';

class FieldCompassPainter extends CustomPainter {
  final double windDirectionDeg;
  final double windSpeedKmh;
  final String windCardinal;
  final double scentDirectionDeg;
  final double scentConeAngleDeg;
  final double scentDistanceMeters;
  final List<TargetBearingInfo> targetBearings;

  FieldCompassPainter({
    required this.windDirectionDeg,
    required this.windSpeedKmh,
    required this.windCardinal,
    required this.scentDirectionDeg,
    required this.scentConeAngleDeg,
    required this.scentDistanceMeters,
    required this.targetBearings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dialRadius = size.width / 2 - 20;

    // 1. Hintergrundkreis mit radialem Farbverlauf
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF141F1A),
          const Color(0xFF090E0C),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, bgPaint);

    // Feine konzentrische Entfernungs-Ringe (33%, 66%, 100%)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, dialRadius * 0.35, gridPaint);
    canvas.drawCircle(center, dialRadius * 0.68, gridPaint);
    canvas.drawCircle(center, dialRadius, gridPaint);

    // 2. Sicherer Annäherungssektor (Gegenwind: windDirectionDeg ± 45°)
    _drawSafeApproachSector(canvas, center, dialRadius);

    // 3. Witterungskegel (scentDirectionDeg ± scentConeAngleDeg / 2)
    _drawScentCone(canvas, center, dialRadius);

    // 4. Gradskala, Ticks & Kardinalbeschriftungen (0°–360°)
    _drawCompassDial(canvas, center, dialRadius);

    // 5. Einströmender Windvektor (Pfeil von außen zum Zentrum)
    _drawWindInflowVector(canvas, center, dialRadius);

    // 6. Peilungs-Pins für Habitate & Spots
    _drawTargetBearings(canvas, center, dialRadius);

    // 7. Zentraler Beobachter- / Fotospot-Hub
    _drawCenterHub(canvas, center);
  }

  void _drawScentCone(Canvas canvas, Offset center, double radius) {
    final halfCone = scentConeAngleDeg / 2.0;
    final startDeg = scentDirectionDeg - halfCone;
    final sweepDeg = scentConeAngleDeg;

    final startRad = _degToCanvasRad(startDeg);
    final sweepRad = sweepDeg * (math.pi / 180.0);

    final conePath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius - 3),
        startRad,
        sweepRad,
        false,
      )
      ..close();

    // Roter Witterungs-Fächer
    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.10),
          WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.42),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;
    canvas.drawPath(conePath, fillPaint);

    // Roter Randbogen am Perimeter
    final arcPaint = Paint()
      ..color = WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 3),
      startRad,
      sweepRad,
      false,
      arcPaint,
    );

    // Witterungs-Zentrumslinie
    final scentRad = _degToCanvasRad(scentDirectionDeg);
    final centerLinePaint = Paint()
      ..color = WildlifeScoutTheme.crimsonScent.withValues(alpha: 0.7)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      center,
      Offset(
        center.dx + (radius - 5) * math.cos(scentRad),
        center.dy + (radius - 5) * math.sin(scentRad),
      ),
      centerLinePaint,
    );
  }

  void _drawSafeApproachSector(Canvas canvas, Offset center, double radius) {
    const sweepDeg = 90.0; // 90° Sektor (Gegenwind ± 45°)
    final startDeg = windDirectionDeg - 45.0;

    final startRad = _degToCanvasRad(startDeg);
    final sweepRad = sweepDeg * (math.pi / 180.0);

    final safePath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius - 3),
        startRad,
        sweepRad,
        false,
      )
      ..close();

    // Smaragdgrüner Fächer
    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.08),
          WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.28),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;
    canvas.drawPath(safePath, fillPaint);

    // Grüner Randbogen
    final arcPaint = Paint()
      ..color = WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 3),
      startRad,
      sweepRad,
      false,
      arcPaint,
    );
  }

  void _drawCompassDial(Canvas canvas, Offset center, double radius) {
    // Äußerer Metall-Ring
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, ringPaint);

    // Teilungsstriche alle 10°
    final tickPaint = Paint()..style = PaintingStyle.stroke;

    for (int deg = 0; deg < 360; deg += 10) {
      final rad = _degToCanvasRad(deg.toDouble());
      final isMajor = deg % 30 == 0;
      final isCardinal = deg % 90 == 0;

      final tickLength = isCardinal ? 9.0 : (isMajor ? 6.0 : 3.5);
      tickPaint.strokeWidth = isCardinal ? 2.0 : (isMajor ? 1.4 : 0.9);
      tickPaint.color = isCardinal
          ? (deg == 0 ? WildlifeScoutTheme.crimsonScent : Colors.white)
          : (isMajor ? Colors.white70 : Colors.white24);

      final p1 = Offset(
        center.dx + (radius - tickLength) * math.cos(rad),
        center.dy + (radius - tickLength) * math.sin(rad),
      );
      final p2 = Offset(
        center.dx + radius * math.cos(rad),
        center.dy + radius * math.sin(rad),
      );
      canvas.drawLine(p1, p2, tickPaint);

      // Gradzahlen alle 30° (außer Cardinals, um Überlappung zu vermeiden)
      if (isMajor && !isCardinal) {
        _drawText(
          canvas: canvas,
          text: '$deg°',
          center: Offset(
            center.dx + (radius - 18) * math.cos(rad),
            center.dy + (radius - 18) * math.sin(rad),
          ),
          style: TextStyle(
            fontSize: 9.0,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        );
      }
    }

    // Kardinal-Punkte N, O, S, W & Zwischenkardinäle NO, SO, SW, NW
    final cardinals = [
      (0, 'N', WildlifeScoutTheme.crimsonScent, 13.5, FontWeight.w900),
      (45, 'NO', WildlifeScoutTheme.textMuted, 11.0, FontWeight.w700),
      (90, 'O', Colors.white, 12.5, FontWeight.w800),
      (135, 'SO', WildlifeScoutTheme.textMuted, 11.0, FontWeight.w700),
      (180, 'S', Colors.white, 12.5, FontWeight.w800),
      (225, 'SW', WildlifeScoutTheme.textMuted, 11.0, FontWeight.w700),
      (270, 'W', Colors.white, 12.5, FontWeight.w800),
      (315, 'NW', WildlifeScoutTheme.textMuted, 11.0, FontWeight.w700),
    ];

    for (final (deg, label, color, fontSize, weight) in cardinals) {
      final rad = _degToCanvasRad(deg.toDouble());
      final offsetDist = deg % 90 == 0 ? 16.0 : 15.0;
      _drawText(
        canvas: canvas,
        text: label,
        center: Offset(
          center.dx + (radius - offsetDist) * math.cos(rad),
          center.dy + (radius - offsetDist) * math.sin(rad),
        ),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
        ),
      );
    }
  }

  void _drawWindInflowVector(Canvas canvas, Offset center, double radius) {
    final windRad = _degToCanvasRad(windDirectionDeg);

    // Wind strömt von außen nach innen
    final outerP = Offset(
      center.dx + (radius - 1) * math.cos(windRad),
      center.dy + (radius - 1) * math.sin(windRad),
    );
    final innerP = Offset(
      center.dx + (radius * 0.38) * math.cos(windRad),
      center.dy + (radius * 0.38) * math.sin(windRad),
    );

    // Pfeil-Schaft
    final arrowPaint = Paint()
      ..color = WildlifeScoutTheme.cyanWater
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(outerP, innerP, arrowPaint);

    // Pfeil-Spitze am inneren Ende (zeigt in Richtung Zentrum)
    final headAngle = windRad + math.pi;
    const headLen = 12.0;
    const spread = 0.45;

    final tipPath = Path()
      ..moveTo(innerP.dx, innerP.dy)
      ..lineTo(
        innerP.dx + headLen * math.cos(headAngle + spread),
        innerP.dy + headLen * math.sin(headAngle + spread),
      )
      ..lineTo(
        innerP.dx + headLen * math.cos(headAngle - spread),
        innerP.dy + headLen * math.sin(headAngle - spread),
      )
      ..close();

    final tipPaint = Paint()
      ..color = WildlifeScoutTheme.cyanWater
      ..style = PaintingStyle.fill;
    canvas.drawPath(tipPath, tipPaint);

    // Äußere Windmarkierung (Leuchtender Cyan-Punkt an der Peripherie)
    final beaconPaint = Paint()
      ..color = WildlifeScoutTheme.cyanWater
      ..style = PaintingStyle.fill;
    canvas.drawCircle(outerP, 4.5, beaconPaint);

    final glowPaint = Paint()
      ..color = WildlifeScoutTheme.cyanWater.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(outerP, 9.0, glowPaint);
  }

  void _drawTargetBearings(Canvas canvas, Offset center, double radius) {
    for (final target in targetBearings) {
      final rad = _degToCanvasRad(target.bearingDeg);
      final pinOffset = Offset(
        center.dx + (radius - 8) * math.cos(rad),
        center.dy + (radius - 8) * math.sin(rad),
      );

      Color color;
      switch (target.status) {
        case ScentStatus.scentContaminated:
          color = WildlifeScoutTheme.crimsonScent;
          break;
        case ScentStatus.safeHeadwind:
          color = WildlifeScoutTheme.emeraldBio;
          break;
        case ScentStatus.crosswind:
          color = WildlifeScoutTheme.amberGold;
          break;
      }

      // Marker-Punkt mit dezentem Ring
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pinOffset, target.isPrimary ? 4.5 : 3.5, dotPaint);

      final ringPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(pinOffset, target.isPrimary ? 4.5 : 3.5, ringPaint);
    }
  }

  void _drawCenterHub(Canvas canvas, Offset center) {
    // Fadenkreuz
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx - 12, center.dy),
      Offset(center.dx + 12, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 12),
      Offset(center.dx, center.dy + 12),
      crossPaint,
    );

    // Zentraler Fotospot
    final hubBg = Paint()
      ..color = WildlifeScoutTheme.bgObsidian
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 9, hubBg);

    final hubBorder = Paint()
      ..color = WildlifeScoutTheme.emeraldBio
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 9, hubBorder);

    final centerDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 2.5, centerDot);
  }

  static void _drawText({
    required Canvas canvas,
    required String text,
    required Offset center,
    required TextStyle style,
  }) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);
  }

  /// Rechnet nautische/meteorologische Grad (0° = Norden, im Uhrzeigersinn)
  /// in Standard-Canvas-Bogenmaß um (0 rad = 90° Osten, im Uhrzeigersinn).
  static double _degToCanvasRad(double deg) {
    return (deg - 90.0) * (math.pi / 180.0);
  }

  @override
  bool shouldRepaint(covariant FieldCompassPainter oldDelegate) {
    return oldDelegate.windDirectionDeg != windDirectionDeg ||
        oldDelegate.windSpeedKmh != windSpeedKmh ||
        oldDelegate.scentDirectionDeg != scentDirectionDeg ||
        oldDelegate.scentConeAngleDeg != scentConeAngleDeg ||
        oldDelegate.scentDistanceMeters != scentDistanceMeters ||
        oldDelegate.targetBearings != targetBearings;
  }
}
