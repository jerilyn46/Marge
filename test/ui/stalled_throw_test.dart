import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:flutter/scheduler.dart';
import 'package:marge/debug/settle_log.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/visuals/dice_3d.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Scripted implements Random {
  _Scripted(this.seq);
  List<int> seq;
  int i = 0;
  @override
  int nextInt(int max) => seq[i++ % seq.length] % max;
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
}

Finder _btn(String text) => find.ancestor(
  of: find.textContaining(text),
  matching: find.byWidgetPredicate(
    (w) => w is ElevatedButton || w is FilledButton,
  ),
);

bool _enabled(WidgetTester t, Finder f) {
  final w = t.widget(f);
  if (w is ElevatedButton) return w.onPressed != null;
  if (w is FilledButton) return w.onPressed != null;
  return false;
}

/// Device-like haptics: on, and the platform answers after a short delay.
int hapticDelayMs = 0;

Future<ProviderContainer> _boot(WidgetTester tester, List<int> seq) async {
  if (hapticDelayMs > 0) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          await Future<void>.delayed(Duration(milliseconds: hapticDelayMs));
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  PlayerCoinLedger.bootstrap = PlayerCoinLedger(
    balances: {'human:Jerilyn': 100},
    loaded: true,
    prefs: prefs,
  );
  SettingsNotifier.bootstrap = GameSettings(
    playerName: 'Jerilyn',
    hasUsername: true,
    loaded: true,
    sfxEnabled: false,
    hapticsEnabled: hapticDelayMs > 0,
  );
  SavedGameStore.bootstrap = SavedGameStore(loaded: true, prefs: prefs);
  final shared = _Scripted(seq); // one stream across rematches
  MatchNotifier.rngFactory = () => shared;
  addTearDown(() {
    MatchNotifier.rngFactory = Random.new;
    PlayerCoinLedger.bootstrap = null;
    SettingsNotifier.bootstrap = null;
    SavedGameStore.bootstrap = null;
  });
  final container = ProviderContainer();
  _last = container;
  addTearDown(container.dispose);
  container
      .read(matchProvider.notifier)
      .start(botCount: 1, playerName: 'Jerilyn');
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  final f = _btn(label);
  expect(f, findsOneWidget, reason: label);
  expect(_enabled(tester, f), isTrue, reason: '$label enabled');
  await tester.tap(f);
  await tester.pump();
  await _settle(tester);
}

String _dbg(ProviderContainer c) {
  final s = c.read(matchProvider)!.snapshot;
  return 'seat ${s.currentSeatIndex} phase ${s.phase} roll ${s.turn?.rollNumber} '
      'dice ${s.turn?.dice.values} last ${s.lastPayout?.kind}';
}

ProviderContainer? _last;

/// testWidgets that ends the match and drains timers (bot / banner / haptics).
void _tw(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    _last?.read(matchProvider.notifier).endMatch();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
  });
}

final _ticking = ValueNotifier<bool>(true);

/// Mount the real screen under a TickerMode we can flip.
Future<ProviderContainer> _mountT(WidgetTester tester, List<int> seq) async {
  final c = await _boot(tester, seq);
  await tester.pumpWidget(
    ValueListenableBuilder<bool>(
      valueListenable: _ticking,
      builder: (_, on, _) => TickerMode(
        enabled: on,
        child: UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildMargeTheme(),
            home: const MatchScreen(),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return c;
}

Future<void> _setView(WidgetTester t, Size px, double dpr) async {
  t.view.devicePixelRatio = dpr;
  t.view.physicalSize = px;
}

void _life(WidgetTester t, List<AppLifecycleState> s) {
  for (final x in s) {
    t.binding.handleAppLifecycleStateChanged(x);
  }
}

const _inner = Size(1080, 2520);
const _cover = Size(948, 1048);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    hapticDelayMs = 0;
    _ticking.value = true;
    // Watchdog off: these cases must unlock on their own.
    MatchScreen.settleWatchdog = const Duration(hours: 1);
  });
  tearDown(() {
    MatchScreen.settleWatchdog = const Duration(milliseconds: 2500);
    _ticking.value = true;
  });

  Future<ProviderContainer> start(WidgetTester tester) async {
    await _setView(tester, _inner, 2.625);
    addTearDown(tester.view.reset);
    return _mountT(tester, [2, 2, 0]);
  }

  Future<void> rollAndHold(WidgetTester tester) async {
    await tester.tap(_btn('ROLL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // mid-throw
  }

  Future<void> expectUnlocked(
    WidgetTester tester,
    ProviderContainer c,
    String why,
  ) async {
    await _settle(tester);
    expect(
      _enabled(tester, _btn('KEEP ROLLING')),
      isTrue,
      reason: '$why: ${_dbg(c)}',
    );
  }

  final resizes = <String, List<(Size, double)>>{
    'inner -> cover': [(_cover, 2.625)],
    'inner -> cover -> inner': [(_cover, 2.625), (_inner, 2.625)],
    'cover display size 2.25': [(_cover, 2.25)],
  };
  for (final e in resizes.entries) {
    _tw('resize mid-throw: ${e.key}', (tester) async {
      final c = await start(tester);
      await rollAndHold(tester);
      for (final (px, dpr) in e.value) {
        await _setView(tester, px, dpr);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
      await expectUnlocked(tester, c, 'resize ${e.key}');
    });
  }

  const lifes = {
    'paused': [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ],
    'inactive': [AppLifecycleState.inactive],
    'hidden': [AppLifecycleState.inactive, AppLifecycleState.hidden],
  };
  for (final e in lifes.entries) {
    _tw('lifecycle mid-throw: ${e.key} then resumed', (tester) async {
      final c = await start(tester);
      await rollAndHold(tester);
      _life(tester, e.value);
      await tester.pump(const Duration(seconds: 3));
      _life(tester, [
        if (e.key == 'paused') AppLifecycleState.hidden,
        if (e.key != 'inactive') AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await expectUnlocked(tester, c, 'lifecycle ${e.key}');
    });
  }

  _tw('TickerMode off mid-throw, then on', (tester) async {
    final c = await start(tester);
    await rollAndHold(tester);
    _ticking.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    _ticking.value = true;
    await tester.pump();
    await expectUnlocked(tester, c, 'TickerMode');
  });

  _tw('fold to cover with TickerMode off mid-throw (config change)', (
    tester,
  ) async {
    final c = await start(tester);
    await rollAndHold(tester);
    _ticking.value = false;
    _life(tester, [AppLifecycleState.inactive]);
    await _setView(tester, _cover, 2.625);
    await tester.pump(const Duration(seconds: 1));
    _life(tester, [AppLifecycleState.resumed]);
    _ticking.value = true;
    await tester.pump();
    await expectUnlocked(tester, c, 'fold');
  });

  _tw('triple-1s hold: TickerMode off during the hold, then on', (
    tester,
  ) async {
    await _setView(tester, _inner, 2.625);
    addTearDown(tester.view.reset);
    final c = await _mountT(tester, [0, 0, 0, 3, 5, 5]);
    await tester.tap(_btn('ROLL')); // 1,1,1 first roll: pot sweep + hold
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    _ticking.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    _ticking.value = true;
    await tester.pump();
    await _settle(tester);
    await _tap(tester, 'Continue playing'); // match over: next game
    await _tap(tester, 'ROLL'); // 4,6,6
    expect(
      _enabled(tester, _btn('KEEP ROLLING')),
      isTrue,
      reason: 'after hold: ${_dbg(c)}',
    );
  });

  _tw('triple-1s hold: app paused during the hold, then resumed', (
    tester,
  ) async {
    await _setView(tester, _inner, 2.625);
    addTearDown(tester.view.reset);
    final c = await _mountT(tester, [0, 0, 0, 3, 5, 5]);
    await tester.tap(_btn('ROLL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    _life(tester, lifes['paused']!);
    await tester.pump(const Duration(seconds: 3));
    _life(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await _settle(tester);
    await _tap(tester, 'Continue playing'); // match over: next game
    await _tap(tester, 'ROLL');
    expect(
      _enabled(tester, _btn('KEEP ROLLING')),
      isTrue,
      reason: 'after hold: ${_dbg(c)}',
    );
  });

  _tw('breadcrumbs: lock set, throw, report, release for one roll', (
    tester,
  ) async {
    SettleLog.clear();
    final c = await start(tester);
    await rollAndHold(tester);
    await expectUnlocked(tester, c, 'roll');
    final ev = SettleLog.entries.map((e) => e.event).toList();
    final serial = c.read(matchProvider)!.rollSerial;
    final mine = SettleLog.entries.where((e) => e.serial == serial).toList();
    expect(
      mine.map((e) => e.event),
      containsAllInOrder([
        'lock-set',
        'throw-start',
        'tray-report',
        'lock-released',
      ]),
      reason: '$ev',
    );
  });

  _tw('breadcrumbs: watchdog-fired is logged', (tester) async {
    SettleLog.clear();
    MatchScreen.settleWatchdog = const Duration(milliseconds: 2500);
    timeDilation = 1000;
    addTearDown(() => timeDilation = 1);
    final c = await start(tester);
    await rollAndHold(tester);
    await _settle(tester);
    timeDilation = 1;
    final ev = SettleLog.entries.map((e) => e.event).toList();
    expect(ev, contains('watchdog-fired'));
    // Dice are snapped to rest before input unlocks.
    expect(ev, contains('throw-snapped'));
    expect(
      tester.state<DiceTrayState>(find.byType(DiceTray)).settling,
      isFalse,
    );
    expect(c, isNotNull);
  });
}
