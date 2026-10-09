import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/table_gem_book.dart';

/// UAT #4: the soft-bankrupt House stake must not mint permanent bank gems.
void main() {
  test('house stake is created by the House, not the pot or other seats', () {
    final book = TableGemBook();
    book.seed('You', bot: false, gems: 5);
    book.seed('Spike', bot: true, gems: 100);
    final c = MatchController(
      config: const MatchConfig(
        botCount: 1,
        anteCents: 10,
        houseStakeCents: 50,
        localPlayerName: 'You',
      ),
      rng: Random(3),
      coins: book,
    );
    c.startMatch();
    final s = c.snapshot;
    final you = s.players.firstWhere((p) => p.profile.id == 'human_0');
    final bot = s.players.firstWhere((p) => p.profile.isBot);
    // You: 5 + 50 (House) − 10 ante = 45. Bot only paid its ante.
    expect(you.usedHouseStake, isTrue);
    expect(you.bankCents, 45);
    expect(bot.bankCents, 90);
    // Pot holds exactly the two antes — the stake did not come from it.
    expect(s.potCents, 20);
    // Table total grew by exactly the House stake (5 + 100 + 50 = 155).
    expect(you.bankCents + bot.bankCents + s.potCents, 155);
    expect(MatchController.houseStakeOwed(you, c.config), 50);
    expect(MatchController.houseStakeOwed(bot, c.config), 0);
  });

  test('cash-out repays the House stake before gems reach the bank', () {
    final ledger = PlayerCoinLedger(balances: {'human:You': 0});
    // Won up to 120 at the table after a 50 House stake → 70 comes home.
    SavedGameStore.returnLocalGems(
      ledger: ledger,
      localName: 'You',
      tableGems: 120,
      houseStakeOwed: 50,
    );
    expect(ledger.availableHumanGems('You'), 70);
  });

  test('a table below the stake returns nothing (no minted gems leak)', () {
    final ledger = PlayerCoinLedger(balances: {'human:You': 10});
    SavedGameStore.returnLocalGems(
      ledger: ledger,
      localName: 'You',
      tableGems: 45,
      houseStakeOwed: 50,
    );
    expect(ledger.availableHumanGems('You'), 10);
  });

  test('no stake used: all table gems return as before', () {
    final ledger = PlayerCoinLedger(balances: {'human:You': 10});
    SavedGameStore.returnLocalGems(
      ledger: ledger,
      localName: 'You',
      tableGems: 45,
    );
    expect(ledger.availableHumanGems('You'), 55);
  });
}
