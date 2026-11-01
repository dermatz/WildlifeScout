import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/wildscout_theme.dart';
import 'presentation/screens/tactical_map_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: WildScoutTheme.bgObsidian,
    ),
  );
  runApp(const WildlifeScoutApp());
}

class WildlifeScoutApp extends StatelessWidget {
  const WildlifeScoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WildlifeScout – Wildlife Tactical Planner',
      debugShowCheckedModeBanner: false,
      theme: WildScoutTheme.buildDarkTheme(),
      home: const TacticalMapScreen(),
    );
  }
}
