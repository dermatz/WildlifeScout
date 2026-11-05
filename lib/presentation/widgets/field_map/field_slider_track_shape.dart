import 'package:flutter/material.dart';
import '../../../core/theme/wildlifescout_theme.dart';
import '../../../domain/models/species_profile.dart';
import '../../../domain/services/sun_moon_calculator.dart';

/// Maßgeschneiderte Feld-Slider-Spur (Apple HIG konform), die im Hintergrund
/// einen nahtlosen Farbverlauf für Nacht, Blaue Stunde, Goldene Stunde und Tageslicht
/// (berechnet über den offline Sonnenstands-Rechner) über die volle Breite darstellt
/// und bei 'Heute' eine dezente vertikale Linie samt Pfeil & "JETZT"-Markierung für
/// die minutengenaue Echtzeit einzeichnet.
class FieldSliderTrackShape extends RoundedRectSliderTrackShape {
  final double? nowFraction;
  final DateTime? referenceDate;
  final double? latitude;
  final double? longitude;

  const FieldSliderTrackShape({
    this.nowFraction,
    this.referenceDate,
    this.latitude,
    this.longitude,
  });

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 14.0;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    // Der Slider nutzt die volle verfügbare Breite des Containers ohne künstlichen Overlay-Versatz
    return Rect.fromLTWH(
      offset.dx,
      trackTop,
      parentBox.size.width,
      trackHeight,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    // Falls das Slider-Theme 0-Höhe hat, frühzeitig abbrechen
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final trackLeft = trackRect.left;
    final trackWidth = trackRect.width;
    final canvas = context.canvas;
    final trackRRect = RRect.fromRectAndRadius(
      trackRect,
      Radius.circular(trackRect.height / 2),
    );

    // 1. Hintergrund-Track mit astronomischem Lichtphasen-Farbverlauf
    // (Nacht -> Blaue Stunde -> Goldene Stunde -> Tag -> Goldene Stunde -> Blaue Stunde -> Nacht)
    final gradientColors = <Color>[];
    final gradientStops = <double>[];

    final ref = referenceDate ?? DateTime.now();
    final lat = latitude ?? 51.1657;
    final lon = longitude ?? 10.4515;

    // 49 Stützstellen (alle 30 Min.) für einen seidig-weichen, leuchtenden Übergang
    const sampleCount = 49;
    for (int i = 0; i < sampleCount; i++) {
      final stop = i / (sampleCount - 1);
      final minutesFromMidnight =
          (i * (24 * 60 - 1) / (sampleCount - 1)).round();
      final sampleHour = minutesFromMidnight ~/ 60;
      final sampleMin = minutesFromMidnight % 60;
      final sampleTime =
          DateTime(ref.year, ref.month, ref.day, sampleHour, sampleMin);
      final astroPos = SunMoonCalculator.calculate(
        dateTime: sampleTime,
        latitude: lat,
        longitude: lon,
      );

      Color color;
      if (astroPos.isGoldenHour) {
        color = const Color(0xFFF59E0B); // Strahlendes Gold / Bernstein (Dämmerung)
      } else if (astroPos.isBlueHour) {
        color = const Color(0xFF2563EB); // Intensives Dämmerungs-Blau (Blaue Stunde)
      } else if (astroPos.currentPeriod == ActivityPeriod.night) {
        color = const Color(0xFF1E293B); // Nacht-Anthrazit / Slate (klar erkennbare Nacht)
      } else {
        color = const Color(0xFF0D9488); // Frisches Tages-Türkis / Smaragd (volles Tageslicht)
      }

      gradientColors.add(color);
      gradientStops.add(stop);
    }

    final gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: gradientColors,
        stops: gradientStops,
      ).createShader(trackRect);

    // Gestochen scharfer Clip auf den abgerundeten Track
    canvas.save();
    canvas.clipRRect(trackRRect);

    // Zeichne den Lichtphasen-Farbverlauf über die volle Breite (ohne abdunkelndes Overlay,
    // damit der gesamte 24h-Tageslichtzyklus auf einen Blick klar sichtbar ist)
    canvas.drawRRect(trackRRect, gradientPaint);

    canvas.restore();

    // 2. Subtiler Umrissrand (Apple HIG Outline) für perfekte Konturenschärfe
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(trackRRect, borderPaint);

    final padding = isRounded ? trackRect.height : 0.0;
    final trackCenterY = trackRect.center.dy;
    final halfTrackH = trackRect.height / 2;

    // 3. Optional: JETZT-Indikator bei heutigem Datum
    if (nowFraction != null && nowFraction! >= 0 && nowFraction! <= 23) {
      final visualPosition = (nowFraction! / 23.0).clamp(0.0, 1.0);
      final calculatedX = isDiscrete
          ? trackLeft + visualPosition * (trackWidth - padding) + padding / 2
          : trackLeft + visualPosition * trackWidth;

      // Wenn der Slider auf der Jetzt-Position steht, richten wir den Marker
      // exakt auf thumbCenter.dx aus, um Rundungsdifferenzen vollständig zu vermeiden.
      final nowX = (calculatedX - thumbCenter.dx).abs() < 1.0
          ? thumbCenter.dx
          : calculatedX;
      final markerTop = trackCenterY - halfTrackH - 2.5;
      final markerBottom = trackCenterY + halfTrackH + 2.5;

      // 3.1 Sanfter Glow-Effekt für hohe Sichtbarkeit im Nacht- & Tarnmodus
      final glowPaint = Paint()
        ..color = WildlifeScoutTheme.amberGold.withValues(alpha: 0.35)
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(nowX, markerTop - 1.0),
        Offset(nowX, markerBottom + 1.0),
        glowPaint,
      );

      // 3.2 Präzise vertikale Markierungslinie über den Schieberegler-Track
      final linePaint = Paint()
        ..color = WildlifeScoutTheme.amberGold
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(nowX, markerTop),
        Offset(nowX, markerBottom),
        linePaint,
      );

      // 3.3 Nach unten zeigender Markierungs-Pfeil (Indikator)
      final arrowTipY = markerTop;
      final arrowBaseY = arrowTipY - 5.0;
      final arrowPath = Path()
        ..moveTo(nowX, arrowTipY)
        ..lineTo(nowX - 3.5, arrowBaseY)
        ..lineTo(nowX + 3.5, arrowBaseY)
        ..close();
      final arrowPaint = Paint()
        ..color = WildlifeScoutTheme.amberGold
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowPath, arrowPaint);

      // 3.4 Kompakter "JETZT"-Schriftzug über dem Pfeil
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'JETZT',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            color: WildlifeScoutTheme.amberGold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final textX = (nowX - textPainter.width / 2).clamp(
        trackLeft,
        trackRect.right - textPainter.width,
      );
      textPainter.paint(
        canvas,
        Offset(textX, arrowBaseY - textPainter.height - 2.0),
      );
    }

    // 4. Astronomische Markierungen für Sonnenaufgang & Sonnenuntergang
    final sunTimes = SunMoonCalculator.calculateSunTimes(
      date: ref,
      latitude: lat,
      longitude: lon,
    );

    void drawSunMarker({
      required DateTime time,
      required bool isSunrise,
    }) {
      final timeFraction = (time.hour + time.minute / 60.0).clamp(0.0, 23.0);
      final visualPosition = (timeFraction / 23.0).clamp(0.0, 1.0);
      final markerX = isDiscrete
          ? trackLeft + visualPosition * (trackWidth - padding) + padding / 2
          : trackLeft + visualPosition * trackWidth;

      final markerColor = isSunrise
          ? const Color(0xFFFDE047) // Strahlendes Morgensonne-Goldgelb
          : const Color(0xFFFB923C); // Warmes Abendrot-Orange

      final markerTop = trackCenterY - halfTrackH;
      final markerBottom = trackCenterY + halfTrackH;

      // 4.1 Weicher Glow für hohe Ablesbarkeit
      final markerGlow = Paint()
        ..color = markerColor.withValues(alpha: 0.35)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(markerX, markerTop - 1.0),
        Offset(markerX, markerBottom + 1.0),
        markerGlow,
      );

      // 4.2 Präzise vertikale Haarlinie über den Schieberegler
      final markerLinePaint = Paint()
        ..color = markerColor
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(markerX, markerTop),
        Offset(markerX, markerBottom),
        markerLinePaint,
      );

      // 4.3 Nach oben zeigender Indikator-Pfeil unterhalb der Spur
      final arrowTipY = markerBottom + 1.5;
      final arrowBaseY = arrowTipY + 4.0;
      final arrowPath = Path()
        ..moveTo(markerX, arrowTipY)
        ..lineTo(markerX - 3.0, arrowBaseY)
        ..lineTo(markerX + 3.0, arrowBaseY)
        ..close();
      final arrowPaint = Paint()
        ..color = markerColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowPath, arrowPaint);

      // 4.4 Zeit-Badge unter dem Pfeil (z.B. "☼ 07:05" bzw. "☾ 16:34")
      final timeStr =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      final symbol = isSunrise ? '☼' : '☾';

      final labelPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$symbol ',
              style: TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.w900,
                color: markerColor,
              ),
            ),
            TextSpan(
              text: timeStr,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: markerColor,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final textX = (markerX - labelPainter.width / 2).clamp(
        trackLeft,
        trackRect.right - labelPainter.width,
      );
      labelPainter.paint(
        canvas,
        Offset(textX, arrowBaseY + 1.5),
      );
    }

    if (sunTimes.sunrise != null) {
      drawSunMarker(time: sunTimes.sunrise!, isSunrise: true);
    }
    if (sunTimes.sunset != null) {
      drawSunMarker(time: sunTimes.sunset!, isSunrise: false);
    }
  }
}
