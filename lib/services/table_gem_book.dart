import '../engine/seat_coin_book.dart';
import 'coin_ledger.dart';

/// Seat totals for one table. Writes never touch the shared gem bank
/// or any other unfinished game.
class TableGemBook implements SeatCoinBook {
  final Map<String, int> banks = {};

  void seed(String name, {required bool bot, required int gems}) {
    banks[PlayerCoinLedger.storageKey(name, bot: bot)] = gems;
  }

  int? seeded(String name, {required bool bot}) =>
      banks[PlayerCoinLedger.storageKey(name, bot: bot)];

  @override
  int openingCents(String name, {required bool bot, required int fallback}) {
    return seeded(name, bot: bot) ?? fallback;
  }

  @override
  void write(String name, {required bool bot, required int cents}) {
    banks[PlayerCoinLedger.storageKey(name, bot: bot)] = cents;
  }
}
