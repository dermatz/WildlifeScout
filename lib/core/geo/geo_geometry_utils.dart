import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Reusable spatial and mathematical geometry algorithms for wildlife habitat analysis.
class GeoGeometryUtils {
  static const Distance distance = Distance();

  /// Berechnet die reale Fläche eines Polygons in Hektar (1 ha = 10.000 m²).
  static double computePolygonAreaHectares(List<LatLng> pts) {
    if (pts.length < 3) return 0.0;
    final ref = pts.first;
    final cosLat = math.cos(ref.latitude * math.pi / 180.0);
    const double mLat = 111320.0;
    final double mLon = 111320.0 * cosLat;

    double areaSqMeters = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % pts.length];
      final x1 = (p1.longitude - ref.longitude) * mLon;
      final y1 = (p1.latitude - ref.latitude) * mLat;
      final x2 = (p2.longitude - ref.longitude) * mLon;
      final y2 = (p2.latitude - ref.latitude) * mLat;
      areaSqMeters += (x1 * y2 - x2 * y1);
    }
    return (areaSqMeters.abs() * 0.5) / 10000.0;
  }

  /// Berechnet die maximale Spannweite (Diagonale der Bounding Box) in Metern.
  static double computeMaxSpanMeters(List<LatLng> pts) {
    if (pts.length < 2) return 0.0;
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    return distance.as(
      LengthUnit.Meter,
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );
  }

  /// Prüft per Ray-Casting-Verfahren, ob ein Punkt innerhalb eines Polygons liegt.
  static bool isPointInPolygon(LatLng pt, List<LatLng> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].latitude, yi = polygon[i].longitude;
      final xj = polygon[j].latitude, yj = polygon[j].longitude;
      final intersect =
          ((yi > pt.longitude) != (yj > pt.longitude)) &&
          (pt.latitude <
              (xj - xi) * (pt.longitude - yi) / (yj - yi + 1e-12) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Erstellt ein Kreis-Polygon um ein Zentrum mit gegebenem Radius.
  static List<LatLng> buildCirclePolygon(
    LatLng center, {
    required double radiusMeters,
  }) {
    const int steps = 16;
    return List.generate(
      steps,
      (i) => distance.offset(center, radiusMeters, (i * 360.0 / steps) % 360.0),
    );
  }

  /// Schneidet ein zu großes Polygon auf ein zusammenhängendes Teilsegment zu.
  static List<LatLng> clipLargePolygonAroundEdge(
    List<LatLng> pts, {
    required LatLng origin,
    required double maxSpanMeters,
    required double Function(LatLng pt) distanceToForests,
  }) {
    if (pts.length <= 20 || computeMaxSpanMeters(pts) <= maxSpanMeters * 1.15) {
      return pts;
    }

    // Geschlossenes Ring-Ende ohne doppelten Schlussknoten betrachten
    final ring =
        pts.length >= 4 &&
            distance.as(LengthUnit.Meter, pts.first, pts.last) < 2.0
        ? pts.sublist(0, pts.length - 1)
        : pts;
    if (ring.length < 4) return pts;

    int bestIdx = 0;
    double bestMetric = double.infinity;

    final step = math.max(1, ring.length ~/ 24);
    for (int i = 0; i < ring.length; i += step) {
      final dOrigin = distance.as(LengthUnit.Meter, origin, ring[i]);
      final dForest = distanceToForests(ring[i]);
      final combined = dOrigin * 0.6 + dForest * 0.4;
      if (combined < bestMetric) {
        bestMetric = combined;
        bestIdx = i;
      }
    }

    final anchor = ring[bestIdx];
    // Zusammenhängendes Ring-Segment um bestIdx herum extrahieren (verhindert Sprünge über die Polygon-Naht!)
    final contiguous = <LatLng>[anchor];
    final maxSideSteps = ring.length ~/ 2;

    for (int offset = 1; offset <= maxSideSteps; offset++) {
      final nextPt = ring[(bestIdx + offset) % ring.length];
      if (distance.as(LengthUnit.Meter, anchor, nextPt) <= maxSpanMeters) {
        contiguous.add(nextPt);
      } else {
        break;
      }
    }

    final backPts = <LatLng>[];
    for (int offset = 1; offset < maxSideSteps; offset++) {
      final prevPt = ring[(bestIdx - offset + ring.length) % ring.length];
      if (distance.as(LengthUnit.Meter, anchor, prevPt) <= maxSpanMeters) {
        backPts.add(prevPt);
      } else {
        break;
      }
    }

    final combinedRing = [...backPts.reversed, ...contiguous];
    if (combinedRing.length < 4) {
      return computeConvexHull(ring.take(24).toList());
    }
    return hasPolygonSelfIntersection(combinedRing)
        ? computeConvexHull(combinedRing)
        : combinedRing;
  }

  /// Baut einen sauberen, überschneidungsfreien Saum-Korridor entlang einer Linie.
  ///
  /// Wichtig: Am letzten Punkt muss die Vorwärtsrichtung (`pts[i - 1] -> pts[i]`)
  /// beibehalten werden (statt `pts[i] -> pts[i - 1]`), da sonst Links- und Rechts-Normale
  /// am Ende um 180° vertauscht werden und eine verkreuzte „Sanduhr“-Form entsteht!
  static List<LatLng> buildCorridorPolygonAlongLine(
    List<LatLng> line, {
    required double widthMeters,
  }) {
    if (line.length < 2) return [];

    // 1. Zu eng beieinander liegende Zwischenpunkte (< 14 m) bereinigen,
    //    damit scharfe Mikro-Knicke beim Versetzen um `widthMeters` keine Schleifen werfen.
    final cleaned = <LatLng>[line.first];
    for (int i = 1; i < line.length && cleaned.length < 14; i++) {
      final d = distance.as(LengthUnit.Meter, cleaned.last, line[i]);
      if (d >= 14.0 || (i == line.length - 1 && d >= 2.0)) {
        cleaned.add(line[i]);
      }
    }
    if (cleaned.length < 2) return [];

    // 2. Vorwärts-Peilung (Bearing) für jedes Liniensegment berechnen
    final segBearings = <double>[];
    for (int i = 0; i < cleaned.length - 1; i++) {
      segBearings.add(distance.bearing(cleaned[i], cleaned[i + 1]));
    }

    final leftSide = <LatLng>[];
    final rightSide = <LatLng>[];

    for (int i = 0; i < cleaned.length; i++) {
      final double forwardBearing;
      if (i == 0) {
        forwardBearing = segBearings.first;
      } else if (i == cleaned.length - 1) {
        // Vorwärtsrichtung vom vorletzten zum letzten Punkt beibehalten!
        forwardBearing = segBearings.last;
      } else {
        // Winkelhalbierende der beiden angrenzenden Segmente für sanfte Kurven
        forwardBearing = averageBearingDegrees(
          segBearings[i - 1],
          segBearings[i],
        );
      }

      final normalLeft = (forwardBearing - 90.0 + 360.0) % 360.0;
      final normalRight = (forwardBearing + 90.0 + 360.0) % 360.0;

      leftSide.add(distance.offset(cleaned[i], widthMeters, normalLeft));
      rightSide.add(distance.offset(cleaned[i], widthMeters, normalRight));
    }

    final corridor = [...leftSide, ...rightSide.reversed];
    if (hasPolygonSelfIntersection(corridor)) {
      return computeConvexHull(corridor);
    }
    return corridor;
  }

  /// Berechnet die gemittelte Peilung zweier Richtungsvektoren.
  static double averageBearingDegrees(double b1, double b2) {
    final r1 = b1 * math.pi / 180.0;
    final r2 = b2 * math.pi / 180.0;
    final x = math.cos(r1) + math.cos(r2);
    final y = math.sin(r1) + math.sin(r2);
    if (x.abs() < 1e-6 && y.abs() < 1e-6) return b2;
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  /// Prüft, ob sich Kanten eines Polygons selbst schneiden.
  static bool hasPolygonSelfIntersection(List<LatLng> poly) {
    final n = poly.length;
    if (n < 4) return false;
    for (int i = 0; i < n; i++) {
      final a1 = poly[i];
      final a2 = poly[(i + 1) % n];
      for (int j = i + 2; j < n; j++) {
        // Nachbarkanten teilen einen gemeinsamen Knoten und schneiden sich nicht echt
        if (i == 0 && j == n - 1) continue;
        final b1 = poly[j];
        final b2 = poly[(j + 1) % n];
        if (segmentsProperlyIntersect(a1, a2, b1, b2)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Prüft echten Schnitt zweier Liniensegmente.
  static bool segmentsProperlyIntersect(
    LatLng a,
    LatLng b,
    LatLng c,
    LatLng d,
  ) {
    double ccw(LatLng p1, LatLng p2, LatLng p3) {
      return (p2.longitude - p1.longitude) * (p3.latitude - p1.latitude) -
          (p2.latitude - p1.latitude) * (p3.longitude - p1.longitude);
    }

    final d1 = ccw(a, b, c);
    final d2 = ccw(a, b, d);
    final d3 = ccw(c, d, a);
    final d4 = ccw(c, d, b);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  /// Berechnet die konvexe Hülle einer Punktmenge (Monotone Chain Algorithmus).
  static List<LatLng> computeConvexHull(List<LatLng> pts) {
    if (pts.length <= 3) return pts;
    final sorted = [...pts]..sort((a, b) {
      final cmpLon = a.longitude.compareTo(b.longitude);
      return cmpLon != 0 ? cmpLon : a.latitude.compareTo(b.latitude);
    });

    double cross(LatLng o, LatLng a, LatLng b) {
      return (a.longitude - o.longitude) * (b.latitude - o.latitude) -
          (a.latitude - o.latitude) * (b.longitude - o.longitude);
    }

    final lower = <LatLng>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <LatLng>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// Berechnet den arithmetischen Schwerpunkt (Zentroid) einer Punktmenge.
  static LatLng computeCentroid(List<LatLng> pts) {
    double latSum = 0;
    double lonSum = 0;
    for (final p in pts) {
      latSum += p.latitude;
      lonSum += p.longitude;
    }
    return LatLng(latSum / pts.length, lonSum / pts.length);
  }

  /// Konvertiert eine Himmelsrichtungs-Abkürzung in Grad.
  static double? cardinalToDegrees(String cardinal) {
    switch (cardinal.toUpperCase()) {
      case 'N':
        return 0.0;
      case 'NO':
      case 'NE':
        return 45.0;
      case 'O':
      case 'E':
        return 90.0;
      case 'SO':
      case 'SE':
        return 135.0;
      case 'S':
        return 180.0;
      case 'SW':
        return 225.0;
      case 'W':
        return 270.0;
      case 'NW':
        return 315.0;
      default:
        return null;
    }
  }

  /// Erstellt einen stabilen Cache-Schlüssel für einen Sektor.
  static String sectorKeyFor(LatLng pos) {
    final sLat = (pos.latitude * 120).round();
    final sLon = (pos.longitude * 120).round();
    return '${sLat}_$sLon';
  }

  /// Reduziert die Stützstellen einer Polyline auf maximal `maxVertices`.
  static List<LatLng> simplifyPolylinePoints(
    List<LatLng> pts, {
    required int maxVertices,
  }) {
    if (pts.length <= maxVertices) return pts;
    final result = <LatLng>[pts.first];
    final step = (pts.length - 1) / (maxVertices - 1);
    for (int i = 1; i < maxVertices - 1; i++) {
      result.add(pts[(i * step).round()]);
    }
    result.add(pts.last);
    return result;
  }

  /// Berechnet den exakten kürzesten Abstand (in Metern) von einem Punkt `p`
  /// zu allen Liniensegmenten `[a, b]` eines Polygons oder Weges.
  static double distancePointToPolylineMeters(
    LatLng p,
    List<LatLng> polyline,
  ) {
    if (polyline.isEmpty) return 999.0;
    if (polyline.length == 1) {
      return distance.as(LengthUnit.Meter, p, polyline.first);
    }

    final cosLat = math.cos(p.latitude * math.pi / 180.0);
    const double metersPerDegLat = 111320.0;
    final double metersPerDegLon = 111320.0 * cosLat;

    double minDistSq = double.infinity;

    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];

      final ax = (a.longitude - p.longitude) * metersPerDegLon;
      final ay = (a.latitude - p.latitude) * metersPerDegLat;
      final bx = (b.longitude - p.longitude) * metersPerDegLon;
      final by = (b.latitude - p.latitude) * metersPerDegLat;

      final dx = bx - ax;
      final dy = by - ay;
      final lenSq = dx * dx + dy * dy;

      double t = 0.0;
      if (lenSq > 0.0001) {
        t = (-(ax * dx + ay * dy) / lenSq).clamp(0.0, 1.0);
      }

      final projX = ax + t * dx;
      final projY = ay + t * dy;
      final distSq = projX * projX + projY * projY;
      if (distSq < minDistSq) {
        minDistSq = distSq;
      }
    }

    return math.sqrt(minDistSq);
  }
}
