import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/gem_iap.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GemPack SKUs', () {
    test('marge_gems_small/medium/large map to bank credits', () {
      expect(GemPack.small.productId, 'marge_gems_small');
      expect(GemPack.medium.productId, 'marge_gems_medium');
      expect(GemPack.large.productId, 'marge_gems_large');
      expect(GemPack.small.gems, 100);
      expect(GemPack.medium.gems, 500);
      expect(GemPack.large.gems, 1200);
      expect(GemPack.all.map((p) => p.gems), PlayerCoinLedger.iapPackGems);
      expect(GemPack.byId('marge_gems_medium')?.gems, 500);
      expect(GemPack.byId('nope'), isNull);
    });

    test('crediting a pack adds to the main gem bank only', () async {
      SharedPreferences.setMockInitialValues({});
      final ledger = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 9, 14, 18),
      );
      ledger.write('You', bot: false, cents: 40);
      await ledger.flush();

      for (final pack in GemPack.all) {
        final before = ledger.availableHumanGems('You');
        final next = ledger.grantHumanPlayCoins('You', cents: pack.gems);
        expect(next, before + pack.gems);
      }
      expect(ledger.savedCents('You', bot: false), 40 + 100 + 500 + 1200);
      expect(ledger.balances.keys.where((k) => k.startsWith('bot:')), isEmpty);
    });
  });
}
