import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_checkpoint.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dice: nextInt(6) + 1. [next] swaps the stream mid-test.
class _Dice implements Random {
  _Dice(this.seq);
  List<int> seq;
  int i = 0;
  void next(List<int> s) {
    seq = s;
    i = 0;
  }

  @override
  int nextInt(int max) => seq[i++ % seq.length] % max;
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
}

class _Live extends MatchNotifier {
  _Live(this._first);
  final MatchViewState _first;
  @override
  MatchViewState? build() => _first;
}

const straight = [0, 1, 2]; // 1,2,3
const miss = [2, 2, 0]; // 3,3,1
const ones = [0, 0, 0];

/// Jerilyn's 9:32 report: straight banked (keeps the seat, fresh set),
/// one miss, then 1-1-1 on the second roll of the new set.
MatchController _herTurn({List<int> finalRoll = ones}) {
  final d = _Dice(straight);
  final c = MatchController(
    config: const MatchConfig(botCount: 1, localPlayerName: 'Jerilyn'),
    rng: d,
  )..startMatch();
  c.roll();
  expect(c.snapshot.turn!.lastScore.kind, ScoreKind.straight);
  c.bank();
  expect(c.snapshot.lastPayout!.message, contains('straight'));
  d.next(miss);
  c.roll();
  d.next(finalRoll);
  c.roll();
  return c;
}

const fours = [3, 3, 3]; // 4,4,4
const sixFiveTwo = [5, 4, 1]; // 6,5,2

MatchController _game(_Dice d) => MatchController(
  config: const MatchConfig(botCount: 1, localPlayerName: 'Jerilyn'),
  rng: d,
)..startMatch();

/// Save, edit the JSON, load into a fresh controller.
MatchController _reload(
  MatchController c,
  void Function(Map<String, Object?> j) edit,
) {
  final j = Map<String, Object?>.from(c.capture().toJson());
  edit(j);
  final r = MatchController(config: c.config, rng: _Dice(miss))
    ..restore(MatchCheckpoint.fromJson(j)!);
  return r;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('banner lifetime', () {
    test('win shows on its roll; the next roll clears it (3s then 6-5-2)', () {
      final d = _Dice(miss);
      final c = _game(d);
      c.roll(); // 3,3,1
      d.next(fours);
      c.roll(); // 4,4,4 on roll 2 — later trips pay face
      c.bank();
      expect(
        c.snapshot.lastPayout!.message,
        'Jerilyn hits three 4s! Collects 4 gems (4 gems each).',
      );
      d.next(sixFiveTwo);
      c.roll();
      expect(c.snapshot.turn!.lastScore.kind, ScoreKind.none);
      expect(c.snapshot.lastPayout, isNull);
      c.roll();
      expect(c.snapshot.turn!.rollNumber, 2);
      expect(c.snapshot.lastPayout, isNull, reason: 'roll 2/3, no score');
    });

    test('win, then turn change clears it (even a celebratory banner)', () {
      final d = _Dice(miss);
      final c = _game(d);
      c.roll();
      c.roll();
      c.roll(); // bust -> handoff
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      final r = _reload(c, (j) {
        j['lastPayout'] = {
          'message':
              'Jerilyn rolls triple ones! Collects 10 gems '
              '(10 gems each).',
          'kind': ScoreKind.tripleOnesPay.name,
          'amountCents': 10,
          'celebratory': true,
        };
      });
      expect(r.snapshot.lastPayout?.celebratory, isTrue);
      r.confirmHandoff();
      expect(r.snapshot.currentSeatIndex, 1);
      expect(r.snapshot.lastPayout, isNull);
    });

    test('win, then round change clears it (even a celebratory banner)', () {
      final d = _Dice(miss);
      final c = _game(d);
      c.roll();
      c.roll();
      c.roll();
      final r = _reload(c, (j) {
        final h = Map<String, Object?>.from(j['handoff']! as Map);
        h['restartsRound'] = true;
        j['handoff'] = h;
        j['lastPayout'] = {
          'message': 'Jerilyn hits three 4s! Collects 4 gems (4 gems each).',
          'kind': ScoreKind.threeOfAKind.name,
          'amountCents': 4,
          'celebratory': true,
        };
      });
      final round = r.snapshot.roundNumber;
      r.confirmHandoff();
      expect(r.snapshot.roundNumber, round + 1);
      expect(r.snapshot.lastPayout, isNull);
    });

    test('straight, then triple 1s on roll 2: only the triple-1s info', () {
      final c = _herTurn();
      final s = c.snapshot;
      expect(s.lastPayout, isNull, reason: 'straight banner gone');
      expect(s.turn!.lastScore.kind, ScoreKind.tripleOnesPay);
      c.bank();
      expect(
        c.snapshot.lastPayout!.message,
        'Jerilyn rolls triple ones! Collects 10 gems (10 gems each).',
      );
    });
  });

  group('roll counter', () {
    test('counts rolls within the current set; set counts banks', () {
      final c = _herTurn();
      final t = c.snapshot.turn!;
      // Her 3rd roll this turn is roll 2 of set 2 (the bank started set 2).
      expect(t.setNumber, 2);
      expect(t.rollNumber, 2);
      expect(t.rollsLeft, 1);
    });

    test('set number survives a checkpoint; next bank is set 3', () {
      final c = _herTurn();
      final back = MatchCheckpoint.fromJson(c.capture().toJson())!;
      expect(back.turn!.setNumber, 2);
      c.bank();
      expect(c.snapshot.turn!.setNumber, 3);
      expect(c.snapshot.turn!.rollNumber, 0);
    });

    test('next seat starts at set 1', () {
      final d = _Dice(straight);
      final c = _game(d);
      c.roll();
      c.bank();
      d.next(miss);
      c.roll();
      c.roll();
      c.roll();
      c.confirmHandoff();
      expect(c.snapshot.currentSeatIndex, 1);
      expect(c.snapshot.turn!.setNumber, 1);
    });
  });

  test('roll 2/3 triple 1s unchanged from 0.1.25 (pay 10, keep playing)', () {
    final c = _herTurn();
    final s0 = c.snapshot;
    final jer = s0.players[0].bankCents;
    final spike = s0.players[1].bankCents;
    final pot = s0.potCents;
    c.bank();
    final s = c.snapshot;
    expect(s.phase, MatchPhase.playing);
    expect(s.players[0].bankCents, jer + 10);
    expect(s.players[1].bankCents, spike - 10);
    expect(s.potCents, pot);
    expect(s.endMessage, isNull);
  });

  Future<void> show(WidgetTester tester, MatchController c) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchProvider.overrideWith(
            () => _Live(MatchViewState(snapshot: c.snapshot)),
          ),
        ],
        child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('screen (9:32): no straight banner; triple-1s hint; set 2', (
    tester,
  ) async {
    await show(tester, _herTurn());
    expect(find.textContaining('nails a straight'), findsNothing);
    expect(find.text('Triple ones — others pay 10 gems'), findsOneWidget);
    expect(find.textContaining('set 2 · roll 2/3'), findsOneWidget);
  });

  testWidgets('screen: three 4s banner gone on roll 2/3 with 6-5-2', (
    tester,
  ) async {
    final d = _Dice(miss);
    final c = _game(d);
    c.roll();
    d.next(fours);
    c.roll();
    c.bank();
    d.next(sixFiveTwo);
    c.roll();
    c.roll();
    await show(tester, c);
    expect(find.textContaining('hits three 4s'), findsNothing);
    expect(find.textContaining('roll 2/3'), findsOneWidget);
  });
}
