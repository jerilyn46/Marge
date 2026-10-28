import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/gem_iap.dart';
import 'package:marge/services/remove_ads.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/widgets/remove_ads_sheet.dart';
import 'package:marge/ui/widgets/reserved_banner_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildMargeTheme(),
    home: Scaffold(body: ListView(children: [child])),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoveAds.debugReset();
    RemoveAds.debugOffersEnabled = true;
    RemoveAdsMatchEndOffer.shownThisSession = false;
    GemIapNotifier.debugSkipBootstrap = true;
  });
  tearDown(() {
    RemoveAds.debugReset();
    GemIapNotifier.debugSkipBootstrap = false;
  });

  testWidgets('tile shows when not owned, opens sheet with comp copy', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const RemoveAdsTile()));
    await tester.pump();
    expect(find.text('Remove Ads'), findsOneWidget);
    expect(find.text('Banner + match-end ad off'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remove-ads-tile')));
    await tester.pumpAndSettle();
    expect(find.text('Play without ads'), findsOneWidget);
    expect(
      find.text('No lobby banner. No break after a match.'),
      findsOneWidget,
    );
    expect(
      find.text('Bonus-gem videos stay optional — only if you tap.'),
      findsOneWidget,
    );
    expect(find.text('Restore purchase'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remove-ads-not-now')));
    await tester.pumpAndSettle();
    expect(find.text('Play without ads'), findsNothing);
  });

  testWidgets('owned hides tile, banner link and match-end offer', (
    tester,
  ) async {
    RemoveAds.owned.value = true;
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            RemoveAdsTile(),
            RemoveAdsBannerLink(),
            RemoveAdsMatchEndOffer(),
            RemoveAdsSettingsRow(),
          ],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('remove-ads-tile')), findsNothing);
    expect(find.byKey(const ValueKey('remove-ads-banner-link')), findsNothing);
    expect(find.byKey(const ValueKey('remove-ads-match-end')), findsNothing);
    expect(find.text('Ads removed'), findsOneWidget);
  });

  testWidgets('owning mid-session hides tile live', (tester) async {
    await tester.pumpWidget(_host(const RemoveAdsTile()));
    expect(find.byKey(const ValueKey('remove-ads-tile')), findsOneWidget);
    RemoveAds.owned.value = true;
    await tester.pump();
    expect(find.byKey(const ValueKey('remove-ads-tile')), findsNothing);
  });

  testWidgets('match-end offer: dismissible and once per session', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const RemoveAdsMatchEndOffer()));
    expect(find.byKey(const ValueKey('remove-ads-match-end')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('remove-ads-match-end-dismiss')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('remove-ads-match-end')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(const RemoveAdsMatchEndOffer()));
    expect(find.byKey(const ValueKey('remove-ads-match-end')), findsNothing);
  });

  testWidgets('ads-off build shows no offers', (tester) async {
    RemoveAds.debugOffersEnabled = false;
    await tester.pumpWidget(
      _host(
        const Column(children: [RemoveAdsTile(), RemoveAdsMatchEndOffer()]),
      ),
    );
    expect(find.byKey(const ValueKey('remove-ads-tile')), findsNothing);
    expect(find.byKey(const ValueKey('remove-ads-match-end')), findsNothing);
  });

  testWidgets('lobby strip renders house art when owned', (tester) async {
    RemoveAds.owned.value = true;
    await tester.pumpWidget(_host(const ReservedBannerStrip()));
    expect(find.text('Evening table'), findsOneWidget);
  });
}
