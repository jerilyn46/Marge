import 'dice.dart';

/// Scoring outcome for a finished (or bankable) hand.
enum ScoreKind {
  /// Three 1s on the first roll of the turn → claim entire pot.
  tripleOnesPotWin,

  /// Three 1s on roll 2 or 3 → each other pays 10 gems.
  tripleOnesPay,

  /// Three 2s–6s. First roll of the set: each other pays 2× the face.
  /// Later rolls: each other pays the face.
  threeOfAKind,

  /// Straight {1,2,3}|{2,3,4}|{3,4,5}|{4,5,6} → each other pays 5 gems.
  straight,

  /// No scoring hand.
  none,
}

class ScoreResult {
  const ScoreResult({
    required this.kind,
    this.faceValue,
    this.perOpponentCents = 0,
    this.takesPot = false,
    this.potPenaltyCents = 0,
    this.bankedOnly = false,
  });

  final ScoreKind kind;

  /// Face of the three-of-a-kind when applicable.
  final int? faceValue;

  /// How much each other player pays the scorer (0 for pot win / none).
  final int perOpponentCents;

  /// True when scorer takes the entire pot (triple-1 first roll).
  final bool takesPot;

  /// Amount the current player puts into the pot (bust after 3 rolls).
  final int potPenaltyCents;

  /// Pay only gems already at the table. No house stake. Humans who cannot
  /// cover the full amount get a choice instead of a silent partial pay.
  final bool bankedOnly;

  bool get isScoring => kind != ScoreKind.none;

  /// First-roll three 2s–6s: each other pays twice the face, or chooses.
  bool get isFirstRollTripsPay => kind == ScoreKind.threeOfAKind && bankedOnly;

  static const none = ScoreResult(kind: ScoreKind.none);

  @override
  String toString() =>
      'ScoreResult($kind face=$faceValue pay=$perOpponentCents pot=$takesPot pen=$potPenaltyCents bankedOnly=$bankedOnly)';
}

/// Pure scoring rules for Marge.
class HandEvaluator {
  HandEvaluator._();

  static const straightSets = <Set<int>>[
    {1, 2, 3},
    {2, 3, 4},
    {3, 4, 5},
    {4, 5, 6},
  ];

  /// Evaluate current dice given which roll number just completed (1–3).
  /// Does not apply the "bust put 2 gems" rule — that is applied by the
  /// match controller when the player finishes 3 rolls with no score.
  static ScoreResult evaluate(DiceSet dice, {required int rollNumber}) {
    assert(rollNumber >= 1 && rollNumber <= 3);
    final values = dice.values;
    final sorted = [...values]..sort();
    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }

    // Three of a kind?
    final tripleEntry = counts.entries.where((e) => e.value == 3).toList();
    if (tripleEntry.isNotEmpty) {
      final face = tripleEntry.first.key;
      if (face == 1) {
        if (rollNumber == 1) {
          // Pot only. Do not also charge 2 gems for triple 1s.
          return const ScoreResult(
            kind: ScoreKind.tripleOnesPotWin,
            faceValue: 1,
            takesPot: true,
          );
        }
        return const ScoreResult(
          kind: ScoreKind.tripleOnesPay,
          faceValue: 1,
          perOpponentCents: 10,
        );
      }
      final firstRoll = rollNumber == 1;
      return ScoreResult(
        kind: ScoreKind.threeOfAKind,
        faceValue: face,
        perOpponentCents: firstRoll ? face * 2 : face,
        bankedOnly: firstRoll,
      );
    }

    // Straight?
    final asSet = sorted.toSet();
    for (final s in straightSets) {
      if (asSet.length == 3 && asSet.containsAll(s)) {
        return const ScoreResult(kind: ScoreKind.straight, perOpponentCents: 5);
      }
    }

    return ScoreResult.none;
  }

  /// Result when player ends turn with no scoring hand after 3 rolls.
  static const bustPenalty = ScoreResult(
    kind: ScoreKind.none,
    potPenaltyCents: 2,
  );
}
