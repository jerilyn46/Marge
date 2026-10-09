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
import 'package:marge/ui/widgets/pot_meter.dart';
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
    container.read(matchProvider.notifier).start(botCount: 1, playerName: 'You');
    final potBefore = container.read(matchProvider)!.snapshot.potCents;
    expect(potBefore, 20);

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
      ),
    );
    await tester.pump();

    int shownPot() => tester.widget<PotMeter>(find.byType(PotMeter)).potCents;
    expect(shownPot(), potBefore);

    expect(find.text('ROLL'), findsOneWidget);
    // Same entry point the ROLL button uses.
    final rolling = container.read(matchProvider.notifier).roll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final mid = container.read(matchProvider)!;
    expect(mid.snapshot.lastPayout?.kind, ScoreKind.tripleOnesPotWin);
    expect(mid.revealingRoll, isTrue);
    // Engine already swept + re-anted (rule unchanged)...
    expect(mid.snapshot.potCents, 20);
    // ...but the table still shows the pre-sweep pot, and no banner yet.
    expect(shownPot(), potBefore);
    expect(find.textContaining('sweeps the pot'), findsNothing);

    // Pause still running just before the end.
    await tester.pump(const Duration(milliseconds: 800));
    expect(container.read(matchProvider)!.revealingRoll, isTrue);
    expect(shownPot(), potBefore);

    // After the 1.2 s pause: banner and pot change land together.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    final after = container.read(matchProvider)!;
    expect(after.revealingRoll, isFalse);
    expect(shownPot(), after.snapshot.potCents);
    expect(find.textContaining('sweeps the pot'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await rolling;
    // Let the unlock toast / confetti timers finish.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
