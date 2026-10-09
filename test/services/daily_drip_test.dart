import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('daily drip', () {
    test('claims once per Denver day and refuses a second mint', () {
      final ledger = PlayerCoinLedger();
      final morning = DateTime.utc(2026, 9, 14, 18); // afternoon MDT
      expect(ledger.canClaimDailyDrip(utcNow: morning), isTrue);
      expect(ledger.claimDailyDrip('You', utcNow: morning), 25);
      expect(ledger.availableHumanGems('You'), 125);
      expect(ledger.canClaimDailyDrip(utcNow: morning), isFalse);
      expect(ledger.claimDailyDrip('You', utcNow: morning.add(const Duration(hours: 2))), isNull);
    });

    test('resets on the next Denver day', () async {
      SharedPreferences.setMockInitialValues({});
      final ledger = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 9, 14, 18),
      );
      expect(ledger.claimDailyDrip('You', utcNow: DateTime.utc(2026, 9, 14, 18)), 25);
      await ledger.flush();

      final nextDay = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 9, 15, 12),
      );
      // Cold load keeps the stamp from disk.
      expect(nextDay.lastDailyDripDay, '2026-09-14');
      expect(nextDay.canClaimDailyDrip(utcNow: DateTime.utc(2026, 9, 15, 12)), isTrue);
      expect(nextDay.claimDailyDrip('You', utcNow: DateTime.utc(2026, 9, 15, 12)), 25);
    });
  });
}
