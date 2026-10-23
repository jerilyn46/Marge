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
  _rng = shared;
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

Future<void> _holdTap(WidgetTester t, int i) async {
  await t.tap(find.byKey(ValueKey('die-$i')));
  await t.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Bug report Oct 23: 1-5-1 on roll 3 with the 1s held (dice 0 and 2,
  // not adjacent) showed "Bust -2 gems". Drive it through real taps.
  for (final holdAfter in [1, 2]) {
    _tw('1-5-1, 1s held at 0 and 2 from roll $holdAfter: missed triple ones', (
      t,
    ) async {
      // roll 1: 1,5,1 (or 3,5,1 then 1,5,1); then only the middle die moves.
      final seq = holdAfter == 1
          ? [0, 4, 0, 3, 4, 2, 2, 0]
          : [2, 4, 0, 0, 3, 0, 4, 2, 2, 0];
      final c = await _boot(t, seq);
      await _settle(t);
      await _tap(t, 'ROLL');
      if (holdAfter == 1) {
        await _holdTap(t, 0);
        await _holdTap(t, 2);
      }
      final pot = c.read(matchProvider)!.snapshot.potCents;
      final bank = c.read(matchProvider)!.snapshot.players[0].bankCents;
      await _tap(t, 'KEEP ROLLING');
      if (holdAfter == 2) {
        expect(c.read(matchProvider)!.snapshot.turn!.dice.values[0], 1);
        await _holdTap(t, 0);
        await _holdTap(t, 2);
      }
      expect(c.read(matchProvider)!.snapshot.turn!.dice.keptFlags, [
        true,
        false,
        true,
      ]);
      await _tap(t, 'KEEP ROLLING');
      final s = c.read(matchProvider)!.snapshot;
      expect(s.handoff!.diceValues, [1, 5, 1]);
      expect(s.handoff!.outcomeText, 'Missed triple ones');
      expect(s.players[0].bankCents, bank - 10);
      expect(s.potCents, pot + 10);
      await _settle(t);
      expect(find.text('Missed triple ones'), findsOneWidget);
      expect(find.text('-10 gems'), findsOneWidget);
      expect(find.text('Bust'), findsNothing);
    });
  }

  _tw('1-5-1 with only one 1 held: normal bust (definition)', (t) async {
    final c = await _boot(t, [0, 4, 0, 3, 2, 4, 0, 2, 2, 0]);
    await _settle(t);
    await _tap(t, 'ROLL'); // 1,5,1
    await _holdTap(t, 0);
    await _tap(t, 'KEEP ROLLING'); // 1,4,3
    await _tap(t, 'KEEP ROLLING'); // 1,5,1
    final s = c.read(matchProvider)!.snapshot;
    expect(s.handoff!.diceValues, [1, 5, 1]);
    expect(s.handoff!.outcomeText, 'Bust');
    expect(s.handoff!.bankDeltaCents, -2);
  });

  for (final delay in [0, 40]) {
    _tw('full flow vs bot Spike (haptics ${delay}ms): after the bot turn, '
        'held 1s at 0 and 2 then 1-5-1 is a missed triple ones', (t) async {
      hapticDelayMs = delay;
      addTearDown(() => hapticDelayMs = 0);
      // Jerilyn busts: 2,3,5 / 2,3,5 / 2,3,5 (no holds).
      final c = await _boot(t, [1, 2, 4]);
      await _settle(t);
      await _tap(t, 'ROLL');
      await _tap(t, 'KEEP ROLLING');
      await _tap(t, 'KEEP ROLLING');
      expect(c.read(matchProvider)!.snapshot.awaitingHandoff, isTrue);
      // Spike: whatever the bot does, play it out.
      _script([1, 3, 5, 2, 4]);
      await _tap(t, 'Continue');
      for (var i = 0; i < 80; i++) {
        final s = c.read(matchProvider)!.snapshot;
        if (s.currentPlayer.profile.isHuman &&
            s.phase.name == 'playing' &&
            !(c.read(matchProvider)!.busyBot)) {
          break;
        }
        if (s.awaitingHandoff && find.text('Continue').evaluate().isNotEmpty) {
          await t.tap(_btn('Continue'));
        }
        await t.pump(const Duration(milliseconds: 250));
      }
      await _settle(t);
      final s0 = c.read(matchProvider)!.snapshot;
      expect(s0.currentPlayer.profile.isHuman, isTrue);
      _script([0, 4, 0, 3, 4]);
      await _tap(t, 'ROLL'); // 1,5,1
      await _holdTap(t, 0);
      await _holdTap(t, 2);
      expect(c.read(matchProvider)!.snapshot.turn!.dice.keptFlags, [
        true,
        false,
        true,
      ]);
      final pot = c.read(matchProvider)!.snapshot.potCents;
      await _tap(t, 'KEEP ROLLING'); // 1,4,1
      expect(c.read(matchProvider)!.snapshot.turn!.dice.keptFlags, [
        true,
        false,
        true,
      ]);
      await _tap(t, 'KEEP ROLLING'); // 1,5,1
      final s = c.read(matchProvider)!.snapshot;
      expect(s.handoff!.diceValues, [1, 5, 1]);
      expect(s.handoff!.outcomeText, 'Missed triple ones');
      expect(s.handoff!.bankDeltaCents, -10);
      expect(s.potCents, pot + 10);
    });
  }

  _tw('tap on a held 1 while the throw sound/haptic is in flight '
      'cannot drop the hold', (t) async {
    hapticDelayMs = 60;
    addTearDown(() => hapticDelayMs = 0);
    final c = await _boot(t, [0, 4, 0, 3, 4, 0, 2, 2]);
    await _settle(t);
    await _tap(t, 'ROLL'); // 1,5,1
    await _holdTap(t, 0);
    await _holdTap(t, 2);
    await _tap(t, 'KEEP ROLLING'); // 1,4,1
    final n = c.read(matchProvider.notifier);
    n.roll(); // roll 3 starts; haptic still pending
    n.toggleKeep(2); // stray tap mid-throw
    n.roll(); // second Roll tap
    await t.pump(const Duration(milliseconds: 100));
    await _settle(t);
    final s = c.read(matchProvider)!.snapshot;
    expect(s.handoff!.diceValues, [1, 5, 1]);
    expect(s.handoff!.outcomeText, 'Missed triple ones');
    expect(s.handoff!.bankDeltaCents, -10);
  });
}

ProviderContainer? _last;
_Scripted? _rng;

void _script(List<int> seq) {
  _rng!
    ..seq = seq
    ..i = 0;
}

void _tw(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    _last?.read(matchProvider.notifier).endMatch();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
  });
}
