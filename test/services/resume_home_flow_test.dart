import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/friends_service.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    PlayerCoinLedger.bootstrap = null;
    FriendsNotifier.bootstrap = null;
    SavedGameStore.bootstrap = null;
    SettingsNotifier.bootstrap = null;
  });

  testWidgets('leave unfinished shows Resume card on home', (tester) async {
    SharedPreferences.setMockInitialValues({'player_name': 'Jerilyn'});
    PlayerCoinLedger.bootstrap = await PlayerCoinLedger.load();
    FriendsNotifier.bootstrap = await FriendsNotifier.load();
    SavedGameStore.bootstrap = await SavedGameStore.load();
    SettingsNotifier.bootstrap = await SettingsNotifier.load();

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsNothing);
    expect(container.read(savedGamesProvider), isEmpty);

    container.read(matchProvider.notifier).start(
          botCount: 1,
          playerName: 'Jerilyn',
        );
    expect(container.read(matchProvider), isNotNull);
    expect(
      container.read(savedGamesProvider),
      isNotEmpty,
      reason: 'start should persist unfinished table',
    );

    await container.read(matchProvider.notifier).leaveUnfinished();
    expect(container.read(matchProvider), isNull);
    expect(container.read(savedGamesProvider), isNotEmpty);

    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Resume'), findsWidgets);

    final cold = await SavedGameStore.load();
    expect(cold.games, isNotEmpty);
  });

  test('reload must not wipe in-memory unsaved upserts before prefs attach',
      () async {
    SharedPreferences.setMockInitialValues({});
    SavedGameStore.bootstrap = null;

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(savedGamesProvider), isEmpty);

    final game = SavedGame.fromJson({
      'id': 'sg-race',
      'savedAt': '2026-09-14T18:00:00.000Z',
      'table': {
        'phase': 'playing',
        'potCents': 20,
        'roundNumber': 1,
        'currentSeatIndex': 0,
        'config': {
          'botCount': 1,
          'otherHumanCount': 0,
          'onlinePlayerCount': 0,
          'friendNames': <String>[],
          'localPlayerName': 'You',
        },
        'players': [
          {
            'id': 'human_0',
            'name': 'You',
            'kind': 'human',
            'avatarEmoji': '🎲',
            'colorSeed': 0,
            'bankCents': 70,
            'usedHouseStake': false,
            'eliminated': false,
          },
          {
            'id': 'bot_0',
            'name': 'Spike',
            'kind': 'bot',
            'personality': 'aggressive',
            'avatarEmoji': '🤖',
            'colorSeed': 1,
            'bankCents': 45,
            'usedHouseStake': false,
            'eliminated': false,
          },
        ],
        'log': <String>['hi'],
      },
    });
    expect(game, isNotNull);
    container.read(savedGamesProvider.notifier).upsert(game!);
    expect(container.read(savedGamesProvider), hasLength(1));

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await container.read(savedGamesProvider.notifier).ensureReady();
    await container.read(savedGamesProvider.notifier).flush();

    expect(
      container.read(savedGamesProvider),
      hasLength(1),
      reason: 'reload must not discard games upserted before prefs load finished',
    );

    final cold = await SavedGameStore.load();
    expect(cold.games, hasLength(1));
  });
}
