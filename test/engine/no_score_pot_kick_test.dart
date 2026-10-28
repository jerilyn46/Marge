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

const whiff = [1, 2, 4]; // 2,3,5: no score, no 1s to chase

/// Human whiffs, hands off to bot seat 1 with [botBank] gems, bot whiffs.
MatchController _botWhiffs(int bots, int botBank) {
  final d = _Dice(whiff);
  final c = MatchController(
    config: MatchConfig(botCount: bots, localPlayerName: 'Jerilyn'),
    rng: d,
  )..startMatch();
  c.roll();
  c.roll();
  c.roll();
  c.confirmHandoff();
  c.debugSetBank(1, botBank);
  for (var i = 0; i < 3 && c.snapshot.phase != MatchPhase.matchEnd; i++) {
    if (c.snapshot.phase == MatchPhase.awaitingHandoff) break;
    c.tickBot();
  }
  return c;
}

void main() {
  test('no-score pot payment: bot paid to 0 is kicked, play continues', () {
    final c = _botWhiffs(2, 2);
    final s = c.snapshot;
    expect(s.players[1].bankCents, 0);
    expect(s.players[1].eliminated, isTrue);
    expect(s.phase, MatchPhase.awaitingHandoff);
  });

  test(
    'no-score pot payment: last opponent kicked → other player takes pot',
    () {
      final c = _botWhiffs(1, 2);
      final s = c.snapshot;
      expect(s.players[1].eliminated, isTrue);
      expect(s.phase, MatchPhase.matchEnd);
      expect(s.potCents, 0);
      expect(s.winnerId, 'human_0');
      expect(s.lastPayout!.message, contains('whiffs and is out of gems'));
      expect(s.lastPayout!.message, contains('wins the pot'));
    },
  );
}
