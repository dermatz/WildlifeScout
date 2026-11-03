import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildlifescout/presentation/screens/field_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FieldMapScreen Bottom Control Deck Responsive & Overflow Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'wildlifescout_last_user_lat_v1': 51.1657,
        'wildlifescout_last_user_lon_v1': 10.4515,
        'wildlifescout_last_user_title_v1': 'Test Revier',
        'wildlifescout_auto_center_gps': false,
      });
    });

    testWidgets('renders bottom control deck without RenderFlex overflow across narrow widths and resizes',
        (tester) async {
      FlutterErrorDetails? caughtDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caughtDetails = details;
        originalOnError?.call(details);
      };
      addTearDown(() async {
        FlutterError.onError = originalOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpWidget(const SizedBox());
      });

      // 1. Initial 350px mobile width
      tester.view.physicalSize = const Size(350, 750);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FieldMapScreen(),
          ),
        ),
      );

      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('06:00').evaluate().isNotEmpty) break;
      }

      expect(caughtDetails, isNull, reason: 'Must not overflow at 350px width');
      expect(find.text('06:00'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);

      // Verify consolidated briefing card elements and expand/collapse interaction
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Kompass'), findsOneWidget);

      await tester.tap(find.text('Details'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Weniger'), findsOneWidget);
      expect(find.text('LUFTDRUCK'), findsOneWidget);

      await tester.tap(find.text('Weniger'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Details'), findsOneWidget);

      // 2. Dynamic resize to ultra-narrow 320px width (e.g. iPhone SE / small viewport)
      tester.view.physicalSize = const Size(320, 640);
      await tester.pump(const Duration(milliseconds: 100));

      expect(caughtDetails, isNull, reason: 'Must not overflow at 320px width');
      expect(find.text('06:00'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);

      // 3. Dynamic resize to compact 280px width (extreme constraint)
      tester.view.physicalSize = const Size(280, 560);
      await tester.pump(const Duration(milliseconds: 100));

      expect(caughtDetails, isNull, reason: 'Must not overflow at 280px width');
      expect(find.text('06:00'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);

      // 4. Return to desktop 800px width
      tester.view.physicalSize = const Size(800, 900);
      await tester.pump(const Duration(milliseconds: 100));

      expect(caughtDetails, isNull, reason: 'Must not overflow at 800px desktop width');
      expect(find.text('06:00'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
    });

    testWidgets('FieldSliderTrackShape spans full container width and provides prominent track height',
        (tester) async {
      const trackShape = FieldSliderTrackShape(
        nowFraction: 10.5,
        referenceDate: null,
      );

      final sliderTheme = SliderThemeData(
        trackHeight: 14.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20.0),
      );

      // Create a test render box of width 300 and height 48
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 48,
                child: Builder(
                  builder: (context) {
                    return SliderTheme(
                      data: sliderTheme.copyWith(trackShape: trackShape),
                      child: Slider(
                        value: 10,
                        min: 0,
                        max: 23,
                        divisions: 23,
                        onChanged: (_) {},
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      final renderBox = tester.renderObject<RenderBox>(sliderFinder);
      final preferredRect = trackShape.getPreferredRect(
        parentBox: renderBox,
        offset: Offset.zero,
        sliderTheme: sliderTheme,
      );

      // Verify that the track rectangle spans the full width of the parent (300px)
      // without subtracting the 40-48px overlay margin of default Flutter tracks
      expect(preferredRect.width, equals(300.0));
      expect(preferredRect.height, equals(14.0));
      expect(preferredRect.left, equals(0.0));
    });
  });
}
