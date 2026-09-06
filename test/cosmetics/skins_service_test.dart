import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/cosmetics/dice_skin.dart';
import 'package:marge/cosmetics/skins_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiceSkinCatalog', () {
    test('has at least 6 skins including Classic free', () {
      expect(DiceSkinCatalog.all.length, greaterThanOrEqualTo(6));
      final classic = DiceSkinCatalog.byId(DiceSkinId.classic);
      expect(classic.isFree, isTrue);
      expect(classic.priceCents, 0);
      final prices = DiceSkinCatalog.all
          .where((s) => !s.isFree)
          .map((s) => s.priceCents);
      for (final p in prices) {
        expect(p, inInclusiveRange(50, 150));
      }
    });
  });

  group('CosmeticsLogic buy/equip/unlock', () {
    test('starts with Classic owned and 200¢ wallet', () {
      const s = CosmeticsState();
      expect(s.walletCents, 200);
      expect(s.isOwned(DiceSkinId.classic), isTrue);
      expect(s.equipped, DiceSkinId.classic);
    });

    test('buy Midnight deducts wallet and owns skin', () {
      const s = CosmeticsState();
      final (next, result) = CosmeticsLogic.buy(s, DiceSkinId.midnight);
      expect(result.ok, isTrue);
      expect(next.isOwned(DiceSkinId.midnight), isTrue);
      expect(next.walletCents, 200 - 50);
    });

    test('buy fails when broke', () {
      const s = CosmeticsState(walletCents: 10);
      final (next, result) = CosmeticsLogic.buy(s, DiceSkinId.candy);
      expect(result.ok, isFalse);
      expect(next.walletCents, 10);
      expect(next.isOwned(DiceSkinId.candy), isFalse);
    });

    test('cannot equip unowned', () {
      const s = CosmeticsState();
      final (next, result) = CosmeticsLogic.equip(s, DiceSkinId.neon);
      expect(result.ok, isFalse);
      expect(next.equipped, DiceSkinId.classic);
    });

    test('equip owned skin', () {
      const s = CosmeticsState(
        owned: {DiceSkinId.classic, DiceSkinId.candy},
      );
      final (next, result) = CosmeticsLogic.equip(s, DiceSkinId.candy);
      expect(result.ok, isTrue);
      expect(next.equipped, DiceSkinId.candy);
    });

    test('unlock is idempotent', () {
      var s = const CosmeticsState();
      final (a, r1) = CosmeticsLogic.unlock(s, DiceSkinId.gold);
      expect(r1.ok, isTrue);
      s = a;
      final (b, r2) = CosmeticsLogic.unlock(s, DiceSkinId.gold);
      expect(r2.ok, isFalse);
      expect(b.owned.length, a.owned.length);
    });
  });

  group('CosmeticsLogic achievements', () {
    test('pot win credits wallet and unlocks Gold', () {
      const s = CosmeticsState();
      final (next, toasts) = CosmeticsLogic.onPotWin(s);
      expect(next.walletCents, 200 + DiceSkinCatalog.potWinWalletBonus);
      expect(next.isOwned(DiceSkinId.gold), isTrue);
      expect(toasts, isNotEmpty);
      expect(next.pendingToast, contains('Gold'));
    });

    test('third hand win unlocks Neon', () {
      var s = const CosmeticsState();
      for (var i = 0; i < 2; i++) {
        final (n, t) = CosmeticsLogic.onHandWin(s);
        s = n;
        expect(s.isOwned(DiceSkinId.neon), isFalse);
        expect(t, isEmpty);
      }
      final (next, toasts) = CosmeticsLogic.onHandWin(s);
      expect(next.matchHandWins, 3);
      expect(next.isOwned(DiceSkinId.neon), isTrue);
      expect(toasts.first, contains('Neon'));
    });

    test('third bust unlocks Lucky Bones', () {
      var s = const CosmeticsState();
      for (var i = 0; i < 2; i++) {
        final (n, _) = CosmeticsLogic.onBust(s);
        s = n;
        expect(s.isOwned(DiceSkinId.luckyBones), isFalse);
      }
      final (next, toasts) = CosmeticsLogic.onBust(s);
      expect(next.matchBusts, 3);
      expect(next.isOwned(DiceSkinId.luckyBones), isTrue);
      expect(toasts.first, contains('Lucky Bones'));
    });

    test('resetMatchProgress clears counters but keeps owned', () {
      final s = CosmeticsLogic.resetMatchProgress(
        const CosmeticsState(
          owned: {DiceSkinId.classic, DiceSkinId.neon},
          matchHandWins: 2,
          matchBusts: 1,
        ),
      );
      expect(s.matchHandWins, 0);
      expect(s.matchBusts, 0);
      expect(s.isOwned(DiceSkinId.neon), isTrue);
    });
  });

  group('CosmeticsNotifier persistence', () {
    test('buy + equip round-trips through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Wait for microtask load.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final notifier = container.read(cosmeticsProvider.notifier);
      // Ensure prefs loaded
      for (var i = 0; i < 20 && !container.read(cosmeticsProvider).loaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(container.read(cosmeticsProvider).loaded, isTrue);
      expect(container.read(cosmeticsProvider).walletCents, 200);

      final buy = await notifier.buy(DiceSkinId.midnight);
      expect(buy.ok, isTrue);
      final equip = await notifier.equip(DiceSkinId.midnight);
      expect(equip.ok, isTrue);

      // New container should reload from same mock prefs store.
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      await Future<void>.delayed(Duration.zero);
      for (var i = 0;
          i < 20 && !container2.read(cosmeticsProvider).loaded;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final reloaded = container2.read(cosmeticsProvider);
      expect(reloaded.isOwned(DiceSkinId.midnight), isTrue);
      expect(reloaded.equipped, DiceSkinId.midnight);
      expect(reloaded.walletCents, 150);
    });
  });
}
