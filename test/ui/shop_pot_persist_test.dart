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

  test('buying gems mid-match: bank credited, table and pot untouched', () {
    final match = container.read(matchProvider.notifier);
    final ledger = container.read(coinLedgerProvider.notifier);
    match.start(botCount: 2, playerName: 'You');

    int bank() => container.read(coinLedgerProvider).availableHumanGems('You');
    int table() => container
        .read(matchProvider)!
        .snapshot
        .players
        .firstWhere((p) => p.profile.id == 'human_0')
        .bankCents;
    int pot() => container.read(matchProvider)!.snapshot.potCents;
    int seatsTotal() => container
        .read(matchProvider)!
        .snapshot
        .players
        .fold(0, (sum, p) => sum + p.bankCents);

    final bank0 = bank();
    final table0 = table();
    final pot0 = pot();
    final seats0 = seatsTotal();
    // Sat down with 100 of 200; ante 10 went to the pot.
    expect(bank0, 100);
    expect(table0, 90);
    expect(pot0, 30);

    match.suspendForShop();
    // Same credit path GemIapNotifier uses for a completed pack purchase.
    expect(ledger.grantHumanPlayCoins('You', cents: 500), bank0 + 500);
    match.resumeAfterShop();

    expect(bank(), bank0 + 500, reason: 'purchase lands in the gem bank');
    expect(table(), table0, reason: 'table gems unchanged by the store');
    expect(pot(), pot0, reason: 'pot unchanged by the store');
    expect(seatsTotal(), seats0);

    // Moving purchased gems onto the table conserves the total.
    expect(match.moveFromMainBank(100), table0 + 100);
    expect(bank(), bank0 + 400);
    expect(table(), table0 + 100);
    expect(pot(), pot0);
    expect(bank() + seatsTotal() + pot(), bank0 + 500 + seats0 + pot0);
  });
}
