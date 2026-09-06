import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ads/ads_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/marge_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  // UMP + MobileAds before runApp / first ad request (no-op off mobile).
  await container.read(adsServiceProvider).bootstrap();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MargeApp(),
    ),
  );
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
