import 'dice.dart';
import 'hand_evaluator.dart';

/// Mutable-ish snapshot of the active player's turn.
class TurnState {
  const TurnState({
    required this.playerId,
    required this.rollNumber,
    required this.dice,
    required this.hasRolled,
    this.lastScore = ScoreResult.none,
    this.setNumber = 1,
    this.carriedIntoFinal,
  });

  /// Faces of the dice carried (held) from roll 2 into roll 3, captured at
  /// the instant roll 3 was thrown: one entry per die, null where the die
  /// was re-rolled. Detection reads this snapshot, never the live
  /// [Die.kept] flags after the throw, so a reset or re-read of hold state
  /// around the throw animation can't change the outcome.
  final List<int?>? carriedIntoFinal;

  /// Which set of 3 rolls this is within the seat's turn: 1, then +1 each
  /// time a winning hand is banked and the same player keeps the seat.
  /// [rollNumber] counts within the set (resets to 0 after a bank).
  final int setNumber;

  /// Seat whose turn it is.
  final String playerId;

  /// 0 = not yet rolled; 1–3 after each roll.
  final int rollNumber;

  final DiceSet dice;
  final bool hasRolled;
  final ScoreResult lastScore;

  /// Rolls remaining in this turn (3 − rolls already taken).
  int get rollsLeft => (3 - rollNumber).clamp(0, 3);

  /// Another roll is allowed while rolls remain. Keeping all dice still
  /// permits rolling (faces stay; the roll is consumed) so the player is
  /// never soft-locked without a score.
  bool get canRoll => rollNumber < 3;

  bool get canBank => hasRolled && lastScore.isScoring;

  /// True after the 3rd roll — player must bank a score or take the bust.
  bool get mustFinish => rollNumber >= 3;

  /// Non-winning hand with rolls still available. The turn is not over:
  /// do not advance, bust, or offer bank.
  bool get mustKeepRolling =>
      hasRolled && !lastScore.isScoring && rollsLeft > 0;

  bool get isFirstRollComplete => rollNumber == 1;

  /// "Going for three 1s": the 3rd roll of a set was taken with exactly two
  /// dice held, both showing 1, and the third die re-rolled. (Held dice keep
  /// [Die.kept]; re-rolled dice come back unkept.) Only meaningful once the
  /// 3rd roll has happened.
  bool get wentForTripleOnes {
    if (rollNumber != 3) return false;
    if (dice.values.every((v) => v == 1)) return false; // that's a pot win
    final carried = carriedIntoFinal;
    final List<int> held = carried != null
        ? [for (final v in carried) ?v]
        : [
            for (final d in dice.dice)
              if (d.kept) d.value,
          ];
    return held.length == 2 && held.every((v) => v == 1);
  }

  TurnState copyWith({
    String? playerId,
    int? rollNumber,
    DiceSet? dice,
    bool? hasRolled,
    ScoreResult? lastScore,
    int? setNumber,
    List<int?>? carriedIntoFinal,
    bool clearCarried = false,
  }) => TurnState(
    playerId: playerId ?? this.playerId,
    rollNumber: rollNumber ?? this.rollNumber,
    dice: dice ?? this.dice,
    hasRolled: hasRolled ?? this.hasRolled,
    lastScore: lastScore ?? this.lastScore,
    setNumber: setNumber ?? this.setNumber,
    carriedIntoFinal: clearCarried
        ? null
        : (carriedIntoFinal ?? this.carriedIntoFinal),
  );

  factory TurnState.start(String playerId) => TurnState(
    playerId: playerId,
    rollNumber: 0,
    dice: DiceSet.blank(),
    hasRolled: false,
  );
}

/// Banner / log event shown in the UI after a payout.
class PayoutEvent {
  const PayoutEvent({
    required this.message,
    required this.kind,
    this.amountCents = 0,
    this.celebratory = false,
    this.diceValues,
    this.seatIndex,
    this.missedTripleOnes = false,
  });

  /// A bust after holding two 1s for the 3rd roll (10 gems to the pot).
  final bool missedTripleOnes;

  final String message;
  final ScoreKind kind;
  final int amountCents;
  final bool celebratory;

  /// Faces that produced this payout when the turn is reset right away
  /// (first-roll triple ones). Lets the table show the roll before the
  /// celebration even though the winner already has a fresh 3 rolls.
  final List<int>? diceValues;

  /// Seat that rolled [diceValues] (set together with it).
  final int? seatIndex;
}
