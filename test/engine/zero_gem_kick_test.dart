import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';

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

const miss = [2, 2, 0]; // 3,3,1
const ones = [0, 0, 0];
const fours = [3, 3, 3];
const straight = [0, 1, 2];

MatchController _start(_Dice d, {int bots = 1}) => MatchController(
  config: MatchConfig(botCount: bots, localPlayerName: 'Jerilyn'),
  rng: d,
)..startMatch();

int _humanSeat(MatchController c) =>
    c.snapshot.players.indexWhere((p) => p.profile.id == 'human_0');

void main() {
  test(
    'Jerilyn screenshot: bot Spike short 8 of 10 → kicked, Jerilyn sweeps pot',
    () {
      final d = _Dice(miss);
      final c = _start(d);
      final me = _humanSeat(c);
      final spike = 1 - me;
      c.debugSetBank(spike, 8);
      final potBefore = c.snapshot.potCents;
      final myBefore = c.snapshot.players[me].bankCents;
      c.roll(); // miss
      d.next(ones);
      c.roll(); // triple ones on roll 2 → 10 each
      if (c.snapshot.phase != MatchPhase.matchEnd) c.bank();
      final s = c.snapshot;
      expect(s.players[spike].bankCents, 0);
      expect(s.players[spike].eliminated, isTrue);
      expect(s.phase, MatchPhase.matchEnd);
      expect(s.potCents, 0);
      expect(s.players[me].bankCents, myBefore + 8 + potBefore);
      expect(s.winnerId, 'human_0');
      final msg = s.lastPayout!.message;
      expect(msg, contains('Collects 8 gems'));
      expect(msg, contains('had only 8 of 10'));
      expect(msg, isNot(contains('(10 gems each)')));
      expect(msg, contains('wins the pot'));
    },
  );

  test('multi-opponent: only the zeroed player is kicked, play continues', () {
    final d = _Dice(straight);
    final c = _start(d, bots: 2);
    final me = _humanSeat(c);
    final others = [0, 1, 2].where((i) => i != me).toList();
    c.debugSetBank(others[0], 3);
    final potBefore = c.snapshot.potCents;
    c.roll(); // straight → 5 each
    c.bank();
    final s = c.snapshot;
    expect(s.players[others[0]].eliminated, isTrue);
    expect(s.players[others[1]].eliminated, isFalse);
    expect(s.phase, isNot(MatchPhase.matchEnd));
    expect(s.potCents, potBefore);
    expect(s.lastPayout!.message, contains('Collects 8 gems'));
    expect(s.lastPayout!.message, contains('out of the game'));
  });

  test('full pay leaving opponent > 0: banner says "N gems each", no kick', () {
    final d = _Dice(straight);
    final c = _start(d);
    final me = _humanSeat(c);
    c.roll();
    c.bank();
    final s = c.snapshot;
    expect(s.players[1 - me].eliminated, isFalse);
    expect(s.lastPayout!.message, contains('Collects 5 gems (5 gems each)'));
  });

  test('first-roll trips paid exactly to 0 → kicked + pot sweep', () {
    final d = _Dice(fours);
    final c = _start(d);
    final me = _humanSeat(c);
    final bot = 1 - me;
    c.debugSetBank(bot, 8); // 2×4 = 8 due
    final pot = c.snapshot.potCents;
    final before = c.snapshot.players[me].bankCents;
    c.roll();
    expect(
      c.snapshot.turn?.lastScore.kind ?? ScoreKind.threeOfAKind,
      ScoreKind.threeOfAKind,
    );
    c.bank();
    final s = c.snapshot;
    expect(s.players[bot].eliminated, isTrue);
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.players[me].bankCents, before + 8 + pot);
    expect(s.potCents, 0);
  });

  test('payoutBreakdown copy', () {
    expect(
      MatchController.payoutBreakdown(10, {'A': 10, 'B': 10}),
      '10 gems each',
    );
    expect(
      MatchController.payoutBreakdown(10, {'Spike': 8}),
      'Spike had only 8 of 10',
    );
    expect(
      MatchController.payoutBreakdown(10, {'A': 10, 'Spike': 0}),
      '10 gems each from one player; Spike had only 0 of 10',
    );
  });

  MatchController hotseat(_Dice d, {int bots = 0}) => MatchController(
    config: MatchConfig(
      botCount: bots,
      otherHumanCount: 1,
      localPlayerName: 'Jerilyn',
    ),
    rng: d,
  )..startMatch();

  int otherHuman(MatchController c) => c.snapshot.players.indexWhere(
    (p) =>
        !p.profile.isBot && p.profile.id != 'human_0' && p.profile.participates,
  );

  MatchController humanAtZero({int bots = 0}) {
    final d = _Dice(miss);
    final c = hotseat(d, bots: bots);
    expect(c.snapshot.currentSeatIndex, _humanSeat(c));
    c.debugSetBank(otherHuman(c), 8);
    c.roll();
    d.next(ones);
    c.roll(); // triple ones roll 2 → 10 each
    if (c.snapshot.phase != MatchPhase.awaitingShortfall) c.bank();
    return c;
  }

  test('human at 0 is NOT auto-kicked: buy-more-or-quit dialog', () {
    final c = humanAtZero();
    final s = c.snapshot;
    final h = otherHuman(c);
    expect(s.players[h].bankCents, 0);
    expect(s.players[h].eliminated, isFalse);
    expect(s.phase, MatchPhase.awaitingShortfall);
    expect(s.pendingShortfall!.zeroBank, isTrue);
    expect(s.pendingShortfall!.payerSeatIndex, h);
    expect(s.lastPayout!.message, contains('had only 8 of 10'));
    expect(s.lastPayout!.message, contains('buy more gems or quit'));
  });

  test('human at 0 quits → the other player gets the pot', () {
    final c = humanAtZero();
    final me = _humanSeat(c);
    final pot = c.snapshot.potCents;
    final before = c.snapshot.players[me].bankCents;
    c.quitShortfall();
    final s = c.snapshot;
    expect(s.players[otherHuman(c)].eliminated, isTrue);
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.potCents, 0);
    expect(s.players[me].bankCents, before + pot);
    expect(s.winnerId, 'human_0');
    expect(s.lastPayout!.message, contains('wins the pot'));
  });

  test('human at 0 buys more gems → stays in, play continues', () {
    final c = humanAtZero();
    final h = otherHuman(c);
    final pot = c.snapshot.potCents;
    expect(c.coverShortfall(), isFalse); // nothing added yet
    c.addTableGems(h, 10);
    expect(c.coverShortfall(), isTrue);
    final s = c.snapshot;
    expect(s.players[h].eliminated, isFalse);
    expect(s.players[h].bankCents, 10);
    expect(s.phase, isNot(MatchPhase.matchEnd));
    expect(s.pendingShortfall, isNull);
    expect(s.potCents, pot);
  });

  test('mix: bot at 0 kicked, human at 0 gets the choice', () {
    final d = _Dice(straight);
    final c = hotseat(d, bots: 1);
    final bot = c.snapshot.players.indexWhere((p) => p.profile.isBot);
    final h = otherHuman(c);
    c.debugSetBank(bot, 3);
    c.debugSetBank(h, 5);
    c.roll(); // straight → 5 each
    c.bank();
    final s = c.snapshot;
    expect(s.players[bot].eliminated, isTrue);
    expect(s.players[h].eliminated, isFalse);
    expect(s.phase, MatchPhase.awaitingShortfall);
    expect(s.pendingShortfall!.zeroBank, isTrue);
    c.quitShortfall();
    expect(c.snapshot.phase, MatchPhase.matchEnd);
    expect(c.snapshot.winnerId, 'human_0');
  });
}
