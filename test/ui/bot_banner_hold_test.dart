import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
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

Future<ProviderContainer> _boot(
  WidgetTester tester,
  List<int> seq, {
  int others = 0,
  int bots = 1,
}) async {
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
      .start(botCount: bots, otherHumanCount: others, playerName: 'Jerilyn');
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

/// Human busts (3 misses), hands off; the bot then rolls [botSeq].
/// Returns how long the bot's payout banner (containing [text]) was on screen.
Future<int> _bannerMs(WidgetTester t, List<int> botSeq, String text) async {
  final c = await _boot(t, const [2, 2, 0]);
  await _settle(t);
  await _tap(t, 'ROLL');
  await _tap(t, 'KEEP ROLLING');
  await _tap(t, 'KEEP ROLLING');
  final rng = MatchNotifier.rngFactory() as _Scripted;
  rng.seq = botSeq;
  rng.i = 0;
  c.read(matchProvider.notifier).confirmHandoff();
  var shown = 0;
  var gone = false;
  for (var k = 0; k < 400 && !gone; k++) {
    await t.pump(const Duration(milliseconds: 50));
    final on = find.textContaining(text).evaluate().isNotEmpty;
    if (on) {
      shown += 50;
    } else if (shown > 0) {
      gone = true;
    }
  }
  debugPrint('$text: visible $shown ms');
  expect(shown, greaterThan(0), reason: 'banner never shown');
  return shown;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _tw('bot straight banner stays >= 1.5 s', (t) async {
    // Bot: 1,2,3 on roll 1, banks; then misses.
    final ms = await _bannerMs(t, [0, 1, 2, 2, 2, 0], 'nails a straight');
    expect(ms, greaterThanOrEqualTo(1500));
  });

  _tw('bot trips banner stays >= 1.5 s', (t) async {
    // Bot: 5,5,5 on roll 1 (first-roll trips), banks; then misses.
    final ms = await _bannerMs(t, [4, 4, 4, 2, 2, 0], 'three 5s');
    expect(ms, greaterThanOrEqualTo(1500));
  });

  _tw('bot roll-2 triple 1s banner stays >= 1.5 s', (t) async {
    // Bot: 1,1,3 (keeps the 1s), then 1 -> 1,1,1 on roll 2; then misses.
    final ms = await _bannerMs(t, [0, 0, 2, 0, 2, 2, 0], 'triple ones');
    expect(ms, greaterThanOrEqualTo(1500));
  });
}

ProviderContainer? _last;

void _tw(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    _last?.read(matchProvider.notifier).endMatch();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
  });
}
