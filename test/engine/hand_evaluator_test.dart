import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/dice.dart';
import 'package:marge/engine/hand_evaluator.dart';

void main() {
  group('HandEvaluator', () {
    test('triple ones on FIRST roll → pot win', () {
      final dice = DiceSet.fromValues([1, 1, 1]);
      final r = HandEvaluator.evaluate(dice, rollNumber: 1);
      expect(r.kind, ScoreKind.tripleOnesPotWin);
      expect(r.takesPot, isTrue);
      expect(r.perOpponentCents, 0);
    });

    test('triple ones on roll 2 → pay 10 each', () {
      final dice = DiceSet.fromValues([1, 1, 1]);
      final r = HandEvaluator.evaluate(dice, rollNumber: 2);
      expect(r.kind, ScoreKind.tripleOnesPay);
      expect(r.takesPot, isFalse);
      expect(r.perOpponentCents, 10);
    });

    test('triple ones on roll 3 → pay 10 each', () {
      final dice = DiceSet.fromValues([1, 1, 1]);
      final r = HandEvaluator.evaluate(dice, rollNumber: 3);
      expect(r.kind, ScoreKind.tripleOnesPay);
      expect(r.perOpponentCents, 10);
    });

    test('three of a kind pays face value', () {
      for (final face in [2, 3, 4, 5, 6]) {
        final dice = DiceSet.fromValues([face, face, face]);
        final r = HandEvaluator.evaluate(dice, rollNumber: 1);
        expect(r.kind, ScoreKind.threeOfAKind);
        expect(r.faceValue, face);
        expect(r.perOpponentCents, face);
      }
    });

    test('straights pay 5 each', () {
      final straights = [
        [1, 2, 3],
        [2, 3, 4],
        [3, 4, 5],
        [4, 5, 6],
        [3, 1, 2], // unordered
        [6, 4, 5],
      ];
      for (final s in straights) {
        final r = HandEvaluator.evaluate(
          DiceSet.fromValues(s),
          rollNumber: 2,
        );
        expect(r.kind, ScoreKind.straight, reason: '$s');
        expect(r.perOpponentCents, 5);
      }
    });

    test('non-scoring hands return none', () {
      final junk = [
        [1, 1, 2],
        [2, 2, 5],
        [1, 3, 5],
        [6, 6, 1],
        [1, 2, 4],
      ];
      for (final j in junk) {
        final r = HandEvaluator.evaluate(
          DiceSet.fromValues(j),
          rollNumber: 3,
        );
        expect(r.kind, ScoreKind.none, reason: '$j');
        expect(r.isScoring, isFalse);
      }
    });

    test('bust penalty constant is 2¢', () {
      expect(HandEvaluator.bustPenalty.potPenaltyCents, 2);
    });

    test('priority: trips beat straight-looking sets', () {
      // Three 2s is trips, not a straight.
      final r = HandEvaluator.evaluate(
        DiceSet.fromValues([2, 2, 2]),
        rollNumber: 1,
      );
      expect(r.kind, ScoreKind.threeOfAKind);
    });
  });
}
