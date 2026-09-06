import 'dart:math';

/// A single die face 1–6.
class Die {
  const Die(this.value, {this.kept = false})
      : assert(value >= 1 && value <= 6);

  final int value;
  final bool kept;

  Die copyWith({int? value, bool? kept}) =>
      Die(value ?? this.value, kept: kept ?? this.kept);

  Die toggleKeep() => Die(value, kept: !kept);

  @override
  bool operator ==(Object other) =>
      other is Die && other.value == value && other.kept == kept;

  @override
  int get hashCode => Object.hash(value, kept);

  @override
  String toString() => 'Die($value${kept ? '*' : ''})';
}

/// Three dice used in a turn.
class DiceSet {
  DiceSet(List<Die> dice)
      : assert(dice.length == 3),
        dice = List.unmodifiable(dice);

  factory DiceSet.blank() =>
      DiceSet(const [Die(1), Die(1), Die(1)]);

  factory DiceSet.fromValues(List<int> values, {List<bool>? kept}) {
    assert(values.length == 3);
    return DiceSet([
      for (var i = 0; i < 3; i++)
        Die(values[i], kept: kept?[i] ?? false),
    ]);
  }

  final List<Die> dice;

  List<int> get values => dice.map((d) => d.value).toList();

  List<bool> get keptFlags => dice.map((d) => d.kept).toList();

  bool get allKept => dice.every((d) => d.kept);

  DiceSet toggleKeep(int index) {
    assert(index >= 0 && index < 3);
    final next = [...dice];
    next[index] = next[index].toggleKeep();
    return DiceSet(next);
  }

  DiceSet setKept(int index, bool kept) {
    final next = [...dice];
    next[index] = next[index].copyWith(kept: kept);
    return DiceSet(next);
  }

  DiceSet keepAll() =>
      DiceSet(dice.map((d) => d.copyWith(kept: true)).toList());

  DiceSet clearKept() =>
      DiceSet(dice.map((d) => d.copyWith(kept: false)).toList());

  /// Roll non-kept dice; kept dice stay.
  DiceSet roll(Random rng) {
    return DiceSet([
      for (final d in dice)
        d.kept ? d : Die(rng.nextInt(6) + 1, kept: false),
    ]);
  }

  /// Fresh roll of all three (first roll of a turn).
  factory DiceSet.rollAll(Random rng) => DiceSet([
        Die(rng.nextInt(6) + 1),
        Die(rng.nextInt(6) + 1),
        Die(rng.nextInt(6) + 1),
      ]);

  @override
  String toString() => 'DiceSet(${dice.join(', ')})';
}
