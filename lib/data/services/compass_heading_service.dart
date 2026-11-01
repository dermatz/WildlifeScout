import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

class CompassHeadingData {
  final double heading; // 0.0 bis 360.0 Grad (0 = Norden, 90 = Osten)
  final double continuousHeading; // Für ruckelfreie Animation ohne 360°-Sprung
  final double? accuracy;
  final bool hasSensor;

  const CompassHeadingData({
    required this.heading,
    required this.continuousHeading,
    this.accuracy,
    required this.hasSensor,
  });

  String get cardinalLabel {
    const directions = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
    final idx = ((heading + 22.5) % 360 / 45).floor();
    return directions[idx % 8];
  }
}

/// Service zur Ermittlung der tatsächlichen Blickrichtung (Gerätekurs / Magnetometer)
/// im Gelände. Filtert und glättet Sensordaten für ruckelfreie Kompass-Drehung.
class CompassHeadingService {
  static Stream<CompassHeadingData>? _headingStream;

  /// Liefert einen geglätteten Stream des aktuellen Gerätekurses.
  static Stream<CompassHeadingData> get stream {
    _headingStream ??= _buildHeadingStream();
    return _headingStream!;
  }

  static Stream<CompassHeadingData> _buildHeadingStream() {
    late StreamController<CompassHeadingData> controller;
    StreamSubscription<CompassEvent>? sub;

    double continuousHeading = 0.0;
    double? lastRawHeading;

    controller = StreamController<CompassHeadingData>.broadcast(
      onListen: () {
        try {
          final events = FlutterCompass.events;
          if (events == null) {
            controller.add(
              const CompassHeadingData(
                heading: 0.0,
                continuousHeading: 0.0,
                hasSensor: false,
              ),
            );
            return;
          }

          sub = events.listen(
            (event) {
              final raw = event.heading;
              if (raw == null) {
                controller.add(
                  const CompassHeadingData(
                    heading: 0.0,
                    continuousHeading: 0.0,
                    hasSensor: false,
                  ),
                );
                return;
              }

              // Normalisiere auf 0..360
              final normalized = (raw % 360.0 + 360.0) % 360.0;

              if (lastRawHeading != null) {
                double diff = normalized - lastRawHeading!;
                if (diff < -180.0) diff += 360.0;
                if (diff > 180.0) diff -= 360.0;
                continuousHeading += diff;
              } else {
                continuousHeading = normalized;
              }
              lastRawHeading = normalized;

              controller.add(
                CompassHeadingData(
                  heading: normalized,
                  continuousHeading: continuousHeading,
                  accuracy: event.accuracy,
                  hasSensor: true,
                ),
              );
            },
            onError: (err) {
              debugPrint('CompassHeadingService error: $err');
              controller.add(
                const CompassHeadingData(
                  heading: 0.0,
                  continuousHeading: 0.0,
                  hasSensor: false,
                ),
              );
            },
          );
        } catch (e) {
          debugPrint('CompassHeadingService initialize error: $e');
          controller.add(
            const CompassHeadingData(
              heading: 0.0,
              continuousHeading: 0.0,
              hasSensor: false,
            ),
          );
        }
      },
      onCancel: () {
        sub?.cancel();
        sub = null;
        _headingStream = null;
      },
    );

    return controller.stream;
  }
}
