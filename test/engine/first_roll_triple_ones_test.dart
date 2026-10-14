import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';

/// Dice: nextInt(6) + 1. Feed a fixed stream; [next] swaps it mid-test.
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

const ones = [0, 0, 0];
const miss = [2, 2, 0]; // 3,3,1

String msg(String n) =>
    '$n rolled three 1s on the first roll! '
    'Everyone pays 10 gems and $n wins the pot.';

/// Local player busts three misses; then the bot (seat 1) is up.
void _bustToBot(MatchController c, _Dice d) {
  d.next(miss);
  c.roll();
  c.roll();
  c.roll();
  expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
  d.next(ones);
  c.confirmHandoff();
  expect(c.snapshot.currentPlayer.profile.isBot, isTrue);
}

void main() {
  test('2 players vs bot: bot pays 10, roller takes pot, match over', () {
    final d = _Dice(ones);
    final c = MatchController(config: const MatchConfig(botCount: 1), rng: d)
      ..startMatch();
    expect(c.snapshot.potCents, 20);
    c.roll();
    final s = c.snapshot;
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.players[0].bankCents, 90 + 10 + 20);
    expect(s.players[1].bankCents, 80);
    expect(s.potCents, 0);
    expect(s.winnerId, s.players[0].profile.id);
    expect(s.endMessage, msg('You'));
    expect(s.lastPayout!.message, msg('You'));
  });

  test('3-player hotseat: both others pay 10', () {
    final d = _Dice(ones);
    final c = MatchController(
      config: const MatchConfig(botCount: 0, otherHumanCount: 2),
      rng: d,
    )..startMatch();
    expect(c.snapshot.potCents, 30);
    c.roll();
    final s = c.snapshot;
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.players.map((p) => p.bankCents).toList(), [90 + 20 + 30, 80, 80]);
    expect(s.endMessage, msg('You'));
  });

  test('bot rolls it: message names the bot, human pays', () {
    final d = _Dice(miss);
    final c = MatchController(config: const MatchConfig(botCount: 1), rng: d)
      ..startMatch();
    _bustToBot(c, d);
    c.tickBot();
    final s = c.snapshot;
    expect(s.phase, MatchPhase.matchEnd);
    final bot = s.players[1];
    expect(s.endMessage, msg(bot.profile.name));
    expect(s.players[0].bankCents, 88 - 10);
    expect(bot.bankCents, 90 + 10 + 22);
  });

  test('shortfall: human adds gems and pays in full', () {
    final d = _Dice(miss);
    final c = MatchController(
      config: const MatchConfig(botCount: 1, startBankCents: 15),
      rng: d,
    )..startMatch();
    _bustToBot(c, d); // You: 5 - 2 = 3
    c.tickBot();
    var s = c.snapshot;
    expect(s.phase, MatchPhase.awaitingShortfall);
    expect(s.pendingShortfall!.dueGems, 10);
    expect(s.pendingShortfall!.face, 1);
    expect(c.coverShortfall(), isFalse); // still short: nothing taken
    expect(c.snapshot.players[0].bankCents, 3);
    c.grantLocalPlayCoins(20);
    expect(c.coverShortfall(), isTrue);
    s = c.snapshot;
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.players[0].bankCents, 23 - 10);
    expect(s.players[1].bankCents, 5 + 10 + 22);
    expect(s.players[0].eliminated, isFalse);
    expect(s.endMessage, msg(s.players[1].profile.name));
  });

  test('shortfall: human pays what they can and leaves', () {
    final d = _Dice(miss);
    final c = MatchController(
      config: const MatchConfig(botCount: 1, startBankCents: 15),
      rng: d,
    )..startMatch();
    _bustToBot(c, d);
    c.tickBot();
    c.quitShortfall();
    final s = c.snapshot;
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.players[0].bankCents, 0);
    expect(s.players[0].eliminated, isTrue);
    expect(s.players[1].bankCents, 5 + 3 + 22);
    expect(s.winnerId, s.players[1].profile.id);
  });

  test('bot shortfall: bot pays what it has; no shortfall prompt', () {
    final d = _Dice(ones);
    final c = MatchController(
      config: const MatchConfig(botCount: 1, startBankCents: 15),
      rng: d,
    )..startMatch();
    c.roll();
    final s = c.snapshot;
    expect(s.pendingShortfall, isNull);
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.players[1].bankCents, 0);
    expect(s.players[0].bankCents, 5 + 5 + 20);
  });

  test('House stake owed stays correct and is never re-used', () {
    final d = _Dice(miss);
    final c = MatchController(
      config: const MatchConfig(
        botCount: 1,
        startBankCents: 11,
        houseStakeCents: 50,
      ),
      rng: d,
    )..startMatch();
    _bustToBot(c, d); // 1 gem, bust 2 -> House stake +50 -> 49
    final you = c.snapshot.players[0];
    expect(you.usedHouseStake, isTrue);
    expect(you.bankCents, 49);
    c.tickBot();
    final s = c.snapshot;
    expect(s.phase, MatchPhase.matchEnd);
    expect(s.players[0].bankCents, 39); // paid 10 from table gems
    expect(MatchController.houseStakeOwed(s.players[0], c.config), 50);
    expect(s.pendingShortfall, isNull);
  });

  test('triple 1s on roll 2 is unchanged (triple-ones pay, keep seat)', () {
    final d = _Dice(miss);
    final c = MatchController(config: const MatchConfig(botCount: 1), rng: d)
      ..startMatch();
    c.roll();
    d.next(ones);
    c.roll();
    var s = c.snapshot;
    expect(s.turn!.lastScore.kind, ScoreKind.tripleOnesPay);
    expect(s.phase, MatchPhase.playing);
    c.bank();
    s = c.snapshot;
    expect(s.phase, MatchPhase.playing);
    expect(s.currentSeatIndex, 0);
    expect(s.potCents, 20);
    expect(s.endMessage, isNull);
  });

  test('triple 1s on roll 3 is unchanged', () {
    final d = _Dice(miss);
    final c = MatchController(config: const MatchConfig(botCount: 1), rng: d)
      ..startMatch();
    c.roll();
    c.roll();
    d.next(ones);
    c.roll();
    var s = c.snapshot;
    expect(s.turn!.lastScore.kind, ScoreKind.tripleOnesPay);
    c.bank();
    s = c.snapshot;
    expect(s.phase, MatchPhase.playing);
    expect(s.potCents, 20);
    expect(s.endMessage, isNull);
  });
}
