import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/engine/player.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/denver_time.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/table_gem_book.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('saved unfinished games', () {
    test(
      'leave saves pot and seated gems; resume does not reset them',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = await SavedGameStore.load();
        final book = TableGemBook();
        book.seed('You', bot: false, gems: 80);
        book.seed('Spike', bot: true, gems: 55);
        final first = MatchController(
          config: const MatchConfig(botCount: 1, localPlayerName: 'You'),
          rng: Random(1),
          coins: book,
        );
        first.startMatch();
        // Ante already taken from the seeded table banks. Pot is not empty.
        expect(first.snapshot.potCents, 20);
        expect(first.snapshot.players[0].bankCents, 70);
        expect(first.snapshot.players[1].bankCents, 45);

        final saved = SavedGame(
          id: 'sg-one',
          savedAt: DateTime.utc(2026, 9, 8, 18),
          table: first.capture(),
        );
        store.upsert(saved);
        await store.flush();

        final cold = await SavedGameStore.load();
        final loaded = cold.byId('sg-one');
        expect(loaded, isNotNull);
        expect(loaded!.table.potCents, 20);
        expect(loaded.table.localBankCents, 70);
        expect(loaded.table.players[1].bankCents, 45);
        expect(loaded.table.currentSeatIndex, first.snapshot.currentSeatIndex);

        final restoredBook = TableGemBook();
        for (final p in loaded.table.players) {
          if (!p.profile.participates) continue;
          restoredBook.seed(
            p.profile.name,
            bot: p.profile.isBot,
            gems: p.bankCents,
          );
        }
        final resumed = MatchController(
          config: loaded.table.config,
          rng: Random(2),
          coins: restoredBook,
        );
        resumed.restore(loaded.table);
        expect(resumed.snapshot.potCents, 20);
        expect(resumed.snapshot.players[0].bankCents, 70);
        expect(resumed.snapshot.players[1].bankCents, 45);
        expect(resumed.snapshot.players[0].bankCents, isNot(100));
        expect(resumed.snapshot.phase, isNot(MatchPhase.matchEnd));
      },
    );

    test('a second unfinished game does not wipe the first', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await SavedGameStore.load();

      MatchController table({
        required String id,
        required int you,
        required int spike,
      }) {
        final book = TableGemBook();
        book.seed('You', bot: false, gems: you);
        book.seed('Spike', bot: true, gems: spike);
        final c = MatchController(
          config: const MatchConfig(botCount: 1, localPlayerName: 'You'),
          rng: Random(3),
          coins: book,
        );
        c.startMatch();
        store.upsert(
          SavedGame(
            id: id,
            savedAt: DateTime.utc(2026, 9, 8, 18),
            table: c.capture(),
          ),
        );
        return c;
      }

      final first = table(id: 'one', you: 80, spike: 40);
      final firstPot = first.snapshot.potCents;
      final firstYou = first.snapshot.players[0].bankCents;

      final second = table(id: 'two', you: 30, spike: 90);
      // Playing the second table must not rewrite the first snapshot.
      expect(store.byId('one')!.table.potCents, firstPot);
      expect(store.byId('one')!.table.localBankCents, firstYou);
      expect(store.byId('two')!.table.potCents, second.snapshot.potCents);
      expect(
        store.byId('two')!.table.localBankCents,
        second.snapshot.players[0].bankCents,
      );
      expect(store.games.length, 2);

      store.remove('two');
      expect(store.byId('one'), isNotNull);
      expect(store.byId('two'), isNull);
    });

    test('completed games are dropped from the resume list', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await SavedGameStore.load();
      final book = TableGemBook();
      book.seed('You', bot: false, gems: 40);
      book.seed('Spike', bot: true, gems: 40);
      final c = MatchController(
        config: const MatchConfig(botCount: 1),
        rng: Random(1),
        coins: book,
      );
      c.startMatch();
      c.endMatch();
      store.upsert(
        SavedGame(
          id: 'done',
          savedAt: DateTime.utc(2026, 9, 8),
          table: c.capture(),
        ),
      );
      expect(store.byId('done'), isNull);
    });
  });

  group('gem bank', () {
    test(
      'denominations add to the gem bank and move cannot exceed available',
      () {
        final ledger = PlayerCoinLedger();
        expect(PlayerCoinLedger.playGemDenominations, [10, 25, 50, 100]);
        expect(ledger.grantHumanPlayCoins('You', cents: 25), 125);
        expect(ledger.availableHumanGems('You'), 125);
        expect(ledger.drawAvailable('You', 126), isNull);
        expect(ledger.availableHumanGems('You'), 125);
        expect(ledger.drawAvailable('You', 25), 100);
        expect(ledger.savedCents('You', bot: false), 100);
      },
    );

    test('saved table bots ignore a Monday reset until that game ends', () {
      final ledger = PlayerCoinLedger(
        balances: {'bot:Spike': 12},
        lastBotResetAt: DateTime.utc(2026, 8, 31),
      );
      final book = TableGemBook();
      book.seed('You', bot: false, gems: 50);
      book.seed('Spike', bot: true, gems: 12);
      final c = MatchController(
        config: const MatchConfig(botCount: 1),
        rng: Random(1),
        coins: book,
      );
      c.startMatch();
      final savedSpike = c.snapshot.players
          .firstWhere((p) => p.profile.isBot)
          .bankCents;
      ledger.applyWeeklyBotReset(DateTime.utc(2026, 9, 8, 18));
      expect(ledger.savedCents('Spike', bot: true), 100);
      expect(
        c.snapshot.players.firstWhere((p) => p.profile.isBot).bankCents,
        savedSpike,
      );
      expect(savedSpike, isNot(100));
    });
  });

  test('Denver week helper stays available for bot reset docs', () {
    expect(DenverTime.weekStartUtc(DateTime.utc(2026, 9, 8, 18)), isNotNull);
  });
}
