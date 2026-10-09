import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ads/ads_service.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAds extends AdsService {
  int completed = 0;
  int breaks = 0;
  @override
  void notifyMatchCompleted() => completed++;
  @override
  Future<bool> maybeShowInterstitialAtBreak() async {
    breaks++;
    return false;
  }
}

/// Tester 6: no interstitial the instant results appear; only after a tap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('match-end ad waits for Continue playing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    PlayerCoinLedger.bootstrap = PlayerCoinLedger(
      balances: {'human:You': 200},
      loaded: true,
      prefs: prefs,
    );
    SettingsNotifier.bootstrap = const GameSettings(
      playerName: 'You',
      hasUsername: true,
      loaded: true,
    );
    SavedGameStore.bootstrap = SavedGameStore(loaded: true, prefs: prefs);
    addTearDown(() {
      PlayerCoinLedger.bootstrap = null;
      SettingsNotifier.bootstrap = null;
      SavedGameStore.bootstrap = null;
    });
    final ads = _FakeAds();
    final container = ProviderContainer(
      overrides: [adsServiceProvider.overrideWithValue(ads)],
    );
    addTearDown(container.dispose);
    container.read(matchProvider.notifier)
      ..start(botCount: 1, playerName: 'You')
      ..endMatch();

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Continue playing'), findsOneWidget);
    expect(ads.completed, 1);
    expect(ads.breaks, 0, reason: 'no interstitial on results appearing');

    await tester.tap(find.text('Continue playing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ads.breaks, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
