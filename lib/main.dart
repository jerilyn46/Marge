import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/screens/home_screen.dart';
import 'ui/theme/marge_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MargeApp()));
}

class MargeApp extends StatelessWidget {
  const MargeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marge Dice Game',
      debugShowCheckedModeBanner: false,
      theme: buildMargeTheme(),
      home: const HomeScreen(),
    );
  }
}
