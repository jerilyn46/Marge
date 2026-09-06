import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/dice.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';

/// Deterministic RNG that yields a fixed sequence of nextInt results.
class ScriptedRandom implements Random {
  ScriptedRandom(this.sequence);
  final List<int> sequence;
  int i = 0;

  @override
  int nextInt(int max) {
    if (i >= sequence.length) {
      // Fallback pseudo
      return sequence[i++ % sequence.length] % max;
    }
    final v = sequence[i++];
    return v % max;
  }

  @override
  double nextDouble() => 0.5;

  @override
  bool nextBool() => false;
}

void main() {
  group('MatchController', () {
    test('starts with 100¢ banks and collects ante into pot', () {
      final c = MatchController(
        config: const MatchConfig(humanCount: 1),
        rng: Random(1),
      );
      c.startMatch();
      final s = c.snapshot;
      expect(s.roundNumber, 1);
      expect(s.potCents, 40); // 4 * 10
      for (final p in s.players) {
        expect(p.bankCents, 90);
      }
      expect(s.players.where((p) => p.profile.isHuman).length, 1);
      expect(s.players.where((p) => p.profile.isBot).length, 3);
    });

    test('hotseat 2 humans fills with 2 bots', () {
      final c = MatchController(
        config: const MatchConfig(humanCount: 2, humanNames: ['A', 'B']),
        rng: Random(1),
      );
      c.startMatch();
      expect(c.snapshot.players.where((p) => p.profile.isHuman).length, 2);
      expect(c.snapshot.players.where((p) => p.profile.isBot).length, 2);
    });

    test('triple-1 first roll sweeps pot', () {
      // DiceSet.rollAll uses nextInt(6)+1 three times.
      // We need 1,1,1 → nextInt returns 0,0,0.
      final rng = ScriptedRandom([0, 0, 0]);
      final c = MatchController(
        config: const MatchConfig(humanCount: 1),
        rng: rng,
      );
      c.startMatch();
      expect(c.snapshot.potCents, 40);
      expect(c.snapshot.currentPlayer.profile.isHuman, isTrue);
      final before = c.snapshot.currentPlayer.bankCents;
      c.roll();
      final s = c.snapshot;
      expect(s.lastPayout?.kind, ScoreKind.tripleOnesPotWin);
      expect(s.lastPayout?.celebratory, isTrue);
      expect(s.lastPayout?.amountCents, 40);
      // After pot win, round restarts with ante.
      // Winner: before+40, then ante -10 → before+30
      final winner = s.players.firstWhere((p) => p.profile.isHuman);
      expect(winner.bankCents, before + 40 - 10);
      expect(s.potCents, 40); // new ante
      expect(s.roundNumber, 2);
      expect(
        s.log.any((l) => l.contains('sweeps the pot')),
        isTrue,
      );
    });

    test('three of a kind collects face from others', () {
      // Roll three 4s on first roll: nextInt → 3,3,3
      final rng = ScriptedRandom([3, 3, 3]);
      final c = MatchController(
        config: const MatchConfig(humanCount: 1),
        rng: rng,
      );
      c.startMatch();
      c.roll();
      expect(c.snapshot.turn!.lastScore.kind, ScoreKind.threeOfAKind);
      expect(c.snapshot.turn!.lastScore.perOpponentCents, 4);
      final humanBefore = c.snapshot.currentPlayer.bankCents;
      final othersBefore = c.snapshot.players
          .where((p) => p.profile.isBot)
          .map((p) => p.bankCents)
          .toList();
      c.bank();
      final human = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
      expect(human.bankCents, humanBefore + 12); // 3 bots * 4
      final others = c.snapshot.players.where((p) => p.profile.isBot).toList();
      for (var i = 0; i < others.length; i++) {
        expect(others[i].bankCents, othersBefore[i] - 4);
      }
    });

    test('straight collects 5 from others', () {
      // 1,2,3 → nextInt 0,1,2
      final rng = ScriptedRandom([0, 1, 2]);
      final c = MatchController(
        config: const MatchConfig(humanCount: 1),
        rng: rng,
      );
      c.startMatch();
      c.roll();
      expect(c.snapshot.turn!.lastScore.kind, ScoreKind.straight);
      c.bank();
      final human = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
      // Started 90, +15 from bots
      expect(human.bankCents, 105);
    });

    test('bust after 3 rolls puts 2¢ in pot', () {
      // Force non-scoring rolls. Keep re-rolling all.
      // Sequence of 9 faces all pairs-ish: 0,0,1, 0,0,1, 0,0,1 → 1,1,2
      final seq = <int>[];
      for (var r = 0; r < 3; r++) {
        seq.addAll([0, 0, 1]); // 1,1,2
      }
      final rng = ScriptedRandom(seq);
      final c = MatchController(
        config: const MatchConfig(humanCount: 1),
        rng: rng,
      );
      c.startMatch();
      final potBefore = c.snapshot.potCents;
      c.roll(); // 1
      expect(c.snapshot.turn!.lastScore.isScoring, isFalse);
      c.roll(); // 2
      c.roll(); // 3
      expect(c.snapshot.turn!.rollNumber, 3);
      expect(c.snapshot.turn!.lastScore.isScoring, isFalse);
      final bankBefore = c.snapshot.currentPlayer.bankCents;
      c.bank();
      expect(c.snapshot.potCents, potBefore + 2);
      // Human paid 2 then turn advanced — find human
      final human = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
      expect(human.bankCents, bankBefore - 2);
    });

    test('house stake tops up once when soft-broke', () {
      final c = MatchController(
        config: const MatchConfig(
          humanCount: 1,
          startBankCents: 5,
          anteCents: 10,
          houseStakeCents: 50,
        ),
        rng: Random(1),
      );
      c.startMatch();
      // Ante 10 with only 5 → house stake +50, then pay 10.
      final human = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
      expect(human.usedHouseStake, isTrue);
      // 5+50-10 = 45
      expect(human.bankCents, 45);
    });

    test('endMatch sets winner by bank', () {
      final c = MatchController(rng: Random(2));
      c.startMatch();
      c.endMatch();
      expect(c.snapshot.phase, MatchPhase.matchEnd);
      expect(c.snapshot.winnerId, isNotNull);
    });

    test('evaluator wiring: forced dice via roll keeps', () {
      // Sanity: DiceSet.fromValues used by evaluator path
      final d = DiceSet.fromValues([5, 5, 5]);
      final r = HandEvaluator.evaluate(d, rollNumber: 2);
      expect(r.perOpponentCents, 5);
    });
  });
}
