import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ads/ads_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/marge_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();

  // Always paint UI first. Ads/UMP must never block or abort cold start
  // (v0.1.2-test crashed before lobby when bootstrap awaited UMP/GMA).
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MargeApp(),
    ),
  );

  // Defer ads init until after the first frame so a PlatformException /
  // native UMP failure cannot kill the isolate before runApp.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_bootstrapAdsSafely(container));
  });
}

Future<void> _bootstrapAdsSafely(ProviderContainer container) async {
  try {
    await container.read(adsServiceProvider).bootstrap();
  } catch (e, st) {
    debugPrint('main: ads bootstrap failed (app continues): $e\n$st');
  }
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
