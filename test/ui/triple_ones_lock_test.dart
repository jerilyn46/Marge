import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/visuals/bank_button.dart';
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
  MatchNotifier.rngFactory = () => _Scripted(seq);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('haptics off', () => _suite(0));
  group('device haptics (40 ms)', () => _suite(40));
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

void _suite(int haptic) {
  setUp(() => hapticDelayMs = haptic);

  // Miss = 3,3,1 (indices 2,2,0); trips = 1,1,1 (0,0,0); then 4,6,6 (3,5,5).
  const miss = [2, 2, 0];
  const ones = [0, 0, 0];
  const after = [3, 5, 5];
  for (final onRoll in [1, 2, 3]) {
    _tw('triple 1s on roll $onRoll vs bot: next human roll unlocks', (
      tester,
    ) async {
      final seq = [
        for (var i = 1; i < onRoll; i++) ...miss,
        ...ones,
        ...after,
        ...after,
      ];
      final c = await _boot(tester, seq);
      await _settle(tester);
      for (var i = 1; i < onRoll; i++) {
        await _tap(tester, i == 1 ? 'ROLL' : 'KEEP ROLLING');
      }
      await _tap(tester, onRoll == 1 ? 'ROLL' : 'KEEP ROLLING');
      final s = c.read(matchProvider)!.snapshot;
      debugPrint('after ones: ${_dbg(c)}');
      if (s.turn!.hasRolled && s.turn!.canBank) {
        final bank = find.byKey(const ValueKey('bank-only'));
        expect(bank, findsOneWidget, reason: 'Bank shown');
        expect((tester.widget(bank) as dynamic).enabled, isTrue);
        await tester.tap(bank);
        await tester.pump();
        await _settle(tester);
      }
      await _settle(tester);
      debugPrint('fresh: ${_dbg(c)}');
      expect(
        c.read(matchProvider)!.snapshot.currentPlayer.profile.isHuman,
        isTrue,
      );
      await _tap(tester, 'ROLL');
      debugPrint('next: ${_dbg(c)}');
      expect(
        _enabled(tester, _btn('KEEP ROLLING')),
        isTrue,
        reason: 'Keep Rolling after ${_dbg(c)}',
      );
    });
  }

  for (final quick in [false, true]) {
    _tw('keep two 1s, third 1 on roll 2 then Bank (quick=$quick)', (
      tester,
    ) async {
      final c = await _boot(tester, [0, 0, 2, 0, 3, 5, 5, 3, 5, 5]);
      await _settle(tester);
      await _tap(tester, 'ROLL'); // 1,1,3
      debugPrint('r1: ${_dbg(c)}');
      c.read(matchProvider.notifier).toggleKeep(0);
      c.read(matchProvider.notifier).toggleKeep(1);
      await tester.pump();
      await _tap(tester, 'ROLL'); // third die -> 1
      debugPrint('r2: ${_dbg(c)}');
      final bank = find.byKey(const ValueKey('bank-only'));
      expect(bank, findsOneWidget);
      debugPrint('bank enabled ${(tester.widget(bank) as dynamic).enabled}');
      await tester.tap(bank);
      await tester.pump(Duration(milliseconds: quick ? 50 : 3000));
      final r = _btn('ROLL');
      for (
        var k = 0;
        k < 60 && (r.evaluate().length != 1 || !_enabled(tester, r));
        k++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      debugPrint('fresh: ${_dbg(c)}');
      await _tap(tester, 'ROLL');
      debugPrint(
        'next: ${_dbg(c)} kept ${c.read(matchProvider)!.snapshot.turn!.dice.dice.map((d) => d.kept).toList()}',
      );
      expect(
        _enabled(tester, _btn('KEEP ROLLING')),
        isTrue,
        reason: 'Keep Rolling after ${_dbg(c)}',
      );
    });
  }

  // Jerilyn's 12:39 table (98 vs 78, pot 24): triple 1s on roll 3, bank,
  // then play on (busts, handoffs, bot turns). Her table must never lock.
  _tw('triple 1s on roll 3, bank, then play on: never locked', (tester) async {
    final c = await _boot(tester, [
      2,
      2,
      0,
      2,
      2,
      0,
      0,
      0,
      0,
      3,
      5,
      5,
      2,
      2,
      0,
    ]);
    await _settle(tester);
    final n = c.read(matchProvider.notifier);
    var humanRolls = 0;
    for (var step = 0; step < 60 && humanRolls < 12; step++) {
      final s = c.read(matchProvider)!.snapshot;
      if (s.phase == MatchPhase.awaitingHandoff) {
        n.confirmHandoff();
        await _settle(tester);
        continue;
      }
      if (s.phase != MatchPhase.playing) break;
      if (s.currentPlayer.profile.isBot) {
        await _settle(tester);
        continue;
      }
      final t = s.turn!;
      if (t.hasRolled && t.canBank) {
        final bank = find.byKey(const ValueKey('bank-only'));
        final any = _btn('BANK');
        if (bank.evaluate().isNotEmpty) {
          expect(
            (tester.widget(bank) as dynamic).enabled,
            isTrue,
            reason: 'Bank locked: ${_dbg(c)}',
          );
          await tester.tap(bank);
        } else {
          expect(
            _enabled(tester, any),
            isTrue,
            reason: 'BANK locked: ${_dbg(c)}',
          );
          await tester.tap(any);
        }
        await tester.pump();
        await _settle(tester);
        continue;
      }
      final label = t.hasRolled && t.mustKeepRolling ? 'KEEP ROLLING' : 'ROLL';
      final b = _btn(label);
      if (b.evaluate().length != 1) {
        final bust = _btn('BUST');
        expect(bust, findsOneWidget, reason: 'no action: ${_dbg(c)}');
        await tester.tap(bust);
        await tester.pump();
        await _settle(tester);
        continue;
      }
      expect(_enabled(tester, b), isTrue, reason: '$label locked: ${_dbg(c)}');
      await tester.tap(b);
      humanRolls++;
      await tester.pump();
      await _settle(tester);
      debugPrint(
        'h$humanRolls: ${_dbg(c)} pot ${c.read(matchProvider)!.snapshot.potCents}',
      );
    }
    expect(humanRolls, greaterThanOrEqualTo(6));
  });

  // Real-device pacing: 16 ms frames, act the moment a control enables.
  for (final seed in [1, 2, 3]) {
    _tw('fast taps after triple 1s (seed $seed): never locked', (tester) async {
      final r = Random(seed);
      final seq = [
        for (var i = 0; i < 400; i++)
          if (i % 23 == 5) ...[0, 0, 0] else r.nextInt(6),
      ];
      final c = await _boot(tester, seq);
      final n = c.read(matchProvider.notifier);
      var idle = 0;
      var actions = 0;
      for (var f = 0; f < 6000 && actions < 80; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        final s = c.read(matchProvider)!.snapshot;
        if (s.phase == MatchPhase.matchEnd ||
            s.phase == MatchPhase.awaitingShortfall) {
          break;
        }
        if (s.phase == MatchPhase.awaitingHandoff) {
          if (++idle > 20) {
            n.confirmHandoff();
            idle = 0;
          }
          continue;
        }
        if (s.currentPlayer.profile.isBot) {
          idle = 0;
          continue;
        }
        Finder? hit;
        for (final f2 in [
          find.byKey(const ValueKey('bank-only')),
          _btn('KEEP ROLLING'),
          _btn('ROLL'),
          _btn('BANK'),
          _btn('BUST'),
        ]) {
          if (f2.evaluate().length == 1) {
            final w = tester.widget(f2.first);
            final on = w is BankButton ? w.enabled : _enabled(tester, f2);
            if (on) {
              hit = f2;
              break;
            }
          }
        }
        if (hit == null) {
          idle++;
          expect(
            idle,
            lessThan(250), // 4 s with nothing enabled = locked
            reason:
                'locked: ${_dbg(c)} view '
                'busy=${c.read(matchProvider)!.busyBot} '
                'reveal=${c.read(matchProvider)!.revealingRoll} '
                'serial=${c.read(matchProvider)!.rollSerial}',
          );
          continue;
        }
        idle = 0;
        if (r.nextInt(3) == 0) {
          // a few frames of human hesitation
          await tester.pump(Duration(milliseconds: 16 * r.nextInt(30)));
        }
        if (r.nextInt(2) == 0) {
          // Hold/unhold dice the way she would between rolls.
          n.toggleKeep(r.nextInt(3));
          await tester.pump(const Duration(milliseconds: 16));
        }
        if (hit.evaluate().length != 1) continue;
        await tester.tap(hit, warnIfMissed: false);
        actions++;
      }
      await tester.pump(const Duration(seconds: 6));
      debugPrint('seed $seed actions $actions ${_dbg(c)}');
    });
  }

  for (final mode in ['pause', 'inactive', 'hidden']) {
    _tw('triple 1s roll 3, bank, roll; app $mode mid-throw', (tester) async {
      final c = await _boot(tester, [2, 2, 0, 2, 2, 0, 0, 0, 0, 3, 5, 5]);
      await _settle(tester);
      await _tap(tester, 'ROLL');
      await _tap(tester, 'KEEP ROLLING');
      await _tap(tester, 'KEEP ROLLING'); // 1,1,1 on roll 3
      final bank = find.byKey(const ValueKey('bank-only'));
      await tester.tap(bank);
      await tester.pump();
      await _settle(tester);
      await tester.tap(_btn('ROLL')); // 4,6,6
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final b = tester.binding;
      if (mode == 'pause') {
        b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else if (mode == 'inactive') {
        b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      } else {
        b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      }
      await tester.pump(const Duration(seconds: 2));
      if (mode == 'pause') {
        b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      }
      if (mode != 'inactive') {
        b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      }
      b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(
        _enabled(tester, _btn('KEEP ROLLING')),
        isTrue,
        reason: 'after $mode: ${_dbg(c)}',
      );
    });
  }

  // Exactly Jerilyn's 12:39 table: she busts, Spike busts (pot 24), then
  // she hits 1,1,1 on roll 3 (98 vs 78), banks, rolls 4,6,6.
  _tw('Jerilyn 12:39: bust, bot bust, 1-1-1 on roll 3, bank, 4-6-6', (
    tester,
  ) async {
    final rng = _Scripted([2, 2, 0]);
    void dice(List<int> v) {
      rng.seq = v;
      rng.i = 0;
    }

    final c = await _boot(tester, const [2, 2, 0]);
    MatchNotifier.rngFactory = () => rng;
    c.read(matchProvider.notifier).start(botCount: 1, playerName: 'Jerilyn');
    await tester.pump();
    final n = c.read(matchProvider.notifier);
    await _settle(tester);
    await _tap(tester, 'ROLL');
    await _tap(tester, 'KEEP ROLLING');
    await _tap(tester, 'KEEP ROLLING');
    debugPrint('j bust: ${_dbg(c)}');
    dice([2, 2, 0, 5, 5, 5, 5, 5, 5]);
    n.confirmHandoff();
    for (var k = 0; k < 15; k++) {
      await _settle(tester);
      final s = c.read(matchProvider)!.snapshot;
      if (s.phase == MatchPhase.awaitingHandoff) {
        debugPrint('bot done: ${_dbg(c)} pot ${s.potCents}');
        dice([2, 2, 0]);
        n.confirmHandoff();
        await _settle(tester);
        break;
      }
    }
    debugPrint('j turn: ${_dbg(c)}');
    await _tap(tester, 'ROLL');
    await _tap(tester, 'KEEP ROLLING');
    dice([0, 0, 0]);
    await _tap(tester, 'KEEP ROLLING');
    final s = c.read(matchProvider)!.snapshot;
    debugPrint(
      'ones: ${_dbg(c)} pot ${s.potCents} '
      '${s.players.map((p) => p.bankCents).toList()}',
    );
    await tester.tap(find.byKey(const ValueKey('bank-only')));
    await tester.pump();
    await _settle(tester);
    final s2 = c.read(matchProvider)!.snapshot;
    debugPrint(
      'banked: ${_dbg(c)} pot ${s2.potCents} '
      '${s2.players.map((p) => p.bankCents).toList()}',
    );
    dice([3, 5, 5]);
    await _tap(tester, 'ROLL');
    debugPrint('next: ${_dbg(c)}');
    expect(
      _enabled(tester, _btn('KEEP ROLLING')),
      isTrue,
      reason: 'locked: ${_dbg(c)}',
    );
  });

  // Safety net: if the tray never reports (here its ticker is stalled), the
  // screen releases the lock once no throw can still be in flight.
  _tw('stalled tray ticker: Keep Rolling still unlocks (watchdog)', (
    tester,
  ) async {
    final c = await _boot(tester, [2, 2, 0]);
    await _settle(tester);
    // A throw that never finishes on time (stalled ticker / lost frames).
    timeDilation = 1000;
    addTearDown(() => timeDilation = 1);
    await tester.pump();
    await tester.tap(_btn('ROLL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_enabled(tester, _btn('KEEP ROLLING')), isFalse); // mid-throw
    await _settle(tester);
    expect(
      _enabled(tester, _btn('KEEP ROLLING')),
      isTrue,
      reason: 'locked: ${_dbg(c)}',
    );
    timeDilation = 1;
  });
}
