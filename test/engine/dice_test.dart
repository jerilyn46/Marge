import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/dice.dart';

void main() {
  test('roll keeps kept dice', () {
    final rng = Random(7);
    var set = DiceSet.fromValues([1, 2, 3], kept: [true, false, true]);
    set = set.roll(rng);
    expect(set.dice[0].value, 1);
    expect(set.dice[2].value, 3);
    expect(set.dice[1].value, inInclusiveRange(1, 6));
  });

  test('toggle keep', () {
    final set = DiceSet.fromValues([4, 5, 6]);
    final next = set.toggleKeep(1);
    expect(next.dice[1].kept, isTrue);
    expect(next.dice[0].kept, isFalse);
  });

  test('rollAll produces three faces', () {
    final set = DiceSet.rollAll(Random(1));
    expect(set.dice.length, 3);
    for (final d in set.dice) {
      expect(d.value, inInclusiveRange(1, 6));
      expect(d.kept, isFalse);
    }
  });
}
