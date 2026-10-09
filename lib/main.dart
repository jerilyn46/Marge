import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ads/ad_ids.dart';
import 'ads/ads_service.dart';
import 'services/coin_ledger.dart';
import 'services/daily_gems_reminder.dart';
import 'services/friends_service.dart';
import 'services/gem_iap.dart';
import 'services/saved_games.dart';
import 'services/settings_service.dart';
import 'ui/match_provider.dart';
import 'startup_log.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/username_screen.dart';
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
  try {
    SettingsNotifier.bootstrap = await SettingsNotifier.load();
  } catch (e, st) {
    debugPrint('main: settings load failed (defaults): $e\n$st');
  }

  final container = ProviderContainer();

  // Always paint UI first. Ads/UMP must never block or abort cold start.
  // Native MobileAdsInitProvider is stripped; Dart bootstraps after first
  // frame only when ADMOB_ENABLED=true (fail closed otherwise).
  unawaited(StartupLog.mark('before-runApp'));
  runApp(
    UncontrolledProviderScope(container: container, child: const MargeApp()),
  );
  unawaited(StartupLog.mark('runApp-returned'));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(StartupLog.mark('first-frame'));
    // Attach the Play Billing purchase listener now (not on first Shop open)
    // so pending / unacknowledged gem purchases are credited and completed.
    // Post-frame only: nothing native before runApp. Failures are contained.
    _startGemIapSafely(container);
    if (!kAdmobEnabled) {
      debugPrint('main: ADMOB_ENABLED=false — skip ads bootstrap');
      return;
    }
    unawaited(_bootstrapAdsSafely(container));
  });
}

void _startGemIapSafely(ProviderContainer container) {
  try {
    container.read(gemIapProvider);
  } catch (e, st) {
    debugPrint('main: gem IAP start failed (Shop retries): $e\n$st');
  }
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
  final DailyGemsReminder _gemsReminder = DailyGemsReminder();
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
    if (state == AppLifecycleState.resumed) {
      // Refresh resume list after background / process pause.
      unawaited(ref.read(savedGamesProvider.notifier).reload());
      // Foreground: never let the gems reminder pop over a roll. Home shows
      // the in-app prompt instead.
      unawaited(_gemsReminder.cancel());
      return;
    }
    ref.read(matchProvider.notifier).persistUnfinished();
    if (state == AppLifecycleState.paused) {
      // Backgrounded with today's drip already claimed: one reminder for when
      // the existing daily-drip clock rolls over (only if already permitted).
      final next = ref.read(coinLedgerProvider).nextDailyDripUtc();
      if (next != null) unawaited(_gemsReminder.scheduleIfPermitted(next));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final Widget home;
    if (!settings.loaded) {
      home = const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    } else if (!settings.hasUsername) {
      home = const UsernameScreen();
    } else {
      home = const HomeScreen();
    }

    return MaterialApp(
      title: 'Marge Dice Game',
      debugShowCheckedModeBanner: false,
      theme: buildMargeTheme(),
      home: home,
    );
  }
}
