import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/bot_ai.dart';
import 'package:marge/engine/dice.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/player.dart';
import 'package:marge/engine/turn_state.dart';

void main() {
  test('bot rolls when turn has not started', () {
    final ai = BotAI(Random(1));
    final d = ai.decide(TurnState.start('x'), BotPersonality.cautious);
    expect(d, isA<BotRoll>());
  });

  test('cautious bot banks a straight', () {
    final ai = BotAI(Random(1));
    final dice = DiceSet.fromValues([2, 3, 4]);
    final score = HandEvaluator.evaluate(dice, rollNumber: 1);
    final turn = TurnState(
      playerId: 'x',
      rollNumber: 1,
      dice: dice,
      hasRolled: true,
      lastScore: score,
    );
    final d = ai.decide(turn, BotPersonality.cautious);
    expect(d, isA<BotBank>());
  });

  test('bot banks three of a kind', () {
    final ai = BotAI(Random(1));
    final dice = DiceSet.fromValues([6, 6, 6]);
    final score = HandEvaluator.evaluate(dice, rollNumber: 1);
    final turn = TurnState(
      playerId: 'x',
      rollNumber: 1,
      dice: dice,
      hasRolled: true,
      lastScore: score,
    );
    final d = ai.decide(turn, BotPersonality.aggressive);
    expect(d, isA<BotBank>());
  });
}
