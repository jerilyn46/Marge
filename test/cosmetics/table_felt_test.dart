import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/cosmetics/table_felt.dart';
import 'package:marge/cosmetics/dice_skin.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'catalog: Forest free default matches MargeColors.felt + 100/250/500',
    () {
      final f = TableFeltCatalog.byId(TableFeltId.forest);
      expect(f.isFree, isTrue);
      expect(f.color, MargeColors.felt);
      expect(
        TableFeltCatalog.all.where((d) => !d.isFree).map((d) => d.priceGems),
        [100, 250, 500],
      );
      expect(const TableFeltState().equipped, TableFeltId.forest);
    },
  );

  test('buy spends gem bank, no overspend, no rebuy', () {
    var bank = 120;
    int? spend(int g) {
      if (g > bank) return null;
      bank -= g;
      return bank;
    }

    var s = const TableFeltState();
    var (n, r) = TableFeltLogic.buy(
      s,
      TableFeltId.crimson,
      bankGems: bank,
      spendGems: spend,
    );
    expect(r.ok, isFalse);
    expect(bank, 120);
    (n, r) = TableFeltLogic.buy(
      s,
      TableFeltId.midnight,
      bankGems: bank,
      spendGems: spend,
    );
    expect(r.ok, isTrue);
    expect(bank, 20);
    s = n;
    (n, r) = TableFeltLogic.buy(
      s,
      TableFeltId.midnight,
      bankGems: bank,
      spendGems: spend,
    );
    expect(r.ok, isFalse);
    expect(r.message, 'Already owned');
    expect(bank, 20);
    // Forest already owned → no rebuy either.
    expect(
      TableFeltLogic.buy(
        s,
        TableFeltId.forest,
        bankGems: bank,
        spendGems: spend,
      ).$2.ok,
      isFalse,
    );
  });

  test('ledger refusal blocks purchase', () {
    final (s, r) = TableFeltLogic.buy(
      const TableFeltState(),
      TableFeltId.royal,
      bankGems: 999,
      spendGems: (_) => null,
    );
    expect(r.ok, isFalse);
    expect(s.isOwned(TableFeltId.royal), isFalse);
  });

  test('equip requires ownership', () {
    expect(
      TableFeltLogic.equip(const TableFeltState(), TableFeltId.royal).$2.ok,
      isFalse,
    );
  });

  test('owned + equipped persist across restart', () async {
    SharedPreferences.setMockInitialValues({});
    var c = ProviderContainer();
    c.read(tableFeltProvider);
    await c.read(tableFeltProvider.notifier).reload();
    await c
        .read(tableFeltProvider.notifier)
        .buy(TableFeltId.midnight, bankGems: 100, spendGems: (g) => 0);
    await c.read(tableFeltProvider.notifier).equip(TableFeltId.midnight);
    c.dispose();

    c = ProviderContainer();
    c.read(tableFeltProvider);
    await c.read(tableFeltProvider.notifier).reload();
    final s = c.read(tableFeltProvider);
    expect(s.isOwned(TableFeltId.midnight), isTrue);
    expect(s.equipped, TableFeltId.midnight);
    c.dispose();
  });

  test('dice skins untouched', () {
    expect(DiceSkinCatalog.all, isNotEmpty);
  });

  test('byId resolves every felt id without throwing', () {
    for (final id in TableFeltId.values) {
      expect(TableFeltCatalog.byId(id).id, id);
    }
  });
}
