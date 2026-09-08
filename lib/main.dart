import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ads/ad_ids.dart';
import 'ads/ads_service.dart';
import 'startup_log.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/marge_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(StartupLog.mark('binding-ready'));

  // Never hit the network for fonts before (or instead of) the first frame.
  // Nunito is not bundled; runtime fetch can throw on some devices.
  GoogleFonts.config.allowRuntimeFetching = false;

  final container = ProviderContainer();

  // Always paint UI first. Ads/UMP must never block or abort cold start.
  // v0.1.3 still crashed on Flip 7 because native MobileAdsInitProvider
  // runs before Dart; this build also disables AdMob entirely.
  unawaited(StartupLog.mark('before-runApp'));
  runApp(
    UncontrolledProviderScope(container: container, child: const MargeApp()),
  );
  unawaited(StartupLog.mark('runApp-returned'));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(StartupLog.mark('first-frame'));
    if (!kAdmobEnabled) {
      debugPrint('main: ADMOB_ENABLED=false — skip ads bootstrap');
      return;
    }
    unawaited(_bootstrapAdsSafely(container));
  });
}

Future<void> _bootstrapAdsSafely(ProviderContainer container) async {
  if (!kAdmobEnabled) return;
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
