import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/visuals/bank_button.dart';
import 'package:marge/ui/visuals/dice_3d.dart';
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

/// 3D dice: result decided before the animation; Roll/Bank, die taps and
/// the win readout stay locked until the dice settle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('winning roll: Bank enters only after the dice settle', (
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
    MatchNotifier.rngFactory = () => _Scripted([3, 3, 3]);
    addTearDown(() {
      MatchNotifier.rngFactory = Random.new;
      PlayerCoinLedger.bootstrap = null;
      SettingsNotifier.bootstrap = null;
      SavedGameStore.bootstrap = null;
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(matchProvider.notifier)
        .start(botCount: 1, playerName: 'You');

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('ROLL'), findsOneWidget);
    final rolling = container.read(matchProvider.notifier).roll();
    await tester.pump();
    await tester.pump(); // first frame with the thrown dice
    final view = container.read(matchProvider)!;
    // Engine result already known (three 4s, bankable) before any motion.
    expect(view.snapshot.turn!.dice.values, [4, 4, 4]);
    expect(view.snapshot.turn!.canBank, isTrue);
    expect(
      tester.widgetList<DiceCube>(find.byType(DiceCube)).map((c) => c.value),
      [4, 4, 4],
    );

    await tester.pump(const Duration(milliseconds: 500)); // mid-tumble
    expect(tester.state<DiceTrayState>(find.byType(DiceTray)).settling, isTrue);
    expect(find.byType(BankButton), findsNothing);
    expect(find.text('ROLL'), findsNothing);
    expect(find.textContaining('Trips on'), findsNothing); // readout waits

    await tester.pump(const Duration(milliseconds: 700)); // settled
    await tester.pump();
    expect(find.byType(BankButton), findsOneWidget);
    expect(find.textContaining('Trips on'), findsOneWidget);

    await rolling;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
