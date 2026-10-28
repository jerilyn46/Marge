import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';

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

const miss = [2, 2, 0]; // 3,3,1

/// Current (human) seat: 1,1,3 → hold the 1s → 1,1,3 → 1,1,4 (miss).
void _goForOnesAndMiss(MatchController c, _Dice d) {
  d.next([0, 0, 2]);
  c.roll();
  c.toggleKeep(0);
  c.toggleKeep(1);
  d.next([2]);
  c.roll(); // 1,1,3
  d.next([3]);
  c.roll(); // 1,1,4
}

MatchController _game(_Dice d, {MatchConfig? config}) =>
    MatchController(config: config ?? const MatchConfig(botCount: 1), rng: d)
      ..startMatch();

void main() {
  test('human holds two 1s, misses on roll 3: 10 gems to the pot', () {
    final d = _Dice(miss);
    final c = _game(d);
    final bank = c.snapshot.players[0].bankCents;
    final pot = c.snapshot.potCents;
    _goForOnesAndMiss(c, d);
    final s = c.snapshot;
    expect(s.turn!.wentForTripleOnes, isTrue);
    expect(s.phase, MatchPhase.awaitingHandoff);
    expect(s.players[0].bankCents, bank - 10);
    expect(s.potCents, pot + 10);
    expect(s.handoff!.outcomeText, 'Missed triple ones');
    expect(s.handoff!.bankDeltaCents, -10);
    expect(
      s.lastPayout!.message,
      'You missed triple ones — 10 gems to the pot.',
    );
    expect(s.lastPayout!.missedTripleOnes, isTrue);
  });

  test('plain bust (nothing held) is unchanged: 2 gems, "Bust"', () {
    final d = _Dice(miss);
    final c = _game(d);
    final bank = c.snapshot.players[0].bankCents;
    c.roll();
    c.roll();
    c.roll();
    final s = c.snapshot;
    expect(s.players[0].bankCents, bank - 2);
    expect(s.handoff!.outcomeText, 'Bust');
    expect(s.handoff!.bankDeltaCents, -2);
  });

  void heldBust(String name, List<int> roll1, List<int> keep, int expectDelta) {
    test(name, () {
      final d = _Dice(roll1);
      final c = _game(d);
      final bank = c.snapshot.players[0].bankCents;
      c.roll();
      for (final i in keep) {
        c.toggleKeep(i);
      }
      d.next(miss);
      c.roll();
      c.roll();
      final s = c.snapshot;
      expect(
        s.phase,
        MatchPhase.awaitingHandoff,
        reason: '${s.turn?.dice.values}',
      );
      expect(s.players[0].bankCents, bank - expectDelta);
    });
  }

  // Edge cases: only "two 1s held, third re-rolled" counts.
  heldBust('one 1 held → normal 2-gem bust', [0, 4, 4], [0], 2);
  heldBust('a 1 and a 3 held → normal bust', [0, 2, 4], [0, 1], 2);
  heldBust('two 4s held → normal bust', [3, 3, 4], [0, 1], 2);
  heldBust('all three held (1,1,3) → normal bust', [0, 0, 2], [0, 1, 2], 2);

  test('two 1s held on roll 2 only (dropped for roll 3) → normal bust', () {
    final d = _Dice([0, 0, 2]);
    final c = _game(d);
    final bank = c.snapshot.players[0].bankCents;
    c.roll();
    c.toggleKeep(0);
    c.toggleKeep(1);
    d.next([2]);
    c.roll();
    c.toggleKeep(0);
    c.toggleKeep(1); // let them go
    d.next(miss);
    c.roll();
    expect(c.snapshot.players[0].bankCents, bank - 2);
  });

  test('roll 3 makes another scoring hand → normal scoring, no charge', () {
    // Hold one 1, roll 3 gives 2,3: straight.
    final d = _Dice([0, 4, 4]);
    final c = _game(d);
    final bank = c.snapshot.players[0].bankCents;
    c.roll();
    c.toggleKeep(0);
    d.next([4, 4]);
    c.roll();
    d.next([1, 2]);
    c.roll(); // 1,2,3
    final s = c.snapshot;
    expect(s.turn!.lastScore.kind, ScoreKind.straight);
    c.bank();
    expect(c.snapshot.players[0].bankCents, bank + 5);
  });

  test('two 1s held and roll 3 is a 1 → triple ones pay (unchanged)', () {
    final d = _Dice([0, 0, 2]);
    final c = _game(d);
    c.roll();
    c.toggleKeep(0);
    c.toggleKeep(1);
    d.next([2]);
    c.roll();
    d.next([0]);
    c.roll();
    expect(c.snapshot.turn!.lastScore.kind, ScoreKind.tripleOnesPay);
    expect(c.snapshot.phase, MatchPhase.playing);
  });

  test('bot holds two 1s and misses: 10 to the pot', () {
    final d = _Dice(miss);
    final c = _game(d);
    c.roll();
    c.roll();
    c.roll();
    c.confirmHandoff(); // bot's turn
    final bot = c.snapshot.players[1].bankCents;
    final pot = c.snapshot.potCents;
    d.next([0, 0, 2]);
    c.tickBot(); // 1,1,3
    d.next([2]);
    c.tickBot(); // holds the 1s
    expect(c.snapshot.turn!.dice.keptFlags, [true, true, false]);
    d.next([3]);
    c.tickBot();
    final s = c.snapshot;
    expect(s.players[1].bankCents, bot - 10);
    expect(s.potCents, pot + 10);
    expect(s.handoff!.outcomeText, 'Missed triple ones');
  });

  test('bot short: pays what it has into the pot and is knocked out', () {
    final d = _Dice(miss);
    final c = _game(
      d,
      config: const MatchConfig(botCount: 2, startBankCents: 15),
    );
    c.roll();
    c.roll();
    c.roll();
    c.confirmHandoff();
    final pot = c.snapshot.potCents;
    d.next([0, 0, 2]);
    c.tickBot();
    d.next([2]);
    c.tickBot();
    d.next([3]);
    c.tickBot();
    final s = c.snapshot;
    expect(s.pendingShortfall, isNull);
    expect(s.players[1].bankCents, 0);
    expect(s.players[1].eliminated, isTrue);
    expect(s.potCents, pot + 5);
    expect(s.phase, MatchPhase.awaitingHandoff);
    expect(s.handoff!.bankDeltaCents, -5);
    c.confirmHandoff();
    expect(c.snapshot.currentSeatIndex, 2);
  });

  test('hotseat: Player 2 holds two 1s and misses', () {
    final d = _Dice(miss);
    final c = _game(
      d,
      config: const MatchConfig(botCount: 0, otherHumanCount: 1),
    );
    c.roll();
    c.roll();
    c.roll();
    c.confirmHandoff();
    expect(c.snapshot.currentPlayer.profile.name, 'Player 2');
    final bank = c.snapshot.players[1].bankCents;
    _goForOnesAndMiss(c, d);
    final s = c.snapshot;
    expect(s.players[1].bankCents, bank - 10);
    expect(s.handoff!.outcomeText, 'Missed triple ones');
  });

  group('human shortfall', () {
    MatchController short(_Dice d) {
      final c = _game(
        d,
        config: const MatchConfig(botCount: 2, startBankCents: 15),
      ); // 5 at the table after the ante
      _goForOnesAndMiss(c, d);
      return c;
    }

    test('add gems, then pay 10 in full', () {
      final d = _Dice(miss);
      final c = short(d);
      var s = c.snapshot;
      expect(s.phase, MatchPhase.awaitingShortfall);
      expect(s.pendingShortfall!.toPot, isTrue);
      expect(s.pendingShortfall!.dueGems, 10);
      final pot = s.potCents;
      expect(c.coverShortfall(), isFalse);
      c.grantLocalPlayCoins(20);
      expect(c.coverShortfall(), isTrue);
      s = c.snapshot;
      expect(s.players[0].bankCents, 25 - 10);
      expect(s.players[0].eliminated, isFalse);
      expect(s.potCents, pot + 10);
      expect(s.phase, MatchPhase.awaitingHandoff);
      expect(s.handoff!.outcomeText, 'Missed triple ones');
      expect(s.handoff!.bankDeltaCents, -10);
    });

    test('pay what they have and leave', () {
      final d = _Dice(miss);
      final c = short(d);
      final pot = c.snapshot.potCents;
      c.quitShortfall();
      final s = c.snapshot;
      expect(s.players[0].bankCents, 0);
      expect(s.players[0].eliminated, isTrue);
      expect(s.potCents, pot + 5);
      expect(
        s.lastPayout!.message,
        'You missed triple ones — 5 gems to the pot.',
      );
    });
  });

  test('+50 House stake: not drawn for the 10; owed amount unchanged', () {
    final d = _Dice(miss);
    final c = _game(
      d,
      config: const MatchConfig(
        botCount: 1,
        startBankCents: 11,
        houseStakeCents: 50,
      ),
    ); // 1 gem at the table after ante
    // Normal bust (2) draws the stake once: 1 + 50 - 2 = 49.
    c.roll();
    c.roll();
    c.roll();
    expect(c.snapshot.players[0].usedHouseStake, isTrue);
    expect(c.snapshot.players[0].bankCents, 49);
    // Bots bust; back to You.
    for (
      var k = 0;
      k < 50 &&
          (c.snapshot.currentSeatIndex != 0 ||
              c.snapshot.phase == MatchPhase.awaitingHandoff);
      k++
    ) {
      if (c.snapshot.phase == MatchPhase.awaitingHandoff) {
        d.next([5, 3, 1]); // 6,4,2: bots never score or pair
        c.confirmHandoff();
      } else {
        c.tickBot();
      }
    }
    _goForOnesAndMiss(c, d);
    final s = c.snapshot;
    expect(s.players[0].bankCents, 39);
    expect(MatchController.houseStakeOwed(s.players[0], c.config), 50);

    // Without a stake used, a short human gets the shortfall choice; the
    // stake is not silently drawn.
    final d2 = _Dice(miss);
    final c2 = _game(
      d2,
      config: const MatchConfig(botCount: 1, startBankCents: 15),
    );
    _goForOnesAndMiss(c2, d2);
    expect(c2.snapshot.phase, MatchPhase.awaitingShortfall);
    expect(c2.snapshot.players[0].usedHouseStake, isFalse);
  });

  group('bot zeroed by missed-roll pot payment is kicked', () {
    MatchController botMisses(_Dice d, int bots, int start) {
      final c = _game(
        d,
        config: MatchConfig(botCount: bots, startBankCents: start),
      );
      c.roll();
      c.roll();
      c.roll();
      c.confirmHandoff();
      d.next([0, 0, 2]);
      c.tickBot();
      d.next([2]);
      c.tickBot();
      d.next([3]);
      c.tickBot();
      return c;
    }

    test('pays exactly 10 to 0 → kicked, game continues', () {
      final d = _Dice(miss);
      final c = botMisses(d, 2, 20);
      final s = c.snapshot;
      expect(s.players[1].bankCents, 0);
      expect(s.players[1].eliminated, isTrue);
      expect(s.phase, MatchPhase.awaitingHandoff);
      c.confirmHandoff();
      expect(c.snapshot.currentSeatIndex, 2);
    });

    test('last opponent kicked at 0 → other player sweeps the pot', () {
      final d = _Dice(miss);
      final c = botMisses(d, 1, 20);
      final s = c.snapshot;
      expect(s.players[1].eliminated, isTrue);
      expect(s.phase, MatchPhase.matchEnd);
      expect(s.potCents, 0);
      expect(s.lastPayout!.message, contains('wins the pot'));
    });

    test('short bot, last opponent → other player sweeps the pot', () {
      final d = _Dice(miss);
      final c = botMisses(d, 1, 15);
      final s = c.snapshot;
      expect(s.players[1].eliminated, isTrue);
      expect(s.phase, MatchPhase.matchEnd);
      expect(s.potCents, 0);
    });
  });
}
