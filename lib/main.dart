import 'package:flutter/material.dart';

import 'src/ui/game_screen.dart';

void main() {
  runApp(const TileWizApp());
}

class TileWizApp extends StatelessWidget {
  const TileWizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const GameScreen();
  }
}
