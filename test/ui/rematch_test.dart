import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rematch restarts same seats/ante without ready-check', () async {
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

    final container = ProviderContainer();
    addTearDown(() {
      container.dispose();
      PlayerCoinLedger.bootstrap = null;
      SettingsNotifier.bootstrap = null;
      SavedGameStore.bootstrap = null;
    });

    final match = container.read(matchProvider.notifier);
    match.start(botCount: 2, otherHumanCount: 0, playerName: 'You');
    final first = container.read(matchProvider);
    expect(first, isNotNull);
    expect(first!.snapshot.config.anteCents, 10);
    expect(first.snapshot.config.botCount, 2);

    match.endMatch();
    expect(
      container.read(matchProvider)!.snapshot.phase,
      MatchPhase.matchEnd,
    );

    match.rematch();
    final again = container.read(matchProvider);
    expect(again, isNotNull);
    expect(again!.snapshot.phase, isNot(MatchPhase.matchEnd));
    expect(again.snapshot.config.botCount, 2);
    expect(again.snapshot.config.anteCents, 10);
    expect(again.snapshot.config.localPlayerName, 'You');
    expect(
      again.snapshot.players.where((p) => p.profile.participates).length,
      greaterThanOrEqualTo(2),
    );
  });
}
