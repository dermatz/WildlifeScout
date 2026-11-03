import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wildlifescout/data/services/rain_radar_service.dart';

void main() {
  group('RainRadarService Tests', () {
    setUp(() {
      RainRadarService.resetCacheForTesting();
    });

    test('fetchLatestRadarUrlTemplate parses radar response and generates XYZ template', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString() ==
            'https://api.rainviewer.com/public/weather-maps.json') {
          return http.Response(
            jsonEncode({
              'version': '2.0',
              'generated': 1793696421,
              'host': 'https://tilecache.rainviewer.com',
              'radar': {
                'past': [
                  {
                    'time': 1793695800,
                    'path': '/v2/radar/old_step',
                  },
                  {
                    'time': 1793696400,
                    'path': '/v2/radar/latest_step_123',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final template =
          await RainRadarService.fetchLatestRadarUrlTemplate(client: mockClient);

      expect(template, isNotNull);
      expect(
        template,
        'https://tilecache.rainviewer.com/v2/radar/latest_step_123/256/{z}/{x}/{y}/2/1_1.png',
      );
    });

    test('returns null and degrades gracefully on HTTP error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final template =
          await RainRadarService.fetchLatestRadarUrlTemplate(client: mockClient);

      expect(template, isNull);
    });
  });
}
