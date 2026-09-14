import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/gem_iap.dart';
import 'package:marge/ui/screens/shop_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Shop shows gem packs, rewarded, Designer Collection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildMargeTheme(),
          home: const ShopScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Play gems — not real money'), findsOneWidget);
    expect(find.textContaining('Coming soon'), findsNothing);
    expect(find.textContaining('cash-out'), findsWidgets);
    expect(find.textContaining('\$'), findsNothing);

    final scrollable = find.byType(Scrollable).first;
    for (final pack in GemPack.all) {
      await tester.scrollUntilVisible(
        find.textContaining(pack.title),
        240,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(find.textContaining(pack.title), findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.text('Watch for gems'),
      240,
      scrollable: scrollable,
    );
    await tester.pump();
    expect(find.text('Watch for gems'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Designer Collection'),
      240,
      scrollable: scrollable,
    );
    await tester.pump();
    expect(find.text('Designer Collection'), findsOneWidget);
  });
}
