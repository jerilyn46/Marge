import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/engine/player.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('play coin pack', () {
    test('adds 100¢ play coins to human:You and reloads them', () async {
      SharedPreferences.setMockInitialValues({});
      final ledger = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 9, 8, 18),
      );
      ledger.write('You', bot: false, cents: 0);
      await ledger.flush();

      final next = ledger.grantHumanPlayCoins('You');
      expect(next, 100);
      expect(ledger.savedCents('You', bot: false), 100);
      expect(ledger.balances.containsKey('human:You'), isTrue);
      expect(ledger.balances.containsKey('bot:You'), isFalse);
      await ledger.flush();

      final cold = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 9, 8, 19),
      );
      expect(cold.savedCents('You', bot: false), 100);
      expect(cold.openingCents('You', bot: false, fallback: 100), 100);
    });

    test('adds the pack on top of an unsaved starting stake', () {
      final ledger = PlayerCoinLedger();
      expect(ledger.grantHumanPlayCoins('  You  '), 200);
      expect(ledger.savedCents('You', bot: false), 200);
    });

    test('does not credit bots or waiting friends', () {
      final ledger = PlayerCoinLedger();
      ledger.write('Spike', bot: true, cents: 40);
      expect(ledger.grantHumanPlayCoins(WaitingSeat.name), isNull);
      expect(ledger.balances.containsKey('human:${WaitingSeat.name}'), isFalse);
      expect(ledger.savedCents('Spike', bot: true), 40);
      expect(ledger.balances.containsKey('human:Spike'), isFalse);

      final seats = PlayerCoinLedger.lobbySeats(
        localName: 'You',
        otherHumans: 0,
        online: 1,
        bots: 1,
        friendNames: const ['Sam'],
        ledger: ledger,
      );
      expect(seats.first.coins, 100);
      expect(seats.firstWhere((s) => s.name == 'Sam').coins, isNull);
      expect(seats.firstWhere((s) => s.name == WaitingSeat.name).coins, isNull);
      expect(seats.firstWhere((s) => s.bot).coins, 40);
    });

    test('table grant credits only the local human and unsticks zero', () {
      final ledger = PlayerCoinLedger();
      ledger.write('You', bot: false, cents: 0);
      final c = MatchController(
        config: const MatchConfig(
          botCount: 1,
          otherHumanCount: 0,
          friendNames: ['Sam'],
          houseStakeCents: 0,
          localPlayerName: 'You',
        ),
        coins: ledger,
      );
      c.startMatch();
      final you = c.snapshot.players.firstWhere(
        (p) => p.profile.id == 'human_0',
      );
      expect(you.bankCents, 0);
      expect(you.eliminated, isTrue);
      expect(you.usedHouseStake, isTrue);

      final sam = c.snapshot.players.firstWhere((p) => p.profile.name == 'Sam');
      expect(sam.profile.isWaiting, isTrue);
      expect(sam.bankCents, 0);

      final next = c.grantLocalPlayCoins(PlayerCoinLedger.playCoinPackCents);
      expect(next, 100);
      final after = c.snapshot.players.firstWhere(
        (p) => p.profile.id == 'human_0',
      );
      expect(after.bankCents, 100);
      expect(after.eliminated, isFalse);
      expect(after.usedHouseStake, isTrue);
      expect(ledger.savedCents('You', bot: false), 100);
      expect(
        c.snapshot.players.firstWhere((p) => p.profile.isBot).bankCents,
        90,
      );
      expect(ledger.savedCents('Spike', bot: true), 90);
      expect(ledger.savedCents('Sam', bot: false), isNull);
      expect(
        c.snapshot.players.firstWhere((p) => p.profile.name == 'Sam').bankCents,
        0,
      );
      expect(c.snapshot.currentPlayer.profile.isBot, isTrue);
    });
  });
}
