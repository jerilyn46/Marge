import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/gem_iap.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Weekend bag', () {
    test('product id and gems are exact', () {
      expect(GemPack.weekend.productId, 'marge_gems_weekend');
      expect(GemPack.weekend.gems, 650);
      expect(GemPack.byId('marge_gems_weekend'), GemPack.weekend);
      expect(GemPack.productIds, contains('marge_gems_weekend'));
    });

    // Oct 2026 (MDT, UTC-6): Mon 26 .. Sun Nov 1.
    test('offered Friday–Sunday Denver', () {
      // Fri Oct 30 00:00 MDT = 06:00Z
      final fri = DateTime.utc(2026, 10, 30, 6);
      final sat = DateTime.utc(2026, 10, 31, 18);
      // Sun Nov 1 23:30 MST (after fall-back) = Nov 2 06:30Z
      final sunLate = DateTime.utc(2026, 11, 2, 6, 30);
      for (final t in [fri, sat, sunLate]) {
        expect(GemPack.isWeekendDenver(t), isTrue, reason: '$t');
        expect(GemPack.offeredAt(t), contains(GemPack.weekend));
      }
    });

    test('not offered Monday–Thursday Denver', () {
      final times = [
        DateTime.utc(2026, 10, 26, 18), // Mon
        DateTime.utc(2026, 10, 27, 18), // Tue
        DateTime.utc(2026, 10, 28, 18), // Wed
        DateTime.utc(2026, 10, 30, 5, 59), // Thu 23:59 MDT
        DateTime.utc(2026, 11, 2, 7), // Mon 00:00 MST
      ];
      for (final t in times) {
        expect(GemPack.isWeekendDenver(t), isFalse, reason: '$t');
        final offered = GemPack.offeredAt(t);
        expect(offered, isNot(contains(GemPack.weekend)));
        expect(
          offered,
          containsAll([GemPack.small, GemPack.medium, GemPack.large]),
        );
      }
    });

    test('purchase grants 650 to main gem bank once', () async {
      SharedPreferences.setMockInitialValues({});
      final ledger = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 10, 30, 18),
      );
      ledger.write('You', bot: false, cents: 40);
      final pack = GemPack.byId('marge_gems_weekend')!;
      final next = ledger.grantHumanPlayCoins('You', cents: pack.gems);
      expect(next, 40 + 650);
      expect(ledger.savedCents('You', bot: false), 690);
    });
  });
}
