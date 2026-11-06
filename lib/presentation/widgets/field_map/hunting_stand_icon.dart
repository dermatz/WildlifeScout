import 'package:flutter/material.dart';

/// Stil-Variante für das Hochsitz-Symbol
enum HuntingStandIconStyle {
  /// Echtes Ansitzkanzel-Piktogramm (Pultdach, Kanzel mit Sehschlitz, Ständerbau & Aufstiegsleiter)
  towerStand,

  /// Taktisches Jagd-Fadenkreuz / Reticle (Targeting-Kreis mit Haarlinien & Center-Dot)
  crosshair,
}

/// Maßgeschneidertes forstliches Vektor-Icon für Hochsitze & Jägerstände:
/// Unterstützt entweder das charakteristische Ansitzkanzel-Piktogramm mit Leiter
/// oder ein präzises forstliches Fadenkreuz (Crosshair / Reticle).
class HuntingStandIcon extends StatelessWidget {
  final double size;
  final Color color;
  final HuntingStandIconStyle style;

  const HuntingStandIcon({
    super.key,
    this.size = 20.0,
    this.color = const Color(0xFFF59E0B),
    this.style = HuntingStandIconStyle.towerStand,
  });

  const HuntingStandIcon.crosshair({
    super.key,
    this.size = 20.0,
    this.color = const Color(0xFFF59E0B),
  }) : style = HuntingStandIconStyle.crosshair;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: style == HuntingStandIconStyle.towerStand
            ? _HuntingTowerPainter(color: color)
            : _CrosshairPainter(color: color),
      ),
    );
  }
}

/// Maler für die klassische forstliche Ansitzkanzel (zentrierter Hochsitz)
class _HuntingTowerPainter extends CustomPainter {
  final Color color;

  const _HuntingTowerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final thinStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    // 1. Schräges Pultdach der Ansitzkanzel (symmetrisch zentriert)
    final roofPath = Path()
      ..moveTo(4.5, 5.0)
      ..lineTo(19.5, 3.2)
      ..lineTo(19.5, 5.2)
      ..lineTo(5.2, 6.6)
      ..close();
    canvas.drawPath(roofPath, fillPaint);

    // 2. Kanzelkorpus (zentrierter Kasten von x: 5.8 bis 18.2, y: 6.0 bis 13.0)
    final cabinRect = RRect.fromRectAndRadius(
      const Rect.fromLTRB(5.8, 6.0, 18.2, 13.0),
      const Radius.circular(0.8),
    );
    canvas.drawRRect(cabinRect, fillPaint);

    // 2b. Ausgeschnittenes Sehschlitz-Fenster
    final windowPaint = Paint()..blendMode = BlendMode.clear;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(7.6, 7.5, 16.4, 9.7),
        const Radius.circular(0.5),
      ),
      windowPaint,
    );

    // 3. Plattformboden
    canvas.drawLine(
      const Offset(4.8, 13.0),
      const Offset(19.2, 13.0),
      strokePaint..strokeWidth = 1.5,
    );

    // 4. Kanzel-Standbeine (leicht nach außen ausgestellt für hohe Stabilität)
    // Linkes Kanzelbein
    canvas.drawLine(
      const Offset(6.8, 13.5),
      const Offset(5.4, 22.5),
      strokePaint..strokeWidth = 1.4,
    );
    // Rechtes Kanzelbein
    canvas.drawLine(
      const Offset(17.2, 13.5),
      const Offset(18.6, 22.5),
      strokePaint..strokeWidth = 1.4,
    );

    // Diagonale Holz-Verstrebung (Andreaskreuz zur Aussteifung)
    canvas.drawLine(
      const Offset(6.5, 14.8),
      const Offset(17.5, 21.5),
      thinStrokePaint,
    );
    canvas.drawLine(
      const Offset(17.5, 14.8),
      const Offset(6.5, 21.5),
      thinStrokePaint,
    );

    // Querriegel oben & unten
    canvas.drawLine(
      const Offset(6.6, 17.5),
      const Offset(17.4, 17.5),
      thinStrokePaint,
    );
    canvas.drawLine(
      const Offset(5.0, 22.2),
      const Offset(19.0, 22.2),
      strokePaint..strokeWidth = 1.4,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HuntingTowerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Maler für ein taktisches Fadenkreuz (Jagd-Reticle / Crosshair)
class _CrosshairPainter extends CustomPainter {
  final Color color;

  const _CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final centerDotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const center = Offset(12.0, 12.0);

    // Äußerer Zielkreis
    canvas.drawCircle(center, 7.5, ringPaint);

    // Innerer Zielpunkt
    canvas.drawCircle(center, 1.4, centerDotPaint);

    // Vier Fadenkreuz-Striche (oben, unten, links, rechts)
    // mit Freiraum um den inneren Kern
    // Oben
    canvas.drawLine(const Offset(12.0, 1.5), const Offset(12.0, 6.0), linePaint);
    // Unten
    canvas.drawLine(const Offset(12.0, 18.0), const Offset(12.0, 22.5), linePaint);
    // Links
    canvas.drawLine(const Offset(1.5, 12.0), const Offset(6.0, 12.0), linePaint);
    // Rechts
    canvas.drawLine(const Offset(18.0, 12.0), const Offset(22.5, 12.0), linePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
