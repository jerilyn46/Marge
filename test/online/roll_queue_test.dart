import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/online/room_models.dart';
import 'package:marge/online/turn_watch.dart';
import 'package:marge/services/sfx_service.dart';
import 'package:marge/ui/visuals/dice_3d.dart';

import 'online_table_test.dart' show Harness, HarnessState;

Map<String, dynamic> rollMap(
  int seq,
  int seat,
  List<int> dice, [
  int rollNumber = 1,
  List<bool> held = const [false, false, false],
]) => {
  'seq': seq,
  'seat': seat,
  'dice': dice,
  'held': held,
  'rollNumber': rollNumber,
  'setNumber': 1,
};

/// A room whose match carries rollSeq + lastRoll + recentRolls (QA 2048).
Room room({
  required int version,
  required int turnSeat,
  required List<Map<String, dynamic>> recent,
  int roll = 1,
  String? payout,
  bool finished = false,
  bool withRecent = true,
}) {
  final last = recent.isEmpty ? null : recent.last;
  return Room.fromMap('r1', {
    'code': 'LTEE2Q',
    'hostUid': 'me',
    'status': finished ? 'finished' : 'playing',
    'ante': 10,
    'version': version,
    'seats': [
      {'index': 0, 'kind': 'host', 'uid': 'me'},
      {'index': 1, 'kind': 'human', 'uid': 'op'},
    ],
    'match': {
      'status': finished ? 'finished' : 'playing',
      'pot': 20,
      'round': 1,
      'seats': [
        {
          'index': 0,
          'kind': 'host',
          'uid': 'me',
          'displayName': 'Me',
          'bank': 90,
        },
        {
          'index': 1,
          'kind': 'human',
          'uid': 'op',
          'displayName': 'Op',
          'bank': 90,
        },
      ],
      if (!finished)
        'turn': {
          'seat': turnSeat,
          'rollNumber': roll,
          'setNumber': 1,
          'dice': roll > 0 && last != null ? last['dice'] : [1, 1, 1],
          'kept': [false, false, false],
        },
      'lastPayout': ?(payout == null ? null : {'message': payout}),
      'rollSeq': ?last?['seq'],
      'lastRoll': ?last,
      if (withRecent) 'recentRolls': recent,
    },
  });
}

OnlineRoll r(int seq, [int seat = 1]) => OnlineRoll(
  seq: seq,
  seat: seat,
  dice: [seq % 6 + 1, 2, 3],
  held: const [false, false, false],
  rollNumber: 1,
);

void main() {
  group('OnlineRollTracker.take', () {
    test('first snapshot primes (no replay of recentRolls on first load)', () {
      final t = OnlineRollTracker();
      final m = room(
        version: 1,
        turnSeat: 1,
        recent: [
          rollMap(4, 1, [1, 2, 3]),
          rollMap(5, 1, [4, 4, 2]),
        ],
      ).match;
      expect(t.take(m), isEmpty);
      expect(t.take(m), isEmpty, reason: 'resubscribe re-delivers');
    });

    test('coalesced snapshot yields every missed roll, in order', () {
      final t = OnlineRollTracker()
        ..take(
          room(
            version: 1,
            turnSeat: 0,
            recent: [
              rollMap(2, 0, [1, 2, 3]),
            ],
          ).match,
        );
      final got = t.take(
        room(
          version: 2,
          turnSeat: 0,
          recent: [
            rollMap(1, 1, [6, 6, 6]),
            rollMap(2, 0, [1, 2, 3]),
            rollMap(3, 0, [4, 5, 6], 2),
            rollMap(4, 1, [2, 2, 5]),
            rollMap(5, 1, [2, 2, 2], 2),
          ],
        ).match,
      );
      expect(got.map((x) => x.seq), [3, 4, 5]);
      expect(got.map((x) => x.seat), [0, 1, 1], reason: 'both seats');
      expect(t.serial, 3);
    });

    test('older server (lastRoll only): latest roll still animates', () {
      final t = OnlineRollTracker()
        ..take(
          room(
            version: 1,
            turnSeat: 1,
            recent: [
              rollMap(2, 1, [1, 2, 3]),
            ],
            withRecent: false,
          ).match,
        );
      final got = t.take(
        room(
          version: 2,
          turnSeat: 1,
          recent: [
            rollMap(5, 1, [3, 3, 3]),
          ],
          withRecent: false,
        ).match,
      );
      expect(got.single.seq, 5);
    });

    test('match start (no rollSeq yet) then first roll fires', () {
      final t = OnlineRollTracker()
        ..take(room(version: 1, turnSeat: 0, recent: [], roll: 0).match);
      expect(
        t
            .take(
              room(
                version: 2,
                turnSeat: 0,
                recent: [
                  rollMap(1, 0, [1, 2, 3]),
                ],
              ).match,
            )
            .single
            .seq,
        1,
      );
    });
  });

  group('RollPlayback', () {
    test('queues rolls that arrive mid-throw and plays them in order', () {
      final p = RollPlayback();
      expect(p.add([r(1)]), isTrue);
      expect(p.next(), isTrue);
      expect(p.busy, isTrue);
      expect(p.add([r(2), r(3)]), isFalse, reason: 'mid-throw: wait');
      expect(p.current!.seq, 1);
      expect(p.settled(1), isTrue);
      expect(p.busy, isTrue, reason: 'more queued: stay locked');
      expect(p.rested(), isTrue);
      p.next();
      expect(p.current!.seq, 2);
      expect(p.settled(99), isFalse, reason: 'stale report ignored');
      p.settled(2);
      p.rested();
      p.next();
      expect(p.current!.seq, 3);
      expect(p.serial, 3);
      p.settled(3);
      expect(p.busy, isFalse, reason: 'last one landed: unlock at once');
      expect(p.resting, isTrue);
      expect(p.rested(), isFalse);
      expect(p.busy || p.resting, isFalse);
    });

    test(
      'a roll arriving while the last result is on show waits the dwell',
      () {
        final p = RollPlayback()..add([r(1)]);
        p.next();
        p.settled(1);
        expect(p.add([r(2)]), isFalse);
        expect(p.busy, isTrue);
        expect(p.rested(), isTrue);
        p.next();
        expect(p.current!.seq, 2);
      },
    );
  });

  group('OnlineTable playback', () {
    late SfxService sfx;
    setUp(() => sfx = SfxService(hapticsEnabled: false));

    DiceTrayState tray(WidgetTester t) =>
        t.state<DiceTrayState>(find.byType(DiceTray));
    List<int> faces(WidgetTester t) =>
        t.widget<DiceTray>(find.byType(DiceTray)).values;

    testWidgets(
      'payout line vanishing in the roll snapshot no longer re-creates the tray (both seats)',
      (t) async {
        for (final seat in [0, 1]) {
          final h = GlobalKey<HarnessState>();
          await t.pumpWidget(
            Harness(
              key: h,
              sfx: sfx,
              initial: room(
                version: 1,
                turnSeat: seat,
                roll: 0,
                payout: 'Op whiffs — 2 gems to the pot.',
                recent: [
                  rollMap(3, 1 - seat, [2, 4, 6], 3),
                ],
              ),
            ),
          );
          await t.pumpAndSettle();
          final before = tray(t);
          h.currentState!.push(
            room(
              version: 2,
              turnSeat: seat,
              recent: [
                rollMap(3, 1 - seat, [2, 4, 6], 3),
                rollMap(4, seat, [5, 5, 1]),
              ],
            ),
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 50));
          expect(identical(tray(t), before), isTrue, reason: 'seat $seat');
          expect(tray(t).settling, isTrue, reason: 'seat $seat roll tumbles');
          await t.pumpAndSettle();
          await t.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('a whiff that puts the payout line up still tumbles', (
      t,
    ) async {
      final h = GlobalKey<HarnessState>();
      await t.pumpWidget(
        Harness(
          key: h,
          sfx: sfx,
          initial: room(
            version: 1,
            turnSeat: 1,
            roll: 2,
            recent: [
              rollMap(2, 1, [2, 4, 6], 2),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      h.currentState!.push(
        room(
          version: 2,
          turnSeat: 0,
          roll: 0,
          payout: 'Op whiffs — 2 gems to the pot.',
          recent: [
            rollMap(2, 1, [2, 4, 6], 2),
            rollMap(3, 1, [2, 4, 5], 3),
          ],
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(tray(t).settling, isTrue);
      expect(faces(t), [2, 4, 5]);
      await t.pumpAndSettle();
    });

    testWidgets(
      'coalesced auto-play set: each roll throws in order, faces held between',
      (t) async {
        final h = GlobalKey<HarnessState>();
        await t.pumpWidget(
          Harness(
            key: h,
            sfx: sfx,
            initial: room(
              version: 1,
              turnSeat: 1,
              roll: 0,
              recent: [
                rollMap(1, 0, [3, 3, 1]),
              ],
            ),
          ),
        );
        await t.pumpAndSettle();
        h.currentState!.push(
          room(
            version: 2,
            turnSeat: 0,
            roll: 0,
            payout: 'Op whiffs — 2 gems to the pot.',
            recent: [
              rollMap(1, 0, [3, 3, 1]),
              rollMap(2, 1, [1, 2, 4]),
              rollMap(3, 1, [1, 2, 5], 2),
              rollMap(4, 1, [6, 2, 5], 3),
            ],
          ),
        );
        final seen = <List<int>>[];
        final serials = <int>[];
        for (var i = 0; i < 80; i++) {
          await t.pump(const Duration(milliseconds: 100));
          final s = t.widget<DiceTray>(find.byType(DiceTray)).rollSerial;
          if (serials.isEmpty || serials.last != s) {
            serials.add(s);
            seen.add(faces(t));
          }
        }
        expect(serials, [1, 2, 3]);
        expect(seen, [
          [1, 2, 4],
          [1, 2, 5],
          [6, 2, 5],
        ]);
        await t.pumpAndSettle();
      },
    );

    testWidgets('a roll arriving mid-throw is queued, not cut short', (
      t,
    ) async {
      final h = GlobalKey<HarnessState>();
      await t.pumpWidget(
        Harness(
          key: h,
          sfx: sfx,
          initial: room(
            version: 1,
            turnSeat: 1,
            roll: 0,
            recent: [
              rollMap(1, 0, [3, 3, 1]),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      h.currentState!.push(
        room(
          version: 2,
          turnSeat: 1,
          recent: [
            rollMap(1, 0, [3, 3, 1]),
            rollMap(2, 1, [1, 2, 4]),
          ],
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      h.currentState!.push(
        room(
          version: 3,
          turnSeat: 1,
          roll: 2,
          recent: [
            rollMap(1, 0, [3, 3, 1]),
            rollMap(2, 1, [1, 2, 4]),
            rollMap(3, 1, [1, 2, 6], 2),
          ],
        ),
      );
      await t.pump();
      expect(t.widget<DiceTray>(find.byType(DiceTray)).rollSerial, 1);
      expect(faces(t), [1, 2, 4], reason: 'first throw keeps its faces');
      await t.pump(const Duration(milliseconds: DiceTray.dieMs));
      expect(
        t.widget<DiceTray>(find.byType(DiceTray)).rollSerial,
        1,
        reason: 'result on show',
      );
      await t.pump(RollPlayback.dwell);
      await t.pump();
      expect(t.widget<DiceTray>(find.byType(DiceTray)).rollSerial, 2);
      expect(faces(t), [1, 2, 6]);
      await t.pumpAndSettle();
    });
  });

  test(
    'leaver row: 100 → 97 (−3) · left; bust stays out; old rooms fall back',
    () {
      MatchView mv(Map<String, dynamic> s1) => MatchView.fromMap({
        'status': 'finished',
        'pot': 0,
        'round': 3,
        'winnerSeat': 0,
        'startBanks': [100, 100],
        'seats': [
          {
            'index': 0,
            'kind': 'host',
            'uid': 'me',
            'displayName': 'Jerilyn',
            'bank': 166,
          },
          {
            'index': 1,
            'kind': 'human',
            'uid': 'bt',
            'displayName': 'Box Tester',
            ...s1,
          },
        ],
      });
      final left = mv({
        'bank': 0,
        'eliminated': true,
        'left': true,
        'leftWith': 97,
      }).results()[1];
      expect(
        '${left.start} → ${left.end} gems${left.statusSuffix}',
        '100 → 97 gems · left',
      );
      expect(left.changeLabel, '−3');
      expect(left.out, isFalse);
      final bust = mv({'bank': 0, 'eliminated': true}).results()[1];
      expect(bust.statusSuffix, ' · out');
      expect(bust.end, 0);
      final deleted = mv({
        'bank': 0,
        'eliminated': true,
        'left': true,
        'leftWith': 0,
      }).results()[1];
      expect(deleted.statusSuffix, ' · left');
      expect(deleted.end, 0);
    },
  );
}
