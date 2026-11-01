import 'dart:async';
import 'dart:js_interop';
import 'package:latlong2/latlong.dart';
import 'package:web/web.dart' as web;

Future<LatLng?> getBrowserGeolocation() async {
  final highAccuracy = await _requestPosition(
    enableHighAccuracy: true,
    timeoutMs: 6000,
    maximumAgeMs: 60000,
  );
  if (highAccuracy != null) return highAccuracy;

  // Fallback auf WLAN-/Netzwerk-Ortung des Browsers, falls GPS am Desktop/Mac
  // zu lange braucht oder nicht verfügbar ist.
  return _requestPosition(
    enableHighAccuracy: false,
    timeoutMs: 5000,
    maximumAgeMs: 300000,
  );
}

Future<LatLng?> _requestPosition({
  required bool enableHighAccuracy,
  required int timeoutMs,
  required int maximumAgeMs,
}) {
  final completer = Completer<LatLng?>();

  try {
    final geolocation = web.window.navigator.geolocation;

    void onSuccess(web.GeolocationPosition pos) {
      if (!completer.isCompleted) {
        final coords = pos.coords;
        completer.complete(LatLng(coords.latitude, coords.longitude));
      }
    }

    void onError(web.GeolocationPositionError err) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }

    geolocation.getCurrentPosition(
      onSuccess.toJS,
      onError.toJS,
      web.PositionOptions(
        enableHighAccuracy: enableHighAccuracy,
        timeout: timeoutMs,
        maximumAge: maximumAgeMs,
      ),
    );
  } catch (_) {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }

  return completer.future.timeout(
    Duration(milliseconds: timeoutMs + 1000),
    onTimeout: () => null,
  );
}
