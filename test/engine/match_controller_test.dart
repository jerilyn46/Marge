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
      // Local humans are seated first, so bots do not reduce the human count.
      expect(MatchConfig.clampOthers(4, 4), 4);
      expect(MatchConfig.clampLobby(9, 0), (4, 0));
      expect(MatchConfig.clampOthers(0, 9), 4);
      expect(MatchConfig.canIncrementBots(4, 3), isFalse); // 7 already
      expect(MatchConfig.canIncrementOthers(3, 4), isFalse);
      expect(MatchConfig.canIncrementBots(2, 2), isTrue);
    });

    test('online seats are reserved before bots fill leftovers', () {
      final plan = MatchConfig.clampLobbyCounts(4, 1, 4);
      // 1 hotseat + 4 online = 5 reserved; 2 seats left for bots (max 4).
      expect(plan.others, 1);
      expect(plan.online, 4);
      expect(plan.bots, 2);
      expect(MatchConfig.canIncrementBots(2, 1, 4), isFalse);
      expect(MatchConfig.canIncrementOnline(2, 1, 4), isFalse);
      expect(MatchConfig.canIncrementOthers(2, 1, 4), isTrue);
      // Raising humans trims online, then bots — never the other way around.
      final humansFirst = MatchConfig.clampLobbyCounts(4, 4, 4);
      expect(humansFirst.others, 4);
      expect(humansFirst.online, 3);
      expect(humansFirst.bots, 0);
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

    test('humans then waiting online then leftover bots', () {
      final c = MatchController(
        config: const MatchConfig(
          botCount: 2,
          otherHumanCount: 1,
          onlinePlayerCount: 2,
          humanNames: ['A', 'B'],
        ),
        rng: Random(1),
      );
      c.startMatch();
      final players = c.snapshot.players;
      expect(players.map((p) => p.profile.kind).toList(), [
        SeatKind.human,
        SeatKind.human,
        SeatKind.waiting,
        SeatKind.waiting,
        SeatKind.bot,
        SeatKind.bot,
      ]);
      expect(players[0].profile.name, 'A');
      expect(players[1].profile.name, 'B');
      expect(players[2].profile.name, WaitingSeat.name);
      expect(players[3].profile.name, WaitingSeat.name);
      expect(players[2].profile.id, 'online_0');
      expect(players[3].profile.isWaiting, isTrue);
      expect(players[2].profile.isBot, isFalse);
      expect(players[4].profile.name, 'Spike');
      expect(players[5].profile.name, 'Mira');
      // Waiting chairs do not ante or invent a person.
      expect(c.snapshot.potCents, 40); // you + human + 2 bots
      expect(players[2].bankCents, 0);
      expect(players.where((p) => p.profile.isBot).length, 2);
      expect(c.config.onlineSeatsAreWaiting, isTrue);
      expect(c.snapshot.log.first, contains('waiting for online players'));
    });

    test('waiting seats do not pay on a scored hand and are skipped', () {
      final rng = ScriptedRandom([3, 3, 3]); // three 4s
      final c = MatchController(
        config: const MatchConfig(
          botCount: 1,
          otherHumanCount: 0,
          onlinePlayerCount: 2,
        ),
        rng: rng,
      );
      c.startMatch();
      expect(c.snapshot.players[1].profile.name, WaitingSeat.name);
      expect(c.snapshot.players[2].profile.name, WaitingSeat.name);
      expect(c.snapshot.players[3].profile.isBot, isTrue);
      expect(c.snapshot.potCents, 20); // you + bot only
      final botBefore = c.snapshot.players[3].bankCents;
      c.roll();
      c.bank();
      // Face 4 from the one playable opponent, not the waiting chairs.
      final human = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
      expect(human.bankCents, 90 + 8);
      expect(c.snapshot.players[1].bankCents, 0);
      expect(c.snapshot.players[2].bankCents, 0);
      expect(c.snapshot.players[3].bankCents, botBefore - 8);
      expect(c.snapshot.currentPlayer.profile.isHuman, isTrue);
    });

    test('turn skips waiting chairs and lands on the next bot', () {
      final seq = <int>[];
      for (var r = 0; r < 3; r++) {
        seq.addAll([0, 0, 1]);
      }
      final c = MatchController(
        config: const MatchConfig(
          botCount: 1,
          otherHumanCount: 0,
          onlinePlayerCount: 2,
        ),
        rng: ScriptedRandom(seq),
      );
      c.startMatch();
      c.roll();
      c.roll();
      c.roll();
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      expect(c.snapshot.handoff!.nextSeatIndex, 3);
      c.confirmHandoff();
      expect(c.snapshot.currentPlayer.profile.isBot, isTrue);
      expect(c.snapshot.currentPlayer.profile.name, 'Spike');
      expect(c.snapshot.players.any((p) => p.profile.isWaiting), isTrue);
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
      final bots = c.snapshot.players.where((p) => p.profile.isBot).toList();
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
      final s = c.snapshot;
      expect(s.lastPayout?.kind, ScoreKind.tripleOnesPotWin);
      expect(s.lastPayout?.celebratory, isTrue);
      expect(s.lastPayout?.amountCents, 40);
      // Pot taken, round ended, new ante, same winner keeps the seat.
      expect(s.phase, MatchPhase.playing);
      expect(s.handoff, isNull);
      expect(s.currentPlayer.profile.isHuman, isTrue);
      expect(s.turn!.hasRolled, isFalse);
      expect(s.turn!.rollNumber, 0);
      final winner = s.players.firstWhere((p) => p.profile.isHuman);
      expect(winner.bankCents, before + 40 - 10);
      expect(s.potCents, 40); // new ante
      expect(s.roundNumber, 2);
      expect(s.log.any((l) => l.contains('sweeps the pot')), isTrue);
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
      expect(c.snapshot.turn!.lastScore.perOpponentCents, 8);
      final humanBefore = c.snapshot.currentPlayer.bankCents;
      final othersBefore = c.snapshot.players
          .where((p) => p.profile.isBot)
          .map((p) => p.bankCents)
          .toList();
      c.bank();
      final human = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
      expect(human.bankCents, humanBefore + 24); // 3 bots * 8
      final others = c.snapshot.players.where((p) => p.profile.isBot).toList();
      for (var i = 0; i < others.length; i++) {
        expect(others[i].bankCents, othersBefore[i] - 8);
      }
    });

    test('three 5s on the first roll: each other pays 10 gems', () {
      // 5,5,5 → nextInt 4,4,4
      final rng = ScriptedRandom([4, 4, 4]);
      final c = MatchController(
        config: const MatchConfig(botCount: 2, otherHumanCount: 1),
        rng: rng,
      );
      c.startMatch();
      expect(c.snapshot.potCents, 40);
      c.roll();
      expect(c.snapshot.turn!.lastScore.perOpponentCents, 10);
      final before = {
        for (final p in c.snapshot.players) p.profile.id: p.bankCents,
      };
      c.bank();
      final you = c.snapshot.players.firstWhere(
        (p) => p.profile.id == 'human_0',
      );
      final other = c.snapshot.players.firstWhere(
        (p) => p.profile.id == 'human_1',
      );
      final bot = c.snapshot.players.firstWhere((p) => p.profile.isBot);
      expect(you.bankCents, before['human_0']! + 30);
      expect(other.bankCents, before['human_1']! - 10);
      expect(bot.bankCents, before['bot_0']! - 10);
      expect(c.snapshot.potCents, 40);
      expect(c.snapshot.pendingShortfall, isNull);
      expect(c.snapshot.players.any((p) => p.profile.isWaiting), isFalse);
    });

    test(
      'bot that cannot cover first-roll trips pays what it has and quits',
      () {
        final rng = ScriptedRandom([4, 4, 4]);
        final c = MatchController(
          config: const MatchConfig(
            botCount: 1,
            otherHumanCount: 0,
            startBankCents: 15,
            houseStakeCents: 50,
          ),
          rng: rng,
        );
        c.startMatch();
        // 15 start, ante 10, table 5. Due is 10. Must not invent house gems.
        expect(c.snapshot.players[1].bankCents, 5);
        c.roll();
        c.bank();
        final you = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
        final bot = c.snapshot.players.firstWhere((p) => p.profile.isBot);
        expect(bot.bankCents, 0);
        expect(bot.eliminated, isTrue);
        expect(you.bankCents, 5 + 5);
        expect(c.snapshot.pendingShortfall, isNull);
      },
    );

    test(
      'human shortfall waits for cover or quit and does not take a partial',
      () {
        final rng = ScriptedRandom([4, 4, 4]);
        final c = MatchController(
          config: const MatchConfig(
            botCount: 0,
            otherHumanCount: 1,
            startBankCents: 15,
          ),
          rng: rng,
        );
        c.startMatch();
        c.roll();
        final owedBefore = c.snapshot.players[1].bankCents;
        c.bank();
        expect(c.snapshot.phase, MatchPhase.awaitingShortfall);
        final pending = c.snapshot.pendingShortfall;
        expect(pending, isNotNull);
        expect(pending!.dueGems, 10);
        expect(c.snapshot.players[1].bankCents, owedBefore);
        expect(c.snapshot.players[1].eliminated, isFalse);
        final rollerBefore = c.snapshot.players[0].bankCents;

        c.quitShortfall();
        expect(c.snapshot.players[1].bankCents, 0);
        expect(c.snapshot.players[1].eliminated, isTrue);
        expect(c.snapshot.players[0].bankCents, rollerBefore + owedBefore);
        expect(c.snapshot.pendingShortfall, isNull);
      },
    );

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
      final seat = c.snapshot.currentSeatIndex;
      final pot = c.snapshot.potCents;
      c.roll();
      final turn = c.snapshot.turn;
      expect(turn, isNotNull);
      expect(turn!.rollNumber, 1);
      expect(turn.rollsLeft, 2);
      expect(turn.lastScore.isScoring, isFalse);
      expect(turn.mustKeepRolling, isTrue);
      expect(turn.canRoll, isTrue);
      expect(turn.canBank, isFalse);
      expect(turn.mustFinish, isFalse);
      // Still the same player's turn — must not auto-end or bust.
      expect(c.snapshot.currentPlayer.profile.id, humanId);
      expect(c.snapshot.currentSeatIndex, seat);
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.handoff, isNull);
      expect(c.snapshot.potCents, pot);
      expect(c.snapshot.lastPayout, isNull);
      // bank() must refuse to end early without a score.
      c.bank();
      expect(c.snapshot.turn, isNotNull);
      expect(c.snapshot.currentPlayer.profile.id, humanId);
      expect(c.snapshot.currentSeatIndex, seat);
      expect(c.snapshot.turn!.rollsLeft, 2);
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.handoff, isNull);
    });

    test('roll2 no score stays on turn with rollsLeft=1', () {
      final rng = ScriptedRandom([0, 0, 1, 0, 0, 1]);
      final c = MatchController(
        config: const MatchConfig(botCount: 1, otherHumanCount: 0),
        rng: rng,
      );
      c.startMatch();
      final humanId = c.snapshot.currentPlayer.profile.id;
      final pot = c.snapshot.potCents;
      c.roll();
      c.roll();
      final turn = c.snapshot.turn!;
      expect(turn.rollNumber, 2);
      expect(turn.rollsLeft, 1);
      expect(turn.lastScore.isScoring, isFalse);
      expect(turn.mustKeepRolling, isTrue);
      expect(turn.canBank, isFalse);
      expect(c.snapshot.currentPlayer.profile.id, humanId);
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.handoff, isNull);
      expect(c.snapshot.potCents, pot);
      c.bank();
      expect(c.snapshot.currentPlayer.profile.id, humanId);
      expect(c.snapshot.phase, MatchPhase.playing);
    });

    test('bust after 3 no-score rolls puts 2¢ in pot then next', () {
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
      final humanId = c.snapshot.currentPlayer.profile.id;
      c.roll(); // 1 — no score, turn continues
      expect(c.snapshot.turn!.rollsLeft, 2);
      expect(c.snapshot.turn!.mustKeepRolling, isTrue);
      expect(c.snapshot.phase, MatchPhase.playing);
      c.roll(); // 2 — still no score
      expect(c.snapshot.turn!.rollsLeft, 1);
      expect(c.snapshot.currentPlayer.profile.id, humanId);
      expect(c.snapshot.phase, MatchPhase.playing);
      c.roll(); // 3 — auto-bust applies, then hand off
      expect(c.snapshot.potCents, potBefore + 2);
      final human = c.snapshot.players.firstWhere((p) => p.profile.isHuman);
      expect(human.bankCents, humanBefore - 2);
      expect(c.snapshot.log.any((l) => l.contains('whiffs')), isTrue);
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      expect(c.snapshot.currentPlayer.profile.id, humanId);
      expect(c.snapshot.handoff!.outcomeText, 'Bust');
      c.confirmHandoff();
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.currentPlayer.profile.id, isNot(humanId));
      expect(c.snapshot.currentPlayer.profile.isBot, isTrue);
      expect(c.snapshot.turn!.hasRolled, isFalse);
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
      expect(human.bankCents, humanBefore + 24);
      // Win resets the same seat to a fresh 3 rolls. Does not hand off.
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.handoff, isNull);
      expect(c.snapshot.currentPlayer.profile.isHuman, isTrue);
      expect(c.snapshot.turn!.hasRolled, isFalse);
      expect(c.snapshot.turn!.rollNumber, 0);
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

    test('handoff gate: 3-miss bust holds next seat until confirm', () {
      final seq = <int>[];
      for (var r = 0; r < 3; r++) {
        seq.addAll([0, 0, 1]);
      }
      final c = MatchController(
        config: const MatchConfig(botCount: 3, otherHumanCount: 0),
        rng: ScriptedRandom(seq),
      );
      c.startMatch();
      c.roll();
      c.roll();
      c.roll();
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      expect(c.snapshot.handoff, isNotNull);
      expect(c.snapshot.handoff!.outcomeText, 'Bust');
      expect(c.snapshot.handoff!.bankDeltaCents, -2);
      expect(c.snapshot.handoff!.restartsRound, isFalse);
      expect(c.snapshot.currentSeatIndex, 0);
      expect(HandoffState.isHotseatCta(c.config), isFalse);
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

    test('bot keeps rolling on no-score until 3rd miss', () {
      // Human busts (turn ends), then bot whiffs three times (2,4,6 → 2,2,6 → 2,2,1).
      final seq = <int>[
        0, 0, 1, // human roll 1
        0, 0, 1, // human roll 2
        0, 0, 1, // human roll 3 bust
        1, 3, 5, // bot roll 1 → 2,4,6
        1, 1, // bot roll 2 → 2,2,6
        0, // bot roll 3 → 2,2,1
      ];
      final c = MatchController(
        config: const MatchConfig(botCount: 1, otherHumanCount: 0),
        rng: ScriptedRandom(seq),
      );
      c.startMatch();
      c.roll();
      c.roll();
      c.roll();
      c.confirmHandoff();
      expect(c.snapshot.currentPlayer.profile.isBot, isTrue);
      final botId = c.snapshot.currentPlayer.profile.id;
      final pot = c.snapshot.potCents;

      expect(c.tickBot(), isTrue); // first roll, no score
      expect(c.snapshot.currentPlayer.profile.id, botId);
      expect(c.snapshot.turn!.rollsLeft, 2);
      expect(c.snapshot.turn!.mustKeepRolling, isTrue);
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.handoff, isNull);
      expect(c.snapshot.potCents, pot);

      expect(c.tickBot(), isTrue); // second roll, still no score
      expect(c.snapshot.currentPlayer.profile.id, botId);
      expect(c.snapshot.turn!.rollsLeft, 1);
      expect(c.snapshot.phase, MatchPhase.playing);
      expect(c.snapshot.handoff, isNull);

      expect(c.tickBot(), isTrue); // third roll → bust, then handoff
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      expect(c.snapshot.handoff!.outcomeText, 'Bust');
      expect(c.snapshot.potCents, pot + 2);
      expect(c.snapshot.currentPlayer.profile.id, botId);
      c.confirmHandoff();
      expect(c.snapshot.currentPlayer.profile.isHuman, isTrue);
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
