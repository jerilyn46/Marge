import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UAT #1: a trip to the Shop mid-game must not reset the pot or the table.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
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
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    PlayerCoinLedger.bootstrap = null;
    SettingsNotifier.bootstrap = null;
    SavedGameStore.bootstrap = null;
  });

  test('shop round-trip keeps the same pot, round, seat, and turn', () async {
    final match = container.read(matchProvider.notifier);
    match.start(botCount: 2, playerName: 'You');
    await match.roll();
    final before = container.read(matchProvider)!.snapshot;
    expect(before.potCents, greaterThan(0));

    match.suspendForShop();
    expect(match.shopOpen, isTrue);
    // Table is saved while the store is open (survives a Billing process kill).
    final saved = container.read(savedGamesProvider);
    expect(saved, isNotEmpty);
    expect(saved.first.table.potCents, before.potCents);

    // Bots must not play behind the Shop.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    match.resumeAfterShop();
    expect(match.shopOpen, isFalse);

    final after = container.read(matchProvider)!.snapshot;
    expect(after.potCents, before.potCents);
    expect(after.roundNumber, before.roundNumber);
    expect(after.currentSeatIndex, before.currentSeatIndex);
    expect(after.turn?.rollNumber, before.turn?.rollNumber);
    expect(after.phase, isNot(MatchPhase.matchEnd));
  });

  test('Continue playing after match end carries the pot forward', () {
    final match = container.read(matchProvider.notifier);
    match.start(botCount: 2, playerName: 'You');
    match.endMatch();
    final ended = container.read(matchProvider)!.snapshot;
    expect(ended.phase, MatchPhase.matchEnd);
    final leftover = ended.potCents;
    expect(leftover, 30); // 3 antes of 10

    match.rematch();
    final again = container.read(matchProvider)!.snapshot;
    // Carried pot + 3 new antes.
    expect(again.potCents, leftover + 30);
    expect(again.log.any((l) => l.contains('Pot carried over')), isTrue);
  });

  test('a fresh match (not Continue playing) still starts from antes only',
      () {
    final match = container.read(matchProvider.notifier);
    match.start(botCount: 2, playerName: 'You');
    expect(container.read(matchProvider)!.snapshot.potCents, 30);
  });
}
