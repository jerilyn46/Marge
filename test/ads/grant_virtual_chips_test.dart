import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/cosmetics/skins_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('grantVirtualChips credits cosmetics wallet', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 20 && !container.read(cosmeticsProvider).loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(cosmeticsProvider).loaded, isTrue);

    final before = container.read(cosmeticsProvider).walletCents;
    final after = await container
        .read(cosmeticsProvider.notifier)
        .grantVirtualChips(25, reason: 'test');
    expect(after, before + 25);
    expect(container.read(cosmeticsProvider).walletCents, before + 25);
  });

  test('CosmeticsLogic.creditWallet is pure', () {
    const s = CosmeticsState(walletCents: 100);
    final next = CosmeticsLogic.creditWallet(s, 25);
    expect(next.walletCents, 125);
    expect(CosmeticsLogic.creditWallet(s, 0).walletCents, 100);
  });
}
