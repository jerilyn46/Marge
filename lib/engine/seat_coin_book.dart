/// Opening balances and immediate writes for seated players.
///
/// Waiting chairs are not written. The engine stays persistence-free;
/// [write] is how a ledger (shared_preferences) hears every ante, payout,
/// bust, and pot credit as it happens.
abstract class SeatCoinBook {
  int openingCents(String name, {required bool bot, required int fallback});

  void write(String name, {required bool bot, required int cents});
}
