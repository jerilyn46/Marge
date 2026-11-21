import 'match_controller.dart';
import 'hand_evaluator.dart';
import 'turn_state.dart';

export 'turn_state.dart' show PotWinReason;

/// One "someone took the pot" moment, offline or online: what the pot-win
/// card shows. Every pot award in Marge ends the match (offline engine and
/// the server alike), so this is only ever built from a finished match.
class PotWin {
  const PotWin({
    required this.winnerSeat,
    required this.winnerName,
    required this.mine,
    required this.gems,
    required this.reason,
    required this.reasonLine,
    this.bankAfter,
    this.includesTableGems = false,
  });

  final int winnerSeat;
  final String winnerName;

  /// The winner is the player holding this phone.
  final bool mine;

  /// Gems that went to the winner in this moment (the count-up).
  final int gems;

  final PotWinReason reason;

  /// Short why-line, e.g. "Box Tester left the table".
  final String reasonLine;

  /// Winner's table bank after the pot landed (null when unknown).
  final int? bankAfter;

  /// [gems] also counts gems everyone paid in the same roll (first-roll
  /// triple 1s: "pot + 10 from each player").
  final bool includesTableGems;

  String get headline =>
      mine ? 'You win the pot!' : '$winnerName wins the pot!';

  /// Small caps tag on the card.
  String get tag => switch (reason) {
    PotWinReason.tripleOnes => 'TRIPLE 1s',
    PotWinReason.opponentOut => 'LAST ONE STANDING',
    PotWinReason.opponentLeft => 'OPPONENT LEFT',
    PotWinReason.opponentQuit => 'OPPONENT QUIT',
    PotWinReason.hostEnded => 'MATCH ENDED',
  };

  String get caption =>
      includesTableGems ? 'the pot + 10 from each player' : 'from the pot';

  /// Offline: the pot-win moment for a finished local match, or null when
  /// the match ended without anyone taking the pot (e.g. End match).
  static PotWin? fromSnapshot(MatchSnapshot s) {
    if (s.phase != MatchPhase.matchEnd) return null;
    final p = s.lastPayout;
    if (p == null ||
        p.kind != ScoreKind.tripleOnesPotWin ||
        p.potWinReason == null) {
      return null;
    }
    var seat = p.seatIndex ?? -1;
    if (seat < 0 || seat >= s.players.length) {
      seat = s.players.indexWhere((x) => x.profile.id == s.winnerId);
    }
    if (seat < 0) return null;
    final winner = s.players[seat];
    final triple = p.potWinReason == PotWinReason.tripleOnes;
    return PotWin(
      winnerSeat: seat,
      winnerName: winner.profile.name,
      mine: winner.profile.id == 'human_0',
      // First-roll 1s: the whole take (pot + 10s). Otherwise the pot only.
      gems: triple ? p.amountCents : (p.potCents ?? p.amountCents),
      reason: p.potWinReason!,
      reasonLine: p.potWinNote ?? p.message,
      bankAfter: winner.bankCents,
      includesTableGems: triple && p.amountCents > (p.potCents ?? 0),
    );
  }
}
