import 'dart:math';

import 'dice.dart';
import 'hand_evaluator.dart';
import 'player.dart';
import 'turn_state.dart';

/// Decision returned by a bot for the current turn step.
sealed class BotDecision {
  const BotDecision();
}

class BotRoll extends BotDecision {
  const BotRoll({this.keepIndices = const []});

  /// Indices to keep before rolling (ignored on first roll).
  final List<int> keepIndices;
}

class BotBank extends BotDecision {
  const BotBank();
}

/// Personality-driven keep / bank heuristics for Marge bots.
class BotAI {
  BotAI(this.rng);

  final Random rng;

  BotDecision decide(TurnState turn, BotPersonality personality) {
    if (!turn.hasRolled) {
      return const BotRoll();
    }

    final score = turn.lastScore;
    if (score.isScoring) {
      return _decideBankOrContinue(turn, personality, score);
    }

    if (turn.rollNumber >= 3) {
      // Nothing to do — match controller will bust.
      return const BotBank();
    }

    return BotRoll(keepIndices: _chooseKeeps(turn.dice, personality));
  }

  BotDecision _decideBankOrContinue(
    TurnState turn,
    BotPersonality personality,
    ScoreResult score,
  ) {
    // Always bank pot win / strong trips immediately.
    if (score.kind == ScoreKind.tripleOnesPotWin) {
      return const BotBank();
    }
    if (score.kind == ScoreKind.tripleOnesPay ||
        score.kind == ScoreKind.threeOfAKind) {
      // Aggressive may re-roll for ones on early rolls if face is low.
      if (personality == BotPersonality.aggressive &&
          turn.rollNumber == 1 &&
          (score.faceValue ?? 0) <= 2 &&
          score.kind != ScoreKind.tripleOnesPay) {
        // Rarely gamble away a weak trip — usually bank.
        if (rng.nextDouble() < 0.15) {
          return const BotRoll();
        }
      }
      return const BotBank();
    }

    // Straight: cautious always banks; chaotic sometimes re-rolls for trips.
    if (score.kind == ScoreKind.straight) {
      switch (personality) {
        case BotPersonality.cautious:
          return const BotBank();
        case BotPersonality.aggressive:
          if (turn.rollNumber < 3 && rng.nextDouble() < 0.25) {
            return BotRoll(keepIndices: _keepStraightCore(turn.dice));
          }
          return const BotBank();
        case BotPersonality.chaotic:
          if (turn.rollNumber < 3 && rng.nextDouble() < 0.45) {
            return const BotRoll();
          }
          return const BotBank();
      }
    }

    return const BotBank();
  }

  List<int> _chooseKeeps(DiceSet dice, BotPersonality personality) {
    final values = dice.values;
    final counts = <int, List<int>>{};
    for (var i = 0; i < 3; i++) {
      counts.putIfAbsent(values[i], () => []).add(i);
    }

    // Prefer keeping a pair (especially ones).
    MapEntry<int, List<int>>? bestPair;
    for (final e in counts.entries) {
      if (e.value.length >= 2) {
        if (bestPair == null ||
            e.key == 1 ||
            (bestPair.key != 1 && e.key > bestPair.key)) {
          bestPair = e;
        }
      }
    }
    if (bestPair != null) {
      if (personality == BotPersonality.chaotic && rng.nextDouble() < 0.2) {
        // Chaotic sometimes ignores the pair.
        return _chaoticKeeps(values);
      }
      return List<int>.from(bestPair.value.take(2));
    }

    // Keep a single 1 if present.
    final ones = counts[1];
    if (ones != null && ones.isNotEmpty) {
      if (personality == BotPersonality.cautious || rng.nextDouble() < 0.7) {
        return [ones.first];
      }
    }

    // Near-straight: keep two consecutive.
    final sortedIdx = [0, 1, 2]..sort((a, b) => values[a].compareTo(values[b]));
    final a = values[sortedIdx[0]];
    final b = values[sortedIdx[1]];
    final c = values[sortedIdx[2]];
    if (b == a + 1) return [sortedIdx[0], sortedIdx[1]];
    if (c == b + 1) return [sortedIdx[1], sortedIdx[2]];

    if (personality == BotPersonality.aggressive) {
      // Keep highest die.
      var maxI = 0;
      for (var i = 1; i < 3; i++) {
        if (values[i] > values[maxI]) maxI = i;
      }
      return [maxI];
    }

    if (personality == BotPersonality.chaotic) {
      return _chaoticKeeps(values);
    }

    // Cautious with nothing: keep nothing, full re-roll.
    return const [];
  }

  List<int> _keepStraightCore(DiceSet dice) {
    // Keep all for a straight re-roll gamble is silly; keep middle pair-ish.
    return [0, 1];
  }

  List<int> _chaoticKeeps(List<int> values) {
    final n = rng.nextInt(4); // 0–3 keeps
    final idxs = [0, 1, 2]..shuffle(rng);
    return idxs.take(n.clamp(0, 3)).toList();
  }
}
