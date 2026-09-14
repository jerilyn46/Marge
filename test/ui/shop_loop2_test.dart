
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ui/screens/shop_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Shop shows Coming soon packs, rewarded, Designer Collection', (
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
    await tester.pumpAndSettle();

    expect(find.text('Play gems — not real money'), findsOneWidget);
    expect(find.textContaining('Coming soon'), findsWidgets);
    expect(find.textContaining('Watch ad for'), findsNothing);
    expect(find.textContaining('\$'), findsNothing);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Watch for gems'),
      240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Watch for gems'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Designer Collection'),
      240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Designer Collection'), findsOneWidget);
  });
}
