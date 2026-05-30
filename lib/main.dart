import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'src/ui/game_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const TileWizApp());
}

class TileWizApp extends StatelessWidget {
  const TileWizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const GameScreen(),
      title: 'TileWiz',
      theme: ThemeData(useMaterial3: true),
    );
  }
}
