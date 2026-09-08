import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/engine/player.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/denver_time.dart';
import 'package:marge/services/friends_service.dart';
import 'package:marge/services/turn_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScriptedRandom implements Random {
  ScriptedRandom(this.sequence);
  final List<int> sequence;
  int i = 0;

  @override
  int nextInt(int max) {
    if (i >= sequence.length) return sequence[i++ % sequence.length] % max;
    return sequence[i++] % max;
  }

  @override
  double nextDouble() => 0.5;

  @override
  bool nextBool() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerCoinLedger save/load', () {
    test('persists human coins and reloads them instead of 100¢', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 9, 8, 18),
      );
      first.write('You', bot: false, cents: 140);
      first.write('Player 2', bot: false, cents: 77);
      await first.flush();

      final cold = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 9, 8, 19),
      );
      expect(cold.savedCents('You', bot: false), 140);
      expect(cold.openingCents('You', bot: false, fallback: 100), 140);
      expect(cold.savedCents('Player 2', bot: false), 77);
      expect(cold.savedCents('Spike', bot: true), isNull);
      expect(cold.openingCents('Alex', bot: false, fallback: 100), 100);
    });

    test('waiting names are never stored', () async {
      SharedPreferences.setMockInitialValues({});
      final ledger = await PlayerCoinLedger.load();
      ledger.write(WaitingSeat.name, bot: false, cents: 50);
      await ledger.flush();
      final loaded = await PlayerCoinLedger.load();
      expect(loaded.balances.containsKey('human:${WaitingSeat.name}'), isFalse);
    });
  });

  group('MatchController ledger', () {
    test('ante deducts and a new controller keeps the saved banks', () {
      final ledger = PlayerCoinLedger();
      final first = MatchController(
        config: const MatchConfig(
          botCount: 1,
          otherHumanCount: 1,
          localPlayerName: 'You',
          humanNames: ['You', 'Player 2'],
        ),
        rng: Random(1),
        coins: ledger,
      );
      first.startMatch();
      expect(first.snapshot.players[0].bankCents, 90);
      expect(ledger.savedCents('You', bot: false), 90);
      expect(ledger.savedCents('Player 2', bot: false), 90);
      expect(ledger.savedCents('Spike', bot: true), 90);

      final second = MatchController(
        config: const MatchConfig(
          botCount: 1,
          otherHumanCount: 1,
          humanNames: ['You', 'Player 2'],
        ),
        rng: Random(2),
        coins: ledger,
      );
      second.startMatch();
      // Saved 90, then this match's ante takes another 10.
      expect(second.snapshot.players[0].bankCents, 80);
      expect(ledger.savedCents('You', bot: false), 80);
      expect(second.snapshot.players[1].profile.name, 'Player 2');
      expect(second.snapshot.players[1].bankCents, 80);
    });

    test('pot win credits the winner on the ledger', () {
      final ledger = PlayerCoinLedger();
      final c = MatchController(
        config: const MatchConfig(botCount: 1, otherHumanCount: 0),
        rng: ScriptedRandom([0, 0, 0]),
        coins: ledger,
      );
      c.startMatch();
      expect(c.snapshot.potCents, 20);
      c.roll();
      expect(c.snapshot.lastPayout?.kind, ScoreKind.tripleOnesPotWin);
      // 90 + pot 20 - new ante 10.
      expect(c.snapshot.players.first.bankCents, 100);
      expect(ledger.savedCents('You', bot: false), 100);
      expect(ledger.savedCents('Spike', bot: true), 80);
    });

    test('bust puts 2¢ in the pot and on the ledger', () {
      final ledger = PlayerCoinLedger();
      final seq = <int>[];
      for (var r = 0; r < 3; r++) {
        seq.addAll([0, 0, 1]);
      }
      final c = MatchController(
        config: const MatchConfig(botCount: 1, otherHumanCount: 0),
        rng: ScriptedRandom(seq),
        coins: ledger,
      );
      c.startMatch();
      final before = c.snapshot.currentPlayer.bankCents;
      c.roll();
      c.roll();
      c.roll();
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      final you = c.snapshot.players.firstWhere((p) => p.profile.name == 'You');
      expect(you.bankCents, before - 2);
      expect(ledger.savedCents('You', bot: false), before - 2);
    });

    test('new player name with no history starts at 100¢', () {
      final ledger = PlayerCoinLedger();
      ledger.write('You', bot: false, cents: 40);
      final c = MatchController(
        config: const MatchConfig(
          botCount: 1,
          localPlayerName: 'Nova Kid',
          humanNames: ['Nova Kid'],
        ),
        coins: ledger,
      );
      c.startMatch();
      expect(c.snapshot.players.first.bankCents, 90);
      expect(ledger.savedCents('You', bot: false), 40);
      expect(ledger.savedCents('Nova Kid', bot: false), 90);
    });
  });

  group('Monday bot reset', () {
    test('Denver week starts Monday 00:00 MDT', () {
      final tuesday = DateTime.utc(2026, 9, 8, 18);
      expect(
        DenverTime.weekStartUtc(tuesday),
        DateTime.utc(2026, 9, 7, 6),
      );
    });

    test('bots reset once per Denver week; humans are never reset', () async {
      SharedPreferences.setMockInitialValues({});
      final ledger = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 9, 6, 12), // Sunday, still prior week
      );
      ledger.write('You', bot: false, cents: 55);
      ledger.write('Spike', bot: true, cents: 12);
      await ledger.flush();

      final monday = DateTime.utc(2026, 9, 7, 6); // Monday 00:00 Denver MDT
      final loaded = await PlayerCoinLedger.load(utcNow: monday);
      expect(loaded.savedCents('You', bot: false), 55);
      expect(loaded.savedCents('Spike', bot: true), 100);
      expect(loaded.lastBotResetAt, monday);

      loaded.write('Spike', bot: true, cents: 33);
      await loaded.flush();
      expect(loaded.applyWeeklyBotReset(DateTime.utc(2026, 9, 8, 18)), isFalse);
      expect(loaded.savedCents('Spike', bot: true), 33);
      expect(loaded.savedCents('You', bot: false), 55);

      final nextWeek = await PlayerCoinLedger.load(
        utcNow: DateTime.utc(2026, 9, 14, 6),
      );
      expect(nextWeek.savedCents('You', bot: false), 55);
      expect(nextWeek.savedCents('Spike', bot: true), 100);
    });
  });

  group('Friends list', () {
    test('add and remove persist across a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final added = FriendsLogic.add(const [], '  Sam ');
      expect(added.error, isNull);
      expect(added.friends.single.name, 'Sam');
      final dup = FriendsLogic.add(added.friends, 'sam');
      expect(dup.error, isNotNull);

      final state = FriendsState(friends: added.friends, loaded: true);
      await prefs.setString(FriendsNotifier.prefsKey, FriendsNotifier.encode(state));

      final removed = FriendsLogic.remove(state.friends, 'Sam');
      expect(removed, isEmpty);
      await prefs.setString(
        FriendsNotifier.prefsKey,
        FriendsNotifier.encode(FriendsState(friends: removed, loaded: true)),
      );
      final loaded = await FriendsNotifier.load(prefs: prefs);
      expect(loaded.friends, isEmpty);

      await prefs.setString(
        FriendsNotifier.prefsKey,
        FriendsNotifier.encode(state),
      );
      final again = await FriendsNotifier.load(prefs: prefs);
      expect(again.names, ['Sam']);
    });

    test('a chosen friend sits before bots and is not replaced by one', () {
      final c = MatchController(
        config: const MatchConfig(
          botCount: 4,
          otherHumanCount: 0,
          onlinePlayerCount: 0,
          friendNames: ['Sam', 'Riley'],
        ),
        rng: Random(1),
      );
      c.startMatch();
      final kinds = c.snapshot.players.map((p) => p.profile.kind).toList();
      expect(kinds.first, SeatKind.human);
      expect(c.snapshot.players[1].profile.name, 'Sam');
      expect(c.snapshot.players[1].profile.isWaiting, isTrue);
      expect(c.snapshot.players[1].profile.isBot, isFalse);
      expect(c.snapshot.players[2].profile.name, 'Riley');
      expect(c.snapshot.players[2].profile.isWaiting, isTrue);
      expect(
        c.snapshot.players.where((p) => p.profile.isBot).map((p) => p.profile.name),
        isNot(contains('Sam')),
      );
      expect(
        c.snapshot.players.where((p) => p.profile.isBot).map((p) => p.profile.name),
        isNot(contains('Riley')),
      );
      // 1 you + 2 friends + leftover bots, never more than 8, friends kept.
      expect(c.snapshot.players.length, lessThanOrEqualTo(8));
      expect(c.snapshot.players.any((p) => p.profile.name == 'Sam'), isTrue);
      expect(c.config.friendNames, ['Sam', 'Riley']);
      // Bots fill leftovers only (max 4, seats left after you+friends = 5).
      expect(c.snapshot.players.where((p) => p.profile.isBot).length, 4);

      final cramped = MatchConfig.clampLobbyCounts(4, 0, 0, 7);
      expect(cramped.friends, 7);
      expect(cramped.bots, 0);
    });
  });

  group('Turn notices', () {
    test('You and friends notify; bots and other humans do not', () {
      expect(
        TurnNotice.forSeat(
          seatName: 'You',
          kind: SeatKind.human,
          localName: 'You',
          friendNames: const ['Sam'],
        ),
        "You's turn",
      );
      expect(
        TurnNotice.forSeat(
          seatName: 'Sam',
          kind: SeatKind.human,
          localName: 'You',
          friendNames: const ['Sam'],
        ),
        "Sam's turn",
      );
      expect(
        TurnNotice.forSeat(
          seatName: 'Spike',
          kind: SeatKind.bot,
          localName: 'You',
          friendNames: const ['Sam'],
        ),
        isNull,
      );
      expect(
        TurnNotice.forSeat(
          seatName: 'Player 2',
          kind: SeatKind.human,
          localName: 'You',
          friendNames: const ['Sam'],
        ),
        isNull,
      );
      expect(
        TurnNotice.forSeat(
          seatName: WaitingSeat.name,
          kind: SeatKind.waiting,
          localName: 'You',
          friendNames: const ['Sam'],
        ),
        isNull,
      );
    });
  });
}
