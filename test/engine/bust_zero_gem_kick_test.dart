import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
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

// Faces 5, 6, 1 (as in the Flip 7 screenshot): no score, a lone 1.
const bust561 = [4, 5, 0];

/// Human busts, hands off to bot seat 1 with [botBank] gems (House stake
/// already used), bot busts on its 3rd roll and can only pay what it has.
MatchController _botBusts(int bots, int botBank) {
  final c = MatchController(
    config: MatchConfig(botCount: bots, localPlayerName: 'Jerilyn'),
    rng: _Dice(bust561),
  )..startMatch();
  c.roll();
  c.roll();
  c.roll();
  c.confirmHandoff();
  c.debugSetBank(1, botBank);
  for (var i = 0; i < 6 && c.snapshot.phase != MatchPhase.matchEnd; i++) {
    if (c.snapshot.phase == MatchPhase.awaitingHandoff) break;
    c.tickBot();
  }
  return c;
}

void main() {
  test('bust -1: bot with 1 gem pays bust to 0 and is kicked', () {
    final c = _botBusts(2, 1);
    final s = c.snapshot;
    expect(s.players[1].bankCents, 0);
    expect(s.players[1].eliminated, isTrue);
    expect(s.phase, MatchPhase.awaitingHandoff);
  });

  test('bust -1: last opponent kicked → remaining player takes pot', () {
    final c = _botBusts(1, 1);
    final s = c.snapshot;
    expect(s.players[1].bankCents, 0);
    expect(s.players[1].eliminated, isTrue);
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.potCents, 0);
    expect(s.winnerId, 'human_0');
    expect(s.lastPayout!.message, contains('wins the pot'));
  });

  test('ante to 0: bot is kicked; last opponent out → other takes pot', () {
    final c = MatchController(
      config: MatchConfig(
        botCount: 1,
        localPlayerName: 'Jerilyn',
        startBankCents: 10,
      ),
      rng: _Dice(bust561),
    )..startMatch();
    final s = c.snapshot;
    expect(s.players[1].eliminated, isTrue);
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.potCents, 0);
    expect(s.winnerId, 'human_0');
    expect(s.lastPayout!.message, contains('wins the pot'));
  });

  test('ante to 0 with two bots: both kicked, human takes pot', () {
    final c = MatchController(
      config: MatchConfig(
        botCount: 2,
        localPlayerName: 'Jerilyn',
        startBankCents: 10,
      ),
      rng: _Dice(bust561),
    )..startMatch();
    final s = c.snapshot;
    expect(s.players[1].eliminated, isTrue);
    expect(s.players[2].eliminated, isTrue);
    expect(s.players[0].eliminated, isFalse);
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.winnerId, 'human_0');
  });
}
