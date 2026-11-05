import 'dart:math' as math;
import 'package:flutter/material.dart';

class FieldScanPulse extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const FieldScanPulse({
    super.key,
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
          painter: RadarSweepPainter(
            progress: animation.value,
            color: color,
          ),
        );
      },
    );
  }
}

class RadarSweepPainter extends CustomPainter {
  final double progress;
  final Color color;

  const RadarSweepPainter({
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

    // 2. Konzentrische Distanzringe (38%, 68%, 100%)
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
  bool shouldRepaint(covariant RadarSweepPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
