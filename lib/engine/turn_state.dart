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

  bool get canRoll => rollNumber < 3 && hasRolled
      ? !dice.allKept
      : rollNumber < 3;

  bool get canBank => hasRolled && lastScore.isScoring;

  bool get mustFinish => rollNumber >= 3;

  bool get isFirstRollComplete => rollNumber == 1;

  TurnState copyWith({
    String? playerId,
    int? rollNumber,
    DiceSet? dice,
    bool? hasRolled,
    ScoreResult? lastScore,
  }) =>
      TurnState(
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
