import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/visuals/pot_of_gems.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Scripted implements Random {
  _Scripted(this.seq);
  final List<int> seq;
  int i = 0;
  @override
  int nextInt(int max) => seq[i++ % seq.length] % max;
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
}

/// Tester (B): first-roll triple ones — dice first, then banner + pot change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pot display holds during the reveal, updates after', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    PlayerCoinLedger.bootstrap = PlayerCoinLedger(
      balances: {'human:You': 200},
      loaded: true,
      prefs: prefs,
    );
    SettingsNotifier.bootstrap = const GameSettings(
      playerName: 'You',
      hasUsername: true,
      loaded: true,
      // Platform haptics never answer under fake async; timing is the point.
      sfxEnabled: false,
      hapticsEnabled: false,
    );
    SavedGameStore.bootstrap = SavedGameStore(loaded: true, prefs: prefs);
    MatchNotifier.rngFactory = () => _Scripted([0, 0, 0]);
    addTearDown(() {
      MatchNotifier.rngFactory = Random.new;
      PlayerCoinLedger.bootstrap = null;
      SettingsNotifier.bootstrap = null;
      SavedGameStore.bootstrap = null;
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Carry 30 gems into the pot so the pot before the win (30 + 2 antes = 50)
    // differs from the pot after the sweep + re-ante (2 antes = 20). With
    // equal values this test could not tell a held display from a live one.
    container
        .read(matchProvider.notifier)
        .start(botCount: 1, playerName: 'You', carryPotGems: 30);
    final potBefore = container.read(matchProvider)!.snapshot.potCents;
    expect(potBefore, 50);

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
      ),
    );
    await tester.pump();

    int shownPot() => tester.widget<PotOfGems>(find.byType(PotOfGems)).potGems;
    String plate() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('pot-plate')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(shownPot(), potBefore);

    expect(find.text('ROLL'), findsOneWidget);
    // Same entry point the ROLL button uses.
    final rolling = container.read(matchProvider.notifier).roll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final mid = container.read(matchProvider)!;
    expect(mid.snapshot.lastPayout?.kind, ScoreKind.tripleOnesPotWin);
    expect(mid.revealingRoll, isTrue);
    // Engine already swept + re-anted (rule unchanged): live pot is 20...
    expect(mid.snapshot.potCents, 20);
    expect(mid.snapshot.potCents, isNot(potBefore));
    // ...but the table still shows the pre-sweep 50, and no banner yet.
    expect(shownPot(), potBefore);
    expect(plate(), 'Pot · $potBefore');
    expect(find.textContaining('sweeps the pot'), findsNothing);

    // Every 100 ms through the rest of the 1.2 s pause: still the old pot.
    // (The throw landed on the first pump above; 300 ms have passed.)
    for (var t = 400; t <= 1100; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(matchProvider)!.revealingRoll,
        isTrue,
        reason: '$t ms',
      );
      expect(shownPot(), potBefore, reason: '$t ms');
      expect(plate(), 'Pot · $potBefore', reason: '$t ms');
      expect(find.textContaining('sweeps the pot'), findsNothing);
    }

    // After the 1.2 s pause: banner and pot change land together.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    final after = container.read(matchProvider)!;
    expect(after.revealingRoll, isFalse);
    expect(shownPot(), 20);
    expect(shownPot(), after.snapshot.potCents);
    // The readout also waits for the 3D dice to settle. On a device they
    // start one 16 ms frame after the throw and settle at ~1.04 s, inside
    // the pause; this fake-time test only ticks them from the 300 ms pump,
    // so allow the remaining ~120 ms here.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('sweeps the pot'), findsOneWidget);
    // The plate drains from 50 to 20 after the pause, never before.
    await tester.pump(const Duration(milliseconds: 600));
    expect(plate(), 'Pot · 20');

    await tester.pump(const Duration(seconds: 3));
    await rolling;
    // Let the unlock toast / confetti timers finish.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
