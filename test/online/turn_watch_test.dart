import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/online/room_models.dart';
import 'package:marge/online/turn_push.dart';
import 'package:marge/online/turn_watch.dart';

MatchView match({
  required int seat,
  int roll = 0,
  int set = 1,
  int round = 1,
  int? rollSeq,
  bool finished = false,
  bool meOut = false,
}) => MatchView.fromMap({
  'status': finished ? 'finished' : 'playing',
  'pot': 20,
  'round': round,
  'seats': [
    {'index': 0, 'kind': 'host', 'uid': 'me', 'bank': 90, 'eliminated': meOut},
    {'index': 1, 'kind': 'human', 'uid': 'op', 'bank': 90},
    {'index': 2, 'kind': 'bot', 'bank': 90},
  ],
  if (!finished)
    'turn': {
      'seat': seat,
      'rollNumber': roll,
      'setNumber': set,
      'dice': [2, 3, 6],
      'kept': [false, false, false],
    },
  'rollSeq': ?rollSeq,
});

void main() {
  group('YourTurnDetector', () {
    test('first snapshot only primes (already my turn on open → no fire)', () {
      final d = YourTurnDetector();
      expect(d.observe(match(seat: 0), 'me'), isFalse);
    });

    test('fires once when the turn passes to me, not on repeats', () {
      final d = YourTurnDetector();
      expect(d.observe(match(seat: 1), 'me'), isFalse);
      expect(d.observe(match(seat: 1, roll: 2), 'me'), isFalse);
      expect(d.observe(match(seat: 0), 'me'), isTrue);
      // Reconnect / resubscribe delivers the same turn again.
      expect(d.observe(match(seat: 0), 'me'), isFalse);
      expect(d.observe(match(seat: 0, roll: 1), 'me'), isFalse);
      // Bank keeps my seat (set 2): still mine, no new buzz.
      expect(d.observe(match(seat: 0, set: 2), 'me'), isFalse);
      expect(d.observe(match(seat: 2), 'me'), isFalse);
      expect(d.observe(match(seat: 0), 'me'), isTrue);
    });

    test('never for bots / others / finished / eliminated', () {
      final d = YourTurnDetector()..observe(match(seat: 1), 'me');
      expect(d.observe(match(seat: 2), 'me'), isFalse);
      expect(d.observe(match(seat: 0, finished: true), 'me'), isFalse);
      expect(d.observe(match(seat: 0, meOut: true), 'me'), isFalse);
      expect(d.observe(null, 'me'), isFalse);
    });
  });

  group('OnlineRollTracker', () {
    test('rollSeq: +1 per new server roll, primed on first load', () {
      final t = OnlineRollTracker();
      expect(t.observe(match(seat: 1, roll: 2, rollSeq: 7)), isFalse);
      expect(t.serial, 0);
      expect(t.observe(match(seat: 1, roll: 2, rollSeq: 7)), isFalse);
      // Opponent's 3rd-roll miss passed the turn in the same commit:
      // the turn shows roll 0 but rollSeq moved → still one animation.
      expect(t.observe(match(seat: 0, rollSeq: 8)), isTrue);
      expect(t.serial, 1);
      // Timeout auto-play rolled several times in one commit → one animation.
      expect(t.observe(match(seat: 1, rollSeq: 11)), isTrue);
      expect(t.serial, 2);
      expect(t.observe(match(seat: 1, rollSeq: 11)), isFalse);
      expect(t.serial, 2);
    });

    test('legacy rooms (no rollSeq) fall back to the visible turn', () {
      final t = OnlineRollTracker();
      expect(t.observe(match(seat: 1)), isFalse);
      expect(t.observe(match(seat: 1, roll: 1)), isTrue);
      expect(t.observe(match(seat: 1, roll: 1)), isFalse);
      expect(t.observe(match(seat: 1, roll: 2)), isTrue);
      expect(t.observe(match(seat: 0)), isFalse);
      expect(t.observe(match(seat: 0, roll: 1)), isTrue);
      expect(t.serial, 3);
    });
  });

  test('push payload → room id only for turn pushes', () {
    expect(
      TurnPush.roomIdFromData({'type': 'turn', 'roomId': 'r1', 'code': 'X'}),
      'r1',
    );
    expect(TurnPush.roomIdFromData({'type': 'other', 'roomId': 'r1'}), isNull);
    expect(TurnPush.roomIdFromData({'type': 'turn'}), isNull);
    expect(TurnPush.roomIdFromData({'type': 'turn', 'roomId': ''}), isNull);
  });

  test(
    'both manifests: notification permission, turn channel, FCM auto-init off',
    () {
      for (final f in [
        'android/app/src/main/AndroidManifest.xml',
        'android/app/src/main/AndroidManifest.ads-on.xml',
      ]) {
        final x = File(f).readAsStringSync();
        expect(x, contains('android.permission.POST_NOTIFICATIONS'), reason: f);
        expect(x, contains(TurnPush.channelId), reason: f);
        expect(x, contains('firebase_messaging_auto_init_enabled'), reason: f);
      }
    },
  );
}
