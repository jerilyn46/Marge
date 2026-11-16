import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/engine.dart';
import 'package:marge/online/room_models.dart';
import 'package:marge/online/room_service.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/services/sfx_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/screens/online_match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/visuals/dice_3d.dart';
import 'package:marge/ui/widgets/pot_win_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pot-win moment (QA 2049): every way a seat takes the pot shows the card
/// with the right winner, amount and reason, and the right next-step
/// buttons — offline (MatchScreen results) and online (OnlineMatchResult).

class _Scripted implements Random {
  _Scripted(this.seq);
  final List<int> seq;
  int i = 0;
  @override
  int nextInt(int max) => seq[i++ % seq.length] % max;
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
}

class _Seeded extends MatchNotifier {
  _Seeded(this._seed);
  final MatchViewState _seed;
  @override
  MatchViewState? build() => _seed;
}

/// Records HapticFeedback.vibrate types sent to the platform.
List<String> _recordHaptics(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add('${call.arguments}');
      }
      return null;
    },
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

Future<void> _pumpOffline(WidgetTester t, MatchSnapshot snap) async {
  SharedPreferences.setMockInitialValues({});
  SettingsNotifier.bootstrap = const GameSettings(
    playerName: 'You',
    hasUsername: true,
    loaded: true,
  );
  addTearDown(() => SettingsNotifier.bootstrap = null);
  await t.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        matchProvider.overrideWith(
          () => _Seeded(MatchViewState(snapshot: snap)),
        ),
      ],
      child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
    ),
  );
  await t.pump();
}

String _text(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(ValueKey(key))).data!;

/// The card has played to the end.
Future<void> _finish(WidgetTester t) async {
  await t.pump(PotWinCard.duration);
  await t.pump(const Duration(milliseconds: 100));
}

void _expectOfflineButtons(WidgetTester t) {
  expect(find.text('Play again'), findsOneWidget);
  expect(find.text('Home'), findsOneWidget);
  // Every pot award ends the match: nothing to "keep playing".
  expect(find.textContaining('Keep playing'), findsNothing);
  expect(find.textContaining('Next round'), findsNothing);
}

MatchController _offline(List<int> rng, {MatchConfig? config}) =>
    MatchController(
      config: config ?? const MatchConfig(botCount: 1),
      rng: _Scripted(rng),
    )..startMatch();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('offline', () {
    testWidgets('triple 1s on the first roll: You, pot + 10s, heavy haptic', (
      t,
    ) async {
      final haptics = _recordHaptics(t);
      final c = _offline([0, 0, 0]);
      final pot = c.snapshot.potCents;
      c.roll();
      final s = c.snapshot;
      expect(s.phase, MatchPhase.matchEnd);
      await _pumpOffline(t, s);
      expect(find.byKey(const ValueKey('match-end-pot-win')), findsOneWidget);
      expect(haptics, isEmpty, reason: 'haptic waits for the gems to land');
      await _finish(t);
      expect(_text(t, 'pot-win-headline'), 'You win the pot!');
      expect(_text(t, 'pot-win-amount'), '+${pot + 10} gems');
      expect(_text(t, 'pot-win-tag'), 'TRIPLE 1s');
      expect(_text(t, 'pot-win-reason'), 'Three 1s on the first roll');
      expect(_text(t, 'pot-win-caption'), 'the pot + 10 from each player');
      expect(haptics, ['HapticFeedbackType.heavyImpact']);
      _expectOfflineButtons(t);
    });

    testWidgets('bot rolls triple 1s: names the bot, medium haptic', (t) async {
      final haptics = _recordHaptics(t);
      // You: 2-4-6 three times (bust), then the bot rolls 1-1-1.
      final c = _offline([
        1, 3, 5, 1, 3, 5, 1, 3, 5, //
        for (var i = 0; i < 30; i++) 0,
      ]);
      for (var i = 0; i < 3; i++) {
        c.roll();
      }
      expect(c.snapshot.phase, MatchPhase.awaitingHandoff);
      c.confirmHandoff();
      for (var i = 0; i < 5 && c.snapshot.phase != MatchPhase.matchEnd; i++) {
        c.tickBot();
      }
      final s = c.snapshot;
      expect(s.phase, MatchPhase.matchEnd);
      final bot = BotRoster.nameAt(0);
      await _pumpOffline(t, s);
      await _finish(t);
      expect(_text(t, 'pot-win-headline'), '$bot wins the pot!');
      expect(_text(t, 'pot-win-tag'), 'TRIPLE 1s');
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
      _expectOfflineButtons(t);
    });

    testWidgets('last opponent out after a straight: pot only, reason line', (
      t,
    ) async {
      final c = _offline([0, 1, 2]); // 1-2-3 straight
      c.debugSetBank(1, 5); // the bot can pay exactly 5, then it is out
      final pot = c.snapshot.potCents;
      c.roll();
      c.bank();
      final s = c.snapshot;
      expect(s.phase, MatchPhase.matchEnd);
      final bot = BotRoster.nameAt(0);
      await _pumpOffline(t, s);
      await _finish(t);
      expect(_text(t, 'pot-win-headline'), 'You win the pot!');
      expect(_text(t, 'pot-win-amount'), '+$pot gems');
      expect(_text(t, 'pot-win-tag'), 'LAST ONE STANDING');
      expect(_text(t, 'pot-win-reason'), 'A straight · $bot is out of gems');
      expect(_text(t, 'pot-win-caption'), 'from the pot');
      _expectOfflineButtons(t);
    });

    testWidgets('last opponent whiffs to 0: they ran out of gems', (t) async {
      final c = _offline([1, 3, 5]); // 2-4-6 forever: nobody scores
      c.debugSetBank(1, 2);
      for (var i = 0; i < 3; i++) {
        c.roll();
      }
      c.confirmHandoff();
      for (var i = 0; i < 8 && c.snapshot.phase != MatchPhase.matchEnd; i++) {
        c.tickBot();
      }
      final s = c.snapshot;
      expect(s.phase, MatchPhase.matchEnd);
      expect(s.lastPayout?.potWinReason, PotWinReason.opponentOut);
      final bot = BotRoster.nameAt(0);
      await _pumpOffline(t, s);
      await _finish(t);
      expect(_text(t, 'pot-win-headline'), 'You win the pot!');
      expect(_text(t, 'pot-win-amount'), '+${s.lastPayout!.potCents} gems');
      expect(_text(t, 'pot-win-reason'), '$bot whiffed and ran out of gems');
      _expectOfflineButtons(t);
    });

    testWidgets('hotseat opponent quits a shortfall: roller takes the pot', (
      t,
    ) async {
      final c = _offline(
        [4, 4, 4], // three 5s on the first roll: 10 each
        config: const MatchConfig(
          botCount: 0,
          otherHumanCount: 1,
          startBankCents: 15,
        ),
      );
      final pot = c.snapshot.potCents;
      c.roll();
      c.bank();
      expect(c.snapshot.phase, MatchPhase.awaitingShortfall);
      c.quitShortfall();
      final s = c.snapshot;
      expect(s.phase, MatchPhase.matchEnd);
      await _pumpOffline(t, s);
      await _finish(t);
      expect(_text(t, 'pot-win-headline'), 'You win the pot!');
      expect(_text(t, 'pot-win-amount'), '+$pot gems');
      expect(_text(t, 'pot-win-tag'), 'OPPONENT QUIT');
      expect(_text(t, 'pot-win-reason'), 'Player 2 quit the game');
      _expectOfflineButtons(t);
    });

    testWidgets('End match (nobody took the pot): no card', (t) async {
      final c = _offline([1, 3, 5]);
      c.endMatch();
      await _pumpOffline(t, c.snapshot);
      await _finish(t);
      expect(find.byType(PotWinCard), findsNothing);
      expect(find.text('🏆 Match over'), findsOneWidget);
      _expectOfflineButtons(t);
    });

    testWidgets('tap skips straight to the end', (t) async {
      final haptics = _recordHaptics(t);
      final c = _offline([0, 0, 0]);
      final pot = c.snapshot.potCents;
      c.roll();
      await _pumpOffline(t, c.snapshot);
      await t.pump(const Duration(milliseconds: 500));
      expect(_text(t, 'pot-win-amount'), isNot('+${pot + 10} gems'));
      await t.tap(find.byKey(const ValueKey('pot-win-card')));
      await t.pump();
      expect(_text(t, 'pot-win-amount'), '+${pot + 10} gems');
      expect(haptics, ['HapticFeedbackType.heavyImpact']);
      await _finish(t);
      expect(haptics.length, 1, reason: 'lands once');
    });

    testWidgets('haptics and sound off in Settings: silent card', (t) async {
      final haptics = _recordHaptics(t);
      final c = _offline([0, 0, 0]);
      c.roll();
      SharedPreferences.setMockInitialValues({});
      SettingsNotifier.bootstrap = const GameSettings(
        playerName: 'You',
        hasUsername: true,
        loaded: true,
        sfxEnabled: false,
        hapticsEnabled: false,
      );
      addTearDown(() => SettingsNotifier.bootstrap = null);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            matchProvider.overrideWith(
              () => _Seeded(MatchViewState(snapshot: c.snapshot)),
            ),
          ],
          child: MaterialApp(
            theme: buildMargeTheme(),
            home: const MatchScreen(),
          ),
        ),
      );
      await _finish(t);
      expect(_text(t, 'pot-win-headline'), 'You win the pot!');
      expect(haptics, isEmpty);
    });
  });

  group('online', () {
    Map<String, dynamic> seat(
      int i,
      String uid,
      String name,
      int bank, {
      bool eliminated = false,
      bool left = false,
      int? leftWith,
    }) => {
      'index': i,
      'kind': i == 0 ? 'host' : 'human',
      'uid': uid,
      'displayName': name,
      'bank': bank,
      'eliminated': eliminated,
      'left': left,
      'leftWith': ?leftWith,
    };

    Room finished(
      Map<String, dynamic> payout, {
      required List<Map<String, dynamic>> seats,
      int? winnerSeat = 0,
      String hostUid = 'me',
    }) => Room.fromMap('r1', {
      'code': 'ABCDEF',
      'hostUid': hostUid,
      'status': 'finished',
      'ante': 10,
      'version': 9,
      'seats': [
        {'index': 0, 'kind': 'host', 'uid': 'me'},
        {'index': 1, 'kind': 'human', 'uid': 'bt'},
      ],
      'match': {
        'status': 'finished',
        'pot': 0,
        'round': 1,
        'winnerSeat': winnerSeat,
        'startBanks': [100, 100],
        'seats': seats,
        'lastPayout': payout,
      },
    });

    Future<SfxService> pumpResult(
      WidgetTester t,
      Room room, {
      String myUid = 'me',
      bool host = true,
    }) async {
      final sfx = SfxService();
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildMargeTheme(),
            home: OnlineMatchResult(
              room: room,
              match: room.match!,
              myUid: myUid,
              onPlayAgain: () {},
              onLobby: host ? () {} : null,
              onDone: () {},
              sfx: sfx,
            ),
          ),
        ),
      );
      await t.pump();
      return sfx;
    }

    void expectHostButtons() {
      expect(find.byKey(const ValueKey('online-play-again')), findsOneWidget);
      expect(find.byKey(const ValueKey('online-lobby')), findsOneWidget);
      expect(find.text('BACK TO LOBBY'), findsOneWidget);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.textContaining('KEEP PLAYING'), findsNothing);
      expect(find.textContaining('Keep playing'), findsNothing);
    }

    testWidgets('first-roll triple 1s (you)', (t) async {
      final cues = <SfxCue>[];
      final room = finished(
        {
          'message':
              'Jerilyn rolled three 1s on the first roll! Everyone pays 10 '
              'and Jerilyn wins the pot.',
          'kind': 'tripleOnesPotWin',
          'amount': 30,
          'seat': 0,
        },
        seats: [seat(0, 'me', 'Jerilyn', 120), seat(1, 'bt', 'Box Tester', 80)],
      );
      final sfx = await pumpResult(t, room);
      sfx.debugOnCue = cues.add;
      await _finish(t);
      expect(_text(t, 'pot-win-headline'), 'You win the pot!');
      expect(_text(t, 'pot-win-amount'), '+30 gems');
      expect(_text(t, 'pot-win-tag'), 'TRIPLE 1s');
      expect(_text(t, 'pot-win-reason'), 'Three 1s on the first roll');
      expect(cues, [SfxCue.gemChimeCascade]);
      // Existing result rows still there under the card.
      expect(find.text('You win with 120 gems!'), findsOneWidget);
      expectHostButtons();
    });

    testWidgets('opponent left: "X left the table. Pot of N goes to Y."', (
      t,
    ) async {
      final room = finished(
        {
          'message': 'Box Tester left the table. Pot of 28 goes to Jerilyn.',
          'kind': 'none',
          'amount': 0,
          'seat': 1,
        },
        seats: [
          seat(0, 'me', 'Jerilyn', 166),
          seat(
            1,
            'bt',
            'Box Tester',
            0,
            eliminated: true,
            left: true,
            leftWith: 97,
          ),
        ],
      );
      await pumpResult(t, room);
      await _finish(t);
      expect(_text(t, 'pot-win-headline'), 'You win the pot!');
      expect(_text(t, 'pot-win-amount'), '+28 gems');
      expect(_text(t, 'pot-win-tag'), 'OPPONENT LEFT');
      expect(_text(t, 'pot-win-reason'), 'Box Tester left the table');
      expect(find.text('100 → 97 gems · left'), findsOneWidget);
      expectHostButtons();
    });

    testWidgets('opponent busts out of gems: sweep line', (t) async {
      final room = finished(
        {
          'message':
              'Box Tester is out of gems — Jerilyn wins the pot (40 gems).',
          'kind': 'tripleOnesPotWin',
          'amount': 40,
          'seat': 0,
        },
        seats: [
          seat(0, 'me', 'Jerilyn', 200),
          seat(1, 'bt', 'Box Tester', 0, eliminated: true),
        ],
      );
      await pumpResult(t, room);
      await _finish(t);
      expect(_text(t, 'pot-win-amount'), '+40 gems');
      expect(_text(t, 'pot-win-tag'), 'LAST ONE STANDING');
      expect(_text(t, 'pot-win-reason'), 'Box Tester ran out of gems');
      expectHostButtons();
    });

    testWidgets('straight knocks the last opponent out', (t) async {
      final room = finished(
        {
          'message':
              'Jerilyn hits a straight! Collects 5 gems. Box Tester out of '
              'gems. — Jerilyn wins the pot (24 gems).',
          'kind': 'tripleOnesPotWin',
          'amount': 24,
          'seat': 0,
        },
        seats: [
          seat(0, 'me', 'Jerilyn', 200),
          seat(1, 'bt', 'Box Tester', 0, eliminated: true),
        ],
      );
      await pumpResult(t, room);
      await _finish(t);
      expect(_text(t, 'pot-win-amount'), '+24 gems');
      expect(
        _text(t, 'pot-win-reason'),
        'A straight · Box Tester is out of gems',
      );
    });

    testWidgets('opponent paid the ante and is out', (t) async {
      final room = finished(
        {
          'message':
              'Box Tester paid the ante and is out — Jerilyn wins the pot '
              '(20 gems).',
          'kind': 'tripleOnesPotWin',
          'amount': 20,
          'seat': 0,
        },
        seats: [
          seat(0, 'me', 'Jerilyn', 200),
          seat(1, 'bt', 'Box Tester', 0, eliminated: true),
        ],
      );
      await pumpResult(t, room);
      await _finish(t);
      expect(
        _text(t, 'pot-win-reason'),
        'Box Tester ran out of gems on the ante',
      );
    });

    testWidgets('someone else wins (joiner): their name, no Back to lobby', (
      t,
    ) async {
      final cues = <SfxCue>[];
      final room = finished(
        {
          'message':
              'Jerilyn rolled three 1s on the first roll! Everyone pays 10 '
              'and Jerilyn wins the pot.',
          'kind': 'tripleOnesPotWin',
          'amount': 30,
          'seat': 0,
        },
        seats: [seat(0, 'me', 'Jerilyn', 120), seat(1, 'bt', 'Box Tester', 80)],
      );
      final sfx = await pumpResult(t, room, myUid: 'bt', host: false);
      sfx.debugOnCue = cues.add;
      await _finish(t);
      expect(_text(t, 'pot-win-headline'), 'Jerilyn wins the pot!');
      expect(find.byKey(const ValueKey('online-play-again')), findsOneWidget);
      expect(find.byKey(const ValueKey('online-lobby')), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      expect(cues, [SfxCue.gemChimeCascade]);
    });

    testWidgets('host ended with a split pot: no card', (t) async {
      final room = finished(
        {
          'message':
              'Jerilyn ended the match. Pot of 20 returned by table bank: '
              'Jerilyn +12, Box Tester +8.',
          'kind': 'none',
          'amount': 0,
          'seat': 0,
        },
        seats: [seat(0, 'me', 'Jerilyn', 120), seat(1, 'bt', 'Box Tester', 80)],
      );
      await pumpResult(t, room);
      await _finish(t);
      expect(find.byType(PotWinCard), findsNothing);
      expect(find.text('🏆 Match over'), findsOneWidget);
      expectHostButtons();
    });

    test('host ended with one seat left: hostEnded', () {
      final m = finished(
        {
          'message': 'Jerilyn ended the match. Pot of 30 goes to Jerilyn.',
          'kind': 'none',
        },
        seats: [
          seat(0, 'me', 'Jerilyn', 130),
          seat(1, 'bt', 'Box Tester', 0, eliminated: true),
        ],
      ).match!;
      final w = m.potWin('me')!;
      expect(w.reason, PotWinReason.hostEnded);
      expect(w.gems, 30);
      expect(w.reasonLine, 'Jerilyn ended the match');
    });

    testWidgets(
      'winning roll tumbles on the table before the card (2048 queue)',
      (t) async {
        SharedPreferences.setMockInitialValues({});
        final rooms = _FakeRooms();
        final roll = {
          'seq': 7,
          'seat': 1,
          'dice': [1, 1, 1],
          'held': [false, false, false],
          'rollNumber': 1,
          'setNumber': 1,
        };
        Room snap(bool done) => Room.fromMap('r9', {
          'code': 'ABCDEF',
          'hostUid': 'me',
          'status': done ? 'finished' : 'playing',
          'ante': 10,
          'version': done ? 3 : 2,
          'seats': [
            {'index': 0, 'kind': 'host', 'uid': 'me'},
            {'index': 1, 'kind': 'human', 'uid': 'bt'},
          ],
          'match': {
            'status': done ? 'finished' : 'playing',
            'pot': done ? 0 : 20,
            'round': 1,
            'startBanks': [100, 100],
            'seats': done
                ? [
                    seat(0, 'me', 'Jerilyn', 80),
                    seat(1, 'bt', 'Box Tester', 120),
                  ]
                : [
                    seat(0, 'me', 'Jerilyn', 90),
                    seat(1, 'bt', 'Box Tester', 90),
                  ],
            'winnerSeat': done ? 1 : null,
            if (!done)
              'turn': {
                'seat': 1,
                'rollNumber': 0,
                'setNumber': 1,
                'dice': [1, 1, 1],
                'kept': [false, false, false],
              },
            'rollSeq': done ? 7 : 6,
            if (done) 'lastRoll': roll,
            if (done) 'recentRolls': [roll],
            if (done)
              'lastPayout': {
                'message':
                    'Box Tester rolled three 1s on the first roll! Everyone '
                    'pays 10 and Box Tester wins the pot.',
                'kind': 'tripleOnesPotWin',
                'amount': 30,
                'seat': 1,
              },
          },
        });
        await t.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: OnlineMatchScreen(rooms: rooms, roomId: 'r9', myUid: 'me'),
            ),
          ),
        );
        rooms.ctl.add(snap(false));
        await t.pump();
        rooms.ctl.add(snap(true));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(t.state<DiceTrayState>(find.byType(DiceTray)).settling, isTrue);
        expect(find.byType(PotWinCard), findsNothing, reason: 'roll first');
        await t.pump(const Duration(seconds: 3));
        await t.pump();
        expect(find.byType(DiceTray), findsNothing);
        expect(find.byType(PotWinCard), findsOneWidget);
        await _finish(t);
        expect(_text(t, 'pot-win-headline'), 'Box Tester wins the pot!');
        expect(_text(t, 'pot-win-amount'), '+30 gems');
        await rooms.ctl.close();
      },
    );
  });
}

class _FakeRooms extends RoomService {
  final ctl = StreamController<Room?>.broadcast();
  @override
  Stream<Room?> watchRoom(String roomId) => ctl.stream;
}
