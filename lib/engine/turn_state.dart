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
  });

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

  TurnState copyWith({
    String? playerId,
    int? rollNumber,
    DiceSet? dice,
    bool? hasRolled,
    ScoreResult? lastScore,
  }) => TurnState(
    playerId: playerId ?? this.playerId,
    rollNumber: rollNumber ?? this.rollNumber,
    dice: dice ?? this.dice,
    hasRolled: hasRolled ?? this.hasRolled,
    lastScore: lastScore ?? this.lastScore,
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
  });

  final String message;
  final ScoreKind kind;
  final int amountCents;
  final bool celebratory;
}
