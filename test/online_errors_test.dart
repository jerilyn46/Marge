import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/online/online_errors.dart';
import 'package:marge/online/room_models.dart';
import 'package:marge/ui/screens/online_match_screen.dart';

FirebaseFunctionsException fx(String code, [String msg = '']) =>
    FirebaseFunctionsException(code: code, message: msg);

void main() {
  group('OnlineErrors', () {
    test('not-found is exactly the inactive-code sentence', () {
      expect(
        OnlineErrors.message(fx('not-found', 'No room with that code')),
        "That room code isn't active.",
      );
    });

    test('network-ish codes and socket errors say check your connection', () {
      for (final c in ['unavailable', 'deadline-exceeded', 'internal']) {
        expect(OnlineErrors.message(fx(c)), OnlineErrors.network, reason: c);
      }
      expect(
        OnlineErrors.message(const SocketException('no route')),
        OnlineErrors.network,
      );
    });

    test('failed-precondition picks a sentence from the server text', () {
      expect(
        OnlineErrors.message(
          fx('failed-precondition', 'Not enough online gems'),
        ),
        contains('Not enough online gems'),
      );
      expect(
        OnlineErrors.message(fx('failed-precondition', 'Room not open')),
        'That game has already started or closed.',
      );
      expect(
        OnlineErrors.message(fx('failed-precondition', 'Match not running')),
        'This match has ended.',
      );
      expect(
        OnlineErrors.message(fx('failed-precondition', 'weird')),
        "That can't be done right now.",
      );
    });

    test('other codes map, unknown errors are generic, nothing leaks', () {
      expect(
        OnlineErrors.message(fx('resource-exhausted')),
        'That room is full.',
      );
      expect(
        OnlineErrors.message(fx('permission-denied', 'Host only')),
        'Only the host can do that.',
      );
      expect(OnlineErrors.message(fx('aborted')), contains('Try again'));
      final odd = OnlineErrors.message(
        StateError('boom #0 room_service.dart:48'),
      );
      expect(odd, OnlineErrors.generic);
      expect(odd.contains('dart'), isFalse);
    });
  });

  group('MatchView.results', () {
    Map<String, dynamic> match({List<int>? start}) => {
      'status': 'finished',
      'pot': 0,
      'round': 3,
      'winnerSeat': 0,
      'startBanks': ?start,
      'lastPayout': {'message': 'Jerilyn rolled three 1s on the first roll!'},
      'seats': [
        {
          'index': 0,
          'kind': 'host',
          'uid': 'a',
          'displayName': 'Jerilyn',
          'bank': 132,
        },
        {
          'index': 1,
          'kind': 'human',
          'uid': 'b',
          'displayName': 'Box Tester',
          'bank': 68,
        },
        {'index': 2, 'kind': 'open', 'bank': 0},
      ],
    };

    test('uses server startBanks for the gem change', () {
      final r = MatchView.fromMap(match(start: [100, 100])).results();
      expect(r.length, 2);
      expect(r[0].winner, isTrue);
      expect(r[0].changeLabel, '+32');
      expect(r[1].changeLabel, '−32');
    });

    test('falls back to client-seen banks, else no change label', () {
      final m = MatchView.fromMap(match());
      expect(m.results(fallbackStart: [90, 90])[0].changeLabel, '+42');
      expect(m.results()[0].changeLabel, isNull);
    });

    testWidgets('result screen names the winner, shows changes and buttons', (
      tester,
    ) async {
      var again = 0, done = 0;
      final room = Room.fromMap('r', {
        'code': 'ABC234',
        'hostUid': 'a',
        'status': 'finished',
        'ante': 10,
        'seats': [
          {'index': 0, 'kind': 'host', 'uid': 'a'},
          {'index': 1, 'kind': 'human', 'uid': 'b'},
        ],
        'match': match(start: [100, 100]),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineMatchResult(
            room: room,
            match: room.match!,
            myUid: 'a',
            onPlayAgain: () => again++,
            onDone: () => done++,
          ),
        ),
      );
      expect(find.text('You win with 132 gems!'), findsOneWidget);
      expect(find.text('+32'), findsOneWidget);
      expect(find.text('−32'), findsOneWidget);
      expect(find.textContaining('three 1s'), findsOneWidget);
      expect(find.text('Play another game?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('online-play-again')));
      await tester.tap(find.byKey(const ValueKey('online-done')));
      expect([again, done], [1, 1]);
    });
  });
}
