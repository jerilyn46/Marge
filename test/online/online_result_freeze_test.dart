import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/online/room_models.dart';
import 'package:marge/online/room_service.dart';
import 'package:marge/ui/screens/online_match_screen.dart';
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
}
