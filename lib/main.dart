import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ads/ad_ids.dart';
import 'ads/ads_service.dart';
import 'services/coin_ledger.dart';
import 'services/friends_service.dart';
import 'services/saved_games.dart';
import 'ui/match_provider.dart';
import 'startup_log.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/marge_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(StartupLog.mark('binding-ready'));

  // Never hit the network for fonts before (or instead of) the first frame.
  // Nunito is not bundled; runtime fetch can throw on some devices.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Coin banks must be on disk before the lobby paints, so a saved
  // balance is never shown as a fresh 100 gems.
  try {
    PlayerCoinLedger.bootstrap = await PlayerCoinLedger.load();
  } catch (e, st) {
    debugPrint('main: coin ledger load failed (using defaults): $e\n$st');
  }
  try {
    FriendsNotifier.bootstrap = await FriendsNotifier.load();
  } catch (e, st) {
    debugPrint('main: friends load failed (empty list): $e\n$st');
  }
  try {
    SavedGameStore.bootstrap = await SavedGameStore.load();
  } catch (e, st) {
    debugPrint('main: saved games load failed (none to resume): $e\n$st');
  }

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

class MargeApp extends ConsumerStatefulWidget {
  const MargeApp({super.key});

  @override
  ConsumerState<MargeApp> createState() => _MargeAppState();
}

class _MargeAppState extends ConsumerState<MargeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    ref.read(matchProvider.notifier).persistUnfinished();
  }

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
