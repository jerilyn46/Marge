import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/online/room_models.dart';
import 'package:marge/online/room_service.dart';
import 'package:marge/ui/screens/online_match_screen.dart';
import 'package:marge/ui/visuals/dice_3d.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRooms extends RoomService {
  final ctl = StreamController<Room?>.broadcast();
  @override
  Stream<Room?> watchRoom(String roomId) => ctl.stream;
}

Room finishedRoom({
  required String botName,
  required String message,
  int v = 9,
}) => Room.fromMap('JXpYKYbXPIqn3gUcUeip', {
  'code': 'GPLLGC',
  'hostUid': 'me',
  'status': 'finished',
  'ante': 10,
  'version': v,
  'memberUids': ['me', 'bot'],
  'seats': [
    {'index': 0, 'kind': 'host', 'uid': 'me'},
    {'index': 1, 'kind': 'human', 'uid': 'bot'},
  ],
  'match': {
    'status': 'finished',
    'pot': 0,
    'round': 1,
    'winnerSeat': 1,
    'startBanks': [100, 100],
    'seats': [
      {
        'index': 0,
        'kind': 'host',
        'uid': 'me',
        'displayName': 'Jerilyn',
        'bank': 78,
      },
      {
        'index': 1,
        'kind': 'human',
        'uid': 'bot',
        'displayName': botName,
        'bank': 122,
      },
    ],
    'lastPayout': {'message': message},
  },
});

void main() {
  testWidgets(
    'result screen freezes names/message at finish; later room edits do not relabel it (GPLLGC)',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final rooms = FakeRooms();
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: OnlineMatchScreen(
              rooms: rooms,
              roomId: 'JXpYKYbXPIqn3gUcUeip',
              myUid: 'me',
            ),
          ),
        ),
      );
      rooms.ctl.add(
        finishedRoom(
          botName: 'Box Tester',
          message: 'Box Tester rolled three 1s on the first roll!',
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Box Tester wins with 122 gems'), findsOneWidget);
      expect(find.textContaining('Box Tester rolled three 1s'), findsOneWidget);

      // 30 s later the other player deletes their data: an old server
      // relabels the seat and the message. The open screen must not change.
      rooms.ctl.add(
        finishedRoom(
          botName: 'Left player',
          message: 'Left player rolled three 1s on the first roll!',
          v: 10,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Box Tester wins with 122 gems'), findsOneWidget);
      expect(find.textContaining('Left player'), findsNothing);

      // The room doc is then deleted (retention): result stays up.
      rooms.ctl.add(null);
      await t.pumpAndSettle();
      expect(find.text('Box Tester wins with 122 gems'), findsOneWidget);
      expect(find.text('This match is no longer available.'), findsNothing);
      await rooms.ctl.close();
    },
  );

  testWidgets(
    'roll that ends the match (first-roll triple 1s) plays before the result screen',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final rooms = FakeRooms();
      Map<String, dynamic> seat(int i, String uid, int bank) => {
        'index': i,
        'kind': i == 0 ? 'host' : 'human',
        'uid': uid,
        'displayName': i == 0 ? 'Jerilyn' : 'Box Tester',
        'bank': bank,
      };
      final roll = {
        'seq': 7,
        'seat': 0,
        'dice': [1, 1, 1],
        'held': [false, false, false],
        'rollNumber': 1,
        'setNumber': 1,
      };
      Room snap(bool finished) => Room.fromMap('r9', {
        'code': 'ABCDEF',
        'hostUid': 'me',
        'status': finished ? 'finished' : 'playing',
        'ante': 10,
        'version': finished ? 3 : 2,
        'seats': [
          {'index': 0, 'kind': 'host', 'uid': 'me'},
          {'index': 1, 'kind': 'human', 'uid': 'bt'},
        ],
        'match': {
          'status': finished ? 'finished' : 'playing',
          'pot': finished ? 0 : 20,
          'round': 2,
          'startBanks': [100, 100],
          'seats': finished
              ? [seat(0, 'me', 120), seat(1, 'bt', 80)]
              : [seat(0, 'me', 90), seat(1, 'bt', 90)],
          if (finished) 'winnerSeat': 0,
          if (!finished)
            'turn': {
              'seat': 0,
              'rollNumber': 0,
              'setNumber': 1,
              'dice': [1, 1, 1],
              'kept': [false, false, false],
            },
          'rollSeq': finished ? 7 : 6,
          if (finished) 'lastRoll': roll,
          if (finished) 'recentRolls': [roll],
          if (finished)
            'lastPayout': {
              'message': 'Jerilyn rolled three 1s on the first roll!',
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
      expect(
        find.byType(DiceTray),
        findsOneWidget,
        reason: 'table stays up for the final throw',
      );
      expect(t.state<DiceTrayState>(find.byType(DiceTray)).settling, isTrue);
      expect(find.text('You win with 120 gems!'), findsNothing);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(find.text('You win with 120 gems!'), findsOneWidget);
      await rooms.ctl.close();
    },
  );
}
