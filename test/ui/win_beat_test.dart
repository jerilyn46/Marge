import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
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

class _Seeded extends MatchNotifier {
  _Seeded(this._seed);
  final MatchViewState _seed;
  @override
  MatchViewState? build() => _seed;
}

Future<void> _pump(WidgetTester tester, MatchViewState view) async {
  await tester.binding.setSurfaceSize(const Size(390, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [matchProvider.overrideWith(() => _Seeded(view))],
      child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('UAT #3: a bankable winning hand shows only BANK', (
    tester,
  ) async {
    // Three 4s on the first roll → three of a kind, still 2 rolls left.
    final c = MatchController(
      config: const MatchConfig(botCount: 1),
      rng: _Scripted([3, 3, 3]),
    );
    c.startMatch();
    c.roll();
    final snap = c.snapshot;
    expect(snap.turn!.canBank, isTrue);
    expect(snap.turn!.rollsLeft, 2);

    await _pump(tester, MatchViewState(snapshot: snap));
    expect(find.byKey(const ValueKey('bank-only')), findsOneWidget);
    expect(find.text('Bank'), findsOneWidget);
    // Amount under the label: two opponents? one bot here → 1 × trips pay.
    expect(find.text('+${bankPreviewGems(snap)} gems'), findsOneWidget);
    expect(bankPreviewGems(snap), snap.turn!.lastScore.perOpponentCents);
    expect(find.textContaining('ROLL AGAIN'), findsNothing);
    expect(find.text('ROLL'), findsNothing);
  });

  testWidgets('UAT #2: triple ones shows the dice before the pot banner', (
    tester,
  ) async {
    final c = MatchController(
      config: const MatchConfig(botCount: 1),
      rng: _Scripted([0, 0, 0]),
    );
    c.startMatch();
    c.roll();
    final snap = c.snapshot;
    expect(snap.lastPayout?.kind, ScoreKind.tripleOnesPotWin);
    // Rule unchanged: fresh 3 rolls for the same winner.
    expect(snap.turn!.hasRolled, isFalse);

    // Beat 1: dice on the table, banner held.
    await _pump(tester, MatchViewState(snapshot: snap, revealingRoll: true));
    final dice = tester.widgetList<DiceCube>(find.byType(DiceCube)).toList();
    expect(dice.map((d) => d.value).take(3), [1, 1, 1]);
    expect(find.textContaining('sweeps the pot'), findsNothing);

    // Beat 2: the notification follows; dice still visible.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, MatchViewState(snapshot: snap));
    expect(find.textContaining('sweeps the pot'), findsOneWidget);
    final dice2 =
        tester.widgetList<DiceCube>(find.byType(DiceCube)).toList();
    expect(dice2.map((d) => d.value).take(3), [1, 1, 1]);
  });
}
