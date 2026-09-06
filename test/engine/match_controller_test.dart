import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/dice.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/engine/player.dart';

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
  group('MatchConfig lobby helpers', () {
    test('default is 3 bots + 0 other humans', () {
      const c = MatchConfig();
      expect(c.botCount, 3);
      expect(c.otherHumanCount, 0);
      expect(c.humanCount, 1);
      expect(c.seatCount, 4);
      expect(c.isValid, isTrue);
    });

    test('requires at least one opponent', () {
      const c = MatchConfig(botCount: 0, otherHumanCount: 0);
      expect(c.isValid, isFalse);
      expect(c.opponentCount, 0);
    });

    test('clamp helpers cap at 7 opponents and 0–4 steppers', () {
      expect(MatchConfig.clampLobby(4, 4), (3, 4)); // trims bots to keep others
      expect(MatchConfig.clampBots(4, 4), 3);
      expect(MatchConfig.clampOthers(4, 4), 3);
      expect(MatchConfig.clampLobby(9, 0), (4, 0));
      expect(MatchConfig.clampOthers(0, 9), 4);
      expect(MatchConfig.canIncrementBots(4, 3), isFalse); // 7 already
      expect(MatchConfig.canIncrementOthers(3, 4), isFalse);
      expect(MatchConfig.canIncrementBots(2, 2), isTrue);
    });
  });

  group('MatchController', () {
    test('starts with 100¢ banks and collects ante into pot', () {
      final c = MatchController(
        config: const MatchConfig(botCount: 3, otherHumanCount: 0),
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

    test('hotseat 1 other human + 2 bots', () {
      final c = MatchController(
        config: const MatchConfig(
          botCount: 2,
          otherHumanCount: 1,
          humanNames: ['A', 'B'],
        ),
        rng: Random(1),
      );
      c.startMatch();
      expect(c.snapshot.players.where((p) => p.profile.isHuman).length, 2);
      expect(c.snapshot.players.where((p) => p.profile.isBot).length, 2);
      expect(c.snapshot.players[0].profile.name, 'A');
      expect(c.snapshot.players[1].profile.name, 'B');
    });

    test('bots-only opponents: 4 bots + 0 other humans', () {
      final c = MatchController(
        config: const MatchConfig(botCount: 4, otherHumanCount: 0),
        rng: Random(1),
      );
      c.startMatch();
      expect(c.snapshot.players.length, 5);
      expect(c.snapshot.players.where((p) => p.profile.isHuman).length, 1);
      expect(c.snapshot.players.where((p) => p.profile.isBot).length, 4);
      expect(c.snapshot.potCents, 50); // 5 * 10
    });

    test('humans-only opponents: 0 bots + 3 other humans', () {
      final c = MatchController(
        config: const MatchConfig(botCount: 0, otherHumanCount: 3),
        rng: Random(1),
      );
      c.startMatch();
      expect(c.snapshot.players.length, 4);
      expect(c.snapshot.players.every((p) => p.profile.isHuman), isTrue);
      expect(c.snapshot.players[0].profile.name, 'You');
      expect(c.snapshot.players[1].profile.name, 'Player 2');
      expect(c.snapshot.players[2].profile.name, 'Player 3');
      expect(c.snapshot.players[3].profile.name, 'Player 4');
    });

    test('max table: 3 bots + 4 other humans = 8 seats', () {
      final c = MatchController(
        config: const MatchConfig(botCount: 3, otherHumanCount: 4),
        rng: Random(1),
      );
      c.startMatch();
      expect(c.snapshot.players.length, 8);
      expect(c.snapshot.players.where((p) => p.profile.isHuman).length, 5);
      expect(c.snapshot.players.where((p) => p.profile.isBot).length, 3);
      expect(c.snapshot.potCents, 80);
    });

    test('bot personalities cycle Aggressive/Cautious/Chaotic', () {
      final c = MatchController(
        config: const MatchConfig(botCount: 4, otherHumanCount: 0),
        rng: Random(1),
      );
      c.startMatch();
      final bots =
          c.snapshot.players.where((p) => p.profile.isBot).toList();
      expect(bots[0].profile.personality, BotPersonality.aggressive);
      expect(bots[1].profile.personality, BotPersonality.cautious);
      expect(bots[2].profile.personality, BotPersonality.chaotic);
      expect(bots[3].profile.personality, BotPersonality.aggressive);
    });

    test('minimum 1 bot opponent', () {
      final c = MatchController(
        config: const MatchConfig(botCount: 1, otherHumanCount: 0),
        rng: Random(1),
      );
      c.startMatch();
      expect(c.snapshot.players.length, 2);
      expect(c.snapshot.potCents, 20);
    });

    test('triple-1 first roll sweeps pot', () {
      // DiceSet.rollAll uses nextInt(6)+1 three times.
      // We need 1,1,1 → nextInt returns 0,0,0.
      final rng = ScriptedRandom([0, 0, 0]);
      final c = MatchController(
        config: const MatchConfig(botCount: 3, otherHumanCount: 0),
        rng: rng,
      );
      c.startMatch();
      expect(c.snapshot.potCents, 40);
      expect(c.snapshot.currentPlayer.profile.isHuman, isTrue);
      final before = c.snapshot.currentPlayer.bankCents;
      c.roll();
      var s = c.snapshot;
      expect(s.lastPayout?.kind, ScoreKind.tripleOnesPotWin);
      expect(s.lastPayout?.celebratory, isTrue);
      expect(s.lastPayout?.amountCents, 40);
      expect(s.phase, MatchPhase.awaitingHandoff);
      expect(s.handoff, isNotNull);
      expect(s.handoff!.outcomeText, 'Pot sweep!');
      expect(s.handoff!.bankDeltaCents, 40);
      expect(s.handoff!.diceValues, [1, 1, 1]);
      expect(s.handoff!.restartsRound, isTrue);
      // Banks updated, but ante / next round wait for confirm.
      final winnerMid =
          s.players.firstWhere((p) => p.profile.isHuman);
      expect(winnerMid.bankCents, before + 40);
      expect(s.potCents, 0);
      expect(s.roundNumber, 1);

      c.confirmHandoff();
      s = c.snapshot;
      // After pot win + confirm, round restarts with ante.
      // Winner: before+40, then ante -10 → before+30
      final winner = s.players.firstWhere((p) => p.profile.isHuman);
      expect(winner.bankCents, before + 40 - 10);
      expect(s.potCents, 40); // new ante
      expect(s.roundNumber, 2);
      expect(s.phase, MatchPhase.playing);
      expect(s.handoff, isNull);
      expect(
        s.log.any((l) => l.contains('sweeps the pot')),
        isTrue,
      );
    });

    test('three of a kind collects face from others', () {
      // Roll three 4s on first roll: nextInt → 3,3,3
      final rng = ScriptedRandom([3, 3, 3]);
      final c = MatchController(
        config: const MatchConfig(botCount: 3, otherHumanCount: 0),
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
        config: const MatchConfig(botCount: 3, otherHumanCount: 0),
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

    test('roll1 no score stays on turn with rollsLeft=2', () {
      // 1,1,2 — not a winning hand
      final rng = ScriptedRandom([0, 0, 1]);
      final c = MatchController(
        config: const MatchConfig(botCount: 3, otherHumanCount: 0),
        rng: rng,
      );
      c.startMatch();
      final humanId = c.snapshot.currentPlayer.profile.id;
      c.roll();
      final turn = c.snapshot.turn;
      expect(turn, isNotNull);
      expect(turn!.rollNumber, 1);
      expect(turn.rollsLeft, 2);
      expect(turn.lastScore.isScoring, isFalse);
      expect(turn.canRoll, isTrue);
      expect(turn.canBank, isFalse);
      expect(turn.mustFinish, isFalse);
      // Still the same player's turn — must not auto-end.
      expect(c.snapshot.currentPlayer.profile.id, humanId);
      expect(c.snapshot.phase, MatchPhase.playing);
      // bank() must refuse to end early without a score.
      c.bank();
      expect(c.snapshot.turn, isNotNull);
      expect(c.snapshot.currentPlayer.profile.id, humanId);
      expect(c.snapshot.turn!.rollsLeft, 2);
    });

    test('bust after 3 no-score rolls puts 2¢ in pot', () {
      // Force non-scoring rolls. Keep re-rolling all.
      // Sequence of 9 faces all pairs-ish: 0,0,1, 0,0,1, 0,0,1 → 1,1,2
      final seq = <int>[];
      for (var r = 0; r < 3; r++) {
        seq.addAll([0, 0, 1]); // 1,1,2
      }
      final rng = ScriptedRandom(seq);
      final c = MatchController(
        config: const MatchConfig(botCount: 3, otherHumanCount: 0),
        rng: rng,
      );
      c.startMatch();
      final potBefore = c.snapshot.potCents;
      final humanBefore = c.snapshot.currentPlayer.bankCents;
      c.roll(); // 1 — no score, turn continues
      expect(c.snapshot.turn!.rollsLeft, 2);
      expect(c.snapshot.turn!.lastScore.isScoring, isFalse);
      c.roll(); // 2 — still no score
      expect(c.snapshot.turn!.rollsLeft, 1);
      c.roll(); // 3 — auto-bust applies
      expect(c.snapshot.potCents, potBefore + 2);
      // Turn advanced after bust — human paid 2¢
      final human = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
      expect(human.bankCents, humanBefore - 2);
      expect(
        c.snapshot.log.any((l) => l.contains('whiffs')),
        isTrue,
      );
    });

    test('scoring hand can bank early while rolls remain', () {
      // Three 4s on first roll
      final rng = ScriptedRandom([3, 3, 3]);
      final c = MatchController(
        config: const MatchConfig(botCount: 3, otherHumanCount: 0),
        rng: rng,
      );
      c.startMatch();
      c.roll();
      expect(c.snapshot.turn!.lastScore.isScoring, isTrue);
      expect(c.snapshot.turn!.rollsLeft, 2);
      expect(c.snapshot.turn!.canBank, isTrue);
      expect(c.snapshot.turn!.canRoll, isTrue);
      final humanBefore = c.snapshot.currentPlayer.bankCents;
      c.bank();
      final human = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
      expect(human.bankCents, humanBefore + 12);
    });

    test('house stake tops up once when soft-broke', () {
      final c = MatchController(
        config: const MatchConfig(
          botCount: 3,
          otherHumanCount: 0,
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

    test('hotseat human turn advances to next human when no bots', () {
      // Force non-scoring 3-roll bust so turn advances.
      final seq = <int>[];
      for (var r = 0; r < 3; r++) {
        seq.addAll([0, 0, 1]);
      }
      final rng = ScriptedRandom(seq);
      final c = MatchController(
        config: const MatchConfig(botCount: 0, otherHumanCount: 1),
        rng: rng,
      );
      c.startMatch();
      expect(c.snapshot.currentPlayer.profile.id, 'human_0');
      c.roll();
      c.roll();
      c.roll(); // bust → handoff gate
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      expect(c.snapshot.currentPlayer.profile.id, 'human_0');
      expect(HandoffState.isHotseatCta(c.config), isTrue);
      c.confirmHandoff();
      expect(c.snapshot.currentPlayer.profile.id, 'human_1');
      expect(c.snapshot.currentPlayer.profile.name, 'Player 2');
      expect(c.snapshot.currentPlayer.profile.isHuman, isTrue);
      expect(c.snapshot.phase, MatchPhase.playing);
    });

    test('handoff gate: bank holds next seat until confirm', () {
      final rng = ScriptedRandom([3, 3, 3]); // trips on 4
      final c = MatchController(
        config: const MatchConfig(botCount: 3, otherHumanCount: 0),
        rng: rng,
      );
      c.startMatch();
      c.roll();
      c.bank();
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      expect(c.snapshot.handoff, isNotNull);
      expect(c.snapshot.handoff!.outcomeText, 'Three of a kind');
      expect(c.snapshot.handoff!.bankDeltaCents, 12);
      expect(c.snapshot.handoff!.diceValues, [4, 4, 4]);
      expect(c.snapshot.handoff!.restartsRound, isFalse);
      expect(c.snapshot.currentSeatIndex, 0);
      // Solo vs bots → Continue CTA (not Next player).
      expect(HandoffState.isHotseatCta(c.config), isFalse);
      // Bots must not act while gated.
      expect(c.tickBot(), isFalse);
      c.confirmHandoff();
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.handoff, isNull);
      expect(c.snapshot.currentSeatIndex, 1);
      expect(c.snapshot.currentPlayer.profile.isBot, isTrue);
    });

    test('handoff gate: bust signed delta is negative', () {
      final seq = <int>[];
      for (var r = 0; r < 3; r++) {
        seq.addAll([0, 0, 1]);
      }
      final c = MatchController(
        config: const MatchConfig(botCount: 1, otherHumanCount: 0),
        rng: ScriptedRandom(seq),
      );
      c.startMatch();
      c.roll();
      c.roll();
      c.roll();
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      expect(c.snapshot.handoff!.outcomeText, 'Bust');
      expect(c.snapshot.handoff!.bankDeltaCents, -2);
      expect(c.snapshot.turn, isNotNull); // dice still locked on turn
      c.confirmHandoff();
      expect(c.snapshot.handoff, isNull);
      expect(c.snapshot.turn!.hasRolled, isFalse);
      expect(c.snapshot.currentPlayer.profile.isBot, isTrue);
    });

    test('mid-turn no-score does not enter handoff (keep rolling)', () {
      final rng = ScriptedRandom([0, 0, 1]);
      final c = MatchController(
        config: const MatchConfig(botCount: 1, otherHumanCount: 0),
        rng: rng,
      );
      c.startMatch();
      c.roll();
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.handoff, isNull);
      expect(c.snapshot.turn!.rollsLeft, 2);
      expect(c.snapshot.turn!.canBank, isFalse);
      c.bank(); // refused
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.handoff, isNull);
    });
  });
}
