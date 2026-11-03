import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/wildlifescout_theme.dart';
import 'domain/services/disturbance_matrix_service.dart';
import 'presentation/screens/field_map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Asynchrones Vorladen der wissenschaftlichen Störungsmatrix aus YAML
  DisturbanceMatrixService.initialize();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: WildlifeScoutTheme.bgObsidian,
    ),
  );
  runApp(const WildlifeScoutApp());
}

class WildlifeScoutApp extends StatelessWidget {
  const WildlifeScoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WildlifeScout – Feld- & Ansitz-Planer',
      debugShowCheckedModeBanner: false,
      theme: WildlifeScoutTheme.buildDarkTheme(),
      home: const FieldMapScreen(),
    );
  }
}
