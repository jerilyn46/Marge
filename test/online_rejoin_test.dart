import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/online/active_room.dart';
import 'package:marge/online/room_models.dart';
import 'package:marge/ui/widgets/rejoin_banner.dart';

Room room(
  String id,
  String status, {
  int version = 1,
  bool meOut = false,
  bool meSeated = true,
}) => Room.fromMap(id, {
  'code': 'C$id',
  'hostUid': 'h',
  'status': status,
  'ante': 10,
  'version': version,
  'memberUids': ['me', 'h'],
  'seats': [
    {'index': 0, 'kind': 'host', 'uid': 'h'},
    meSeated
        ? {'index': 1, 'kind': 'human', 'uid': 'me'}
        : {'index': 1, 'kind': 'open'},
  ],
  if (status != 'lobby')
    'match': {
      'status': status == 'finished' ? 'finished' : 'playing',
      'pot': 20,
      'round': 1,
      'seats': [
        {'index': 0, 'kind': 'host', 'uid': 'h', 'bank': 90},
        {
          'index': 1,
          'kind': 'human',
          'uid': 'me',
          'bank': 90,
          'eliminated': meOut,
        },
      ],
    },
});

void main() {
  group('pickActiveRoom', () {
    test('finds a running match where my seat is still in', () {
      expect(pickActiveRoom([room('a', 'playing')], 'me')?.id, 'a');
    });

    test('ignores finished, abandoned, and matches I left or busted from', () {
      expect(
        pickActiveRoom([
          room('f', 'finished'),
          room('x', 'abandoned'),
          room('l', 'playing', meOut: true),
          room('o', 'lobby', meSeated: false),
        ], 'me'),
        isNull,
      );
    });

    test('prefers a running match over a lobby, then the newest', () {
      expect(
        pickActiveRoom([
          room('lob', 'lobby', version: 9),
          room('p1', 'playing', version: 3),
          room('p2', 'playing', version: 7),
        ], 'me')?.id,
        'p2',
      );
      expect(pickActiveRoom([room('lob', 'lobby')], 'me')?.id, 'lob');
    });
  });

  group('RejoinPrompt', () {
    Future<void> pump(WidgetTester t, Widget w) =>
        t.pumpWidget(MaterialApp(home: Scaffold(body: w)));

    testWidgets('shows nothing without a live room', (t) async {
      await pump(
        t,
        RejoinPrompt(
          find: () async => null,
          onRejoin: (_) async {},
          leave: (_) async {},
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('rejoin-banner')), findsNothing);
    });

    testWidgets('Rejoin opens the room; Leave confirms then leaves', (t) async {
      Room? live = room('a', 'playing');
      final opened = <String>[], left = <String>[];
      await pump(
        t,
        RejoinPrompt(
          find: () async => live,
          onRejoin: (r) async => opened.add(r.id),
          leave: (r) async {
            left.add(r.id);
            live = null;
          },
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Rejoin your match'), findsOneWidget);
      expect(find.textContaining('room Ca'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('rejoin-go')));
      await t.pumpAndSettle();
      expect(opened, ['a']);
      expect(find.text('Rejoin your match'), findsOneWidget); // still live

      await t.tap(find.byKey(const ValueKey('rejoin-leave')));
      await t.pumpAndSettle();
      expect(find.text('Leave this match?'), findsOneWidget);
      await t.tap(find.text('Leave'));
      await t.pumpAndSettle();
      expect(left, ['a']);
      expect(find.byKey(const ValueKey('rejoin-banner')), findsNothing);
    });
  });
}
