import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/gem_shortfall.dart';
import 'package:marge/engine/match_controller.dart';

class _Dice implements Random {
  _Dice(this.seq);
  List<int> seq;
  int i = 0;
  @override
  int nextInt(int max) => seq[i++ % seq.length] % max;
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
}

// Faces 5, 6, 1: no score.
const bust561 = [4, 5, 0];

MatchController _humanBustsToZero(int bots) {
  final c = MatchController(
    config: MatchConfig(botCount: bots, localPlayerName: 'Jerilyn'),
    rng: _Dice(bust561),
  )..startMatch();
  c.roll();
  c.roll();
  c.debugSetBank(0, 1);
  c.roll();
  return c;
}

void main() {
  test('human busts to 0 → Out of gems offered, not kicked', () {
    final c = _humanBustsToZero(2);
    final s = c.snapshot;
    expect(s.players[0].bankCents, 0);
    expect(s.players[0].eliminated, isFalse);
    expect(s.phase, MatchPhase.awaitingShortfall);
    final p = s.pendingShortfall!;
    expect(p.zeroBank, isTrue);
    expect(p.payerSeatIndex, 0);
    expect(p.zeroBankThen, ZeroBankThen.handoff);
  });

  test('human bust→0 stays in (+10) → hands off to next seat', () {
    final c = _humanBustsToZero(2);
    c.debugSetBank(0, 10);
    expect(c.coverShortfall(), isTrue);
    final s = c.snapshot;
    expect(s.pendingShortfall, isNull);
    expect(s.players[0].eliminated, isFalse);
    expect(s.players[0].bankCents, 10);
    expect(s.phase, MatchPhase.awaitingHandoff);
  });

  test('human bust→0 quits vs last bot → bot takes the pot', () {
    final c = _humanBustsToZero(1);
    c.quitShortfall();
    final s = c.snapshot;
    expect(s.players[0].eliminated, isTrue);
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.potCents, 0);
    expect(s.winnerId, s.players[1].profile.id);
  });

  test('zeroBankThen survives JSON round trip', () {
    const g = GemShortfall(
      payerSeatIndex: 0,
      rollerSeatIndex: 0,
      dueGems: 10,
      face: 0,
      zeroBank: true,
      zeroBankThen: ZeroBankThen.handoff,
    );
    expect(
      GemShortfall.fromJson(g.toJson())!.zeroBankThen,
      ZeroBankThen.handoff,
    );
  });
}
