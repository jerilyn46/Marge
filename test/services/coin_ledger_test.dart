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
      expect(c.snapshot.players[1].bankCents, 0);
      expect(c.snapshot.players[2].bankCents, 0);
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
    test('waiting friend row and seat do not show a coin amount', () {
      final ledger = PlayerCoinLedger();
      ledger.write('Sam', bot: false, cents: 250);
      ledger.write('You', bot: false, cents: 140);
      expect(ledger.savedCents('Sam', bot: false), 250);

      final seats = PlayerCoinLedger.lobbySeats(
        localName: 'You',
        otherHumans: 0,
        online: 1,
        bots: 1,
        friendNames: const ['Sam'],
        ledger: ledger,
      );
      final samLobby = seats.firstWhere((s) => s.name == 'Sam');
      final online = seats.firstWhere((s) => s.name == WaitingSeat.name);
      expect(samLobby.waiting, isTrue);
      expect(samLobby.coins, isNull);
      expect(samLobby.line, isNot(contains('¢')));
      expect(samLobby.line, isNot(contains('250')));
      expect(samLobby.line, isNot(contains('100')));
      expect(online.waiting, isTrue);
      expect(online.coins, isNull);
      expect(online.line, isNot(contains('¢')));
      expect(online.line, isNot(contains('100')));
      // You still shows the saved bank. Waiting chairs do not.
      expect(seats.first.line, contains('140¢'));

      const seated = FriendEntry(name: 'Sam');
      const aside = FriendEntry(name: 'Sam', seated: false);
      expect(FriendsLogic.statusLabel(seated), 'Waiting to sit');
      expect(FriendsLogic.rowLabel(seated), isNot(contains('¢')));
      expect(FriendsLogic.rowLabel(seated), isNot(contains('250')));
      expect(FriendsLogic.rowLabel(seated), isNot(contains('100')));
      expect(FriendsLogic.rowLabel(aside), isNot(contains('¢')));

      // A waiting chair must not display coins even if a bank was stuffed in.
      const stuffed = PlayerState(
        profile: PlayerProfile(
          id: 'friend_0',
          name: 'Sam',
          kind: SeatKind.waiting,
          avatarEmoji: '👋',
        ),
        bankCents: 100,
      );
      expect(stuffed.showsCoinTotal, isFalse);
      expect(stuffed.coinTotalLabel, 'Waiting');
      expect(stuffed.coinTotalLabel, isNot(contains('¢')));
      expect(stuffed.coinTotalLabel, isNot(contains('100')));

      final c = MatchController(
        config: const MatchConfig(
          botCount: 1,
          friendNames: ['Sam'],
        ),
        rng: Random(1),
        coins: ledger,
      );
      c.startMatch();
      final sam = c.snapshot.players.firstWhere((p) => p.profile.name == 'Sam');
      expect(sam.profile.isWaiting, isTrue);
      expect(sam.profile.isBot, isFalse);
      expect(sam.profile.participates, isFalse);
      expect(sam.coinTotalLabel, 'Waiting');
      expect(sam.coinTotalLabel, isNot(contains('¢')));
      expect(c.snapshot.currentPlayer.profile.name, isNot('Sam'));
      expect(c.snapshot.currentPlayer.profile.isBot, isFalse);
      // You + bot ante only. Sam does not ante, roll, or get written as 0/100.
      expect(c.snapshot.potCents, 20);
      expect(ledger.savedCents('Sam', bot: false), 250);
      expect(ledger.savedCents('You', bot: false), 130);

      c.roll();
      final after = c.snapshot.players.firstWhere((p) => p.profile.name == 'Sam');
      expect(after.profile.isWaiting, isTrue);
      expect(after.coinTotalLabel, isNot(contains('¢')));
      expect(ledger.savedCents('Sam', bot: false), 250);
      expect(c.snapshot.players.any((p) => p.profile.isBot && p.profile.name == 'Sam'), isFalse);
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
