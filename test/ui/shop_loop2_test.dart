import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/gem_iap.dart';
import 'package:marge/ui/screens/shop_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Shop: neutral note when packs fail to load, Designer Collection', (
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
    // Billing has no products in tests: no disabled "Unavailable" buttons,
    // just a short neutral note (Tester 7). Billing never answers in tests,
    // so the load times out and the spinner gives way to the note.
    await tester.pump(GemIapNotifier.billingTimeout);
    await tester.pump(const Duration(milliseconds: 100));
    for (final pack in GemPack.all) {
      expect(find.textContaining(pack.title), findsNothing);
    }
    expect(find.text('Unavailable'), findsNothing);
    expect(
      find.byKey(const ValueKey('gem-packs-unavailable')),
      findsOneWidget,
    );

    // Ads are off in tests: the rewarded card is hidden, with no
    // developer-facing "ads off in this build" copy.
    expect(find.text('Watch for gems'), findsNothing);
    expect(find.textContaining('in this build'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Designer Collection'),
      240,
      scrollable: scrollable,
    );
    await tester.pump();
    expect(find.text('Designer Collection'), findsOneWidget);
  });
}
