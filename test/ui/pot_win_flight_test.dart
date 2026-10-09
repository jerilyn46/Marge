import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/visuals/pot_of_gems.dart';
import 'package:marge/ui/visuals/pot_win_flight.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visuals/visual_test_utils.dart';

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

class _Driven extends MatchNotifier {
  _Driven(this._seed);
  final MatchViewState _seed;
  @override
  MatchViewState? build() => _seed;
  void push(MatchViewState v) => state = v;
}

/// First-roll triple ones for the human at seat 0 (pot 20 → swept).
MatchSnapshot _potWin() {
  final c = MatchController(
    config: const MatchConfig(botCount: 1),
    rng: _Scripted([0, 0, 0]),
  );
  c.startMatch();
  c.roll();
  final snap = c.snapshot;
  expect(snap.lastPayout?.kind, ScoreKind.tripleOnesPotWin);
  return snap;
}

Future<_Driven> _pump(
  WidgetTester tester,
  MatchViewState view, {
  bool reduceMotion = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  late _Driven driven;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [matchProvider.overrideWith(() => driven = _Driven(view))],
      child: MaterialApp(
        theme: buildMargeTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 760),
            disableAnimations: reduceMotion,
          ),
          child: const MatchScreen(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return driven;
}

Offset _gemCenter(WidgetTester tester, int i) {
  final imgs = find.descendant(
    of: find.byType(PotWinFlight),
    matching: find.byType(Image),
  );
  return tester.getCenter(imgs.at(i));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pot win: gems leave the bowl, reach the seat, then the bank', (
    tester,
  ) async {
    final snap = _potWin();
    final won = snap.lastPayout!.amountCents;
    final driven = await _pump(
      tester,
      MatchViewState(snapshot: snap, revealingRoll: true, heldPotCents: won),
    );
    // During the reveal nothing flies.
    expect(find.byType(PotWinFlight), findsNothing);

    driven.push(MatchViewState(snapshot: snap));
    await tester.pump(); // listener → post-frame launch
    await tester.pump();
    expect(find.byType(PotWinFlight), findsOneWidget);

    final bowl = tester.getRect(find.byType(PotOfGems));
    final seat = tester.getCenter(find.byKey(const ValueKey('seat-chip-0')));
    final bank = tester.getCenter(find.byTooltip('Table gems'));

    // Lifting: first gem is still over the bowl.
    await tester.pump(const Duration(milliseconds: 60));
    expect(bowl.inflate(20).contains(_gemCenter(tester, 0)), isTrue);

    // Gathered on the winner's seat (lift + to-seat + half the hold).
    await tester.pump(
      const Duration(
        milliseconds: PotWinFlight.liftMs + PotWinFlight.toSeatMs + 60 - 60,
      ),
    );
    expect((_gemCenter(tester, 0) - seat).distance, lessThan(8));

    // Most of the way to the gem bank readout.
    await tester.pump(
      const Duration(
        milliseconds: PotWinFlight.holdMs + PotWinFlight.toBankMs - 80,
      ),
    );
    expect(
      (_gemCenter(tester, 0) - bank).distance,
      lessThan((seat - bank).distance * 0.25),
    );

    await tester.pump(
      PotWinFlight.durationFor(
        PotWinFlight.spritesFor(won, snap.config.anteCents),
        toBank: true,
      ),
    );
    await tester.pump();
    expect(find.byType(PotWinFlight), findsNothing);
  });

  testWidgets('Reduce Motion: a pot win flies nothing', (tester) async {
    final snap = _potWin();
    final driven = await _pump(
      tester,
      MatchViewState(snapshot: snap, revealingRoll: true, heldPotCents: 20),
      reduceMotion: true,
    );
    driven.push(MatchViewState(snapshot: snap));
    await tester.pump();
    await tester.pump();
    expect(find.byType(PotWinFlight), findsNothing);
  });

  test('sprites: one per ante unit, 4..12', () {
    expect(PotWinFlight.spritesFor(0, 10), 0);
    expect(PotWinFlight.spritesFor(20, 10), 4);
    expect(PotWinFlight.spritesFor(90, 10), 9);
    expect(PotWinFlight.spritesFor(900, 10), 12);
  });

  testWidgets('golden: pot win gems mid-flight to the seat', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await precacheAssets(tester, GemArt.potAssets);
    await tester.pumpWidget(
      feltHost(
        SizedBox(
          key: const ValueKey('flight'),
          width: 360,
          height: 280,
          child: PotWinFlight(
            from: const Offset(180, 80),
            seat: const Offset(70, 220),
            bank: const Offset(330, 20),
            gems: 8,
            onDone: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 380));
    await settleImages(tester);
    await expectLater(
      find.byKey(const ValueKey('flight')),
      matchesGoldenFile('visuals/goldens/pot_win_flight_to_seat.png'),
    );
    await tester.pump(const Duration(seconds: 2));
  });
}
