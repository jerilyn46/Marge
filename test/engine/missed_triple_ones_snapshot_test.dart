import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/dice.dart';
import 'package:marge/engine/turn_state.dart';

TurnState _t(List<int> v, List<bool> kept, {List<int?>? carried}) => TurnState(
  playerId: 'h',
  rollNumber: 3,
  dice: DiceSet.fromValues(v, kept: kept),
  hasRolled: true,
  carriedIntoFinal: carried,
);

void main() {
  test('1-5-1, 1s carried at 0 and 2, live holds cleared after throw', () {
    expect(
      _t(
        [1, 5, 1],
        [false, false, false],
        carried: [1, null, 1],
      ).wentForTripleOnes,
      isTrue,
    );
  });
  test('carried snapshot wins over stale live flags', () {
    expect(
      _t(
        [1, 5, 1],
        [true, false, true],
        carried: [1, null, null],
      ).wentForTripleOnes,
      isFalse,
    );
  });
  test('any two positions count', () {
    for (final c in [
      [1, 1, null],
      [null, 1, 1],
      [1, null, 1],
    ]) {
      final v = [for (final x in c) x ?? 4];
      expect(
        _t(v, [false, false, false], carried: c).wentForTripleOnes,
        isTrue,
      );
    }
  });
  test('1-1-1 on roll 3 is not a miss', () {
    expect(
      _t(
        [1, 1, 1],
        [true, false, true],
        carried: [1, null, 1],
      ).wentForTripleOnes,
      isFalse,
    );
  });
  test('no snapshot (old checkpoint) falls back to live holds', () {
    expect(_t([1, 5, 1], [true, false, true]).wentForTripleOnes, isTrue);
  });
}
