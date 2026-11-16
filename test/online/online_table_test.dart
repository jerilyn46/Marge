import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/online/room_models.dart';
import 'package:marge/services/sfx_service.dart';
import 'package:marge/ui/screens/online_match_screen.dart';
import 'package:marge/ui/visuals/dice_3d.dart';

Room room({
  required int version,
  required int turnSeat,
  int roll = 0,
  int? rollSeq,
  List<int> dice = const [2, 3, 6],
  int lastSeat = 1,
}) => Room.fromMap('r1', {
  'code': 'EE7LWC',
  'hostUid': 'me',
  'status': 'playing',
  'ante': 10,
  'version': version,
  'memberUids': ['me', 'op'],
  'seats': [
    {'index': 0, 'kind': 'host', 'uid': 'me'},
    {'index': 1, 'kind': 'human', 'uid': 'op'},
  ],
  'match': {
    'status': 'playing',
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
    'turn': {
      'seat': turnSeat,
      'rollNumber': roll,
      'setNumber': 1,
      'dice': roll > 0 ? dice : [1, 1, 1],
      'kept': [false, false, false],
    },
    'rollSeq': ?rollSeq,
    if (rollSeq != null)
      'lastRoll': {
        'seq': rollSeq,
        'seat': lastSeat,
        'dice': dice,
        'held': [false, false, false],
        'rollNumber': roll == 0 ? 3 : roll,
      },
  },
});

class Harness extends StatefulWidget {
  const Harness({super.key, required this.initial, required this.sfx});
  final Room initial;
  final SfxService sfx;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late Room room = widget.initial;
  void push(Room r) => setState(() => room = r);
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: OnlineTable(
        room: room,
        myUid: 'me',
        sfx: widget.sfx,
        onRoll: (_) {},
        onBank: () {},
      ),
    ),
  );
}

void main() {
  late List<SfxCue> cues;
  late SfxService sfx;
  setUp(() {
    cues = [];
    sfx = SfxService(hapticsEnabled: false)..debugOnCue = cues.add;
  });

  int traySerial(WidgetTester t) =>
      t.widget<DiceTray>(find.byType(DiceTray)).rollSerial;
  int rattles() => cues.where((c) => c == SfxCue.cupRattle).length;

  testWidgets(
    'opponent roll animates once; initial load and reconnect do not',
    (t) async {
      final h = GlobalKey<HarnessState>();
      await t.pumpWidget(
        Harness(
          key: h,
          sfx: sfx,
          initial: room(version: 5, turnSeat: 1, roll: 1, rollSeq: 4),
        ),
      );
      await t.pumpAndSettle();
      expect(traySerial(t), 0, reason: 'initial load never replays a roll');
      expect(rattles(), 0);

      // Opponent rolls again (server-confirmed).
      h.currentState!.push(
        room(version: 6, turnSeat: 1, roll: 2, rollSeq: 5, dice: [4, 4, 1]),
      );
      await t.pump();
      expect(traySerial(t), 1);
      expect(rattles(), 1, reason: 'throw sound hook fires for the opponent');
      await t.pumpAndSettle();

      // Reconnect / resubscribe re-delivers the same snapshot (new object).
      h.currentState!.push(
        room(version: 6, turnSeat: 1, roll: 2, rollSeq: 5, dice: [4, 4, 1]),
      );
      await t.pumpAndSettle();
      expect(traySerial(t), 1, reason: 'no double-fire on resubscribe');
      expect(rattles(), 1);
    },
  );

  testWidgets(
    'timeout auto-play / 3rd-roll miss that passes the turn still animates, '
    'and the Your turn banner shows once',
    (t) async {
      final h = GlobalKey<HarnessState>();
      await t.pumpWidget(
        Harness(
          key: h,
          sfx: sfx,
          initial: room(version: 1, turnSeat: 1, rollSeq: 2),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('online-your-turn-banner')),
        findsNothing,
      );

      // Server auto-played the opponent's set; the turn is now mine at roll 0.
      h.currentState!.push(
        room(version: 2, turnSeat: 0, rollSeq: 5, dice: [5, 2, 3]),
      );
      await t.pump();
      expect(traySerial(t), 1);
      expect(cues, contains(SfxCue.yourTurn));
      expect(
        find.byKey(const ValueKey('online-your-turn-banner')),
        findsOneWidget,
      );
      // Last roll's faces are on the table (not the reset 1-1-1).
      expect(t.widget<DiceTray>(find.byType(DiceTray)).values, [5, 2, 3]);
      await t.pumpAndSettle();
      await t.pump(OnlineTable.bannerDuration);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('online-your-turn-banner')),
        findsNothing,
      );
      expect(cues.where((c) => c == SfxCue.yourTurn).length, 1);
    },
  );

  testWidgets('my roll: buttons lock while the dice settle, holds tap after', (
    t,
  ) async {
    final h = GlobalKey<HarnessState>();
    await t.pumpWidget(
      Harness(key: h, sfx: sfx, initial: room(version: 1, turnSeat: 0)),
    );
    await t.pumpAndSettle();
    final rollBtn = find.byKey(const ValueKey('online-roll'));
    expect(t.widget<ElevatedButton>(rollBtn).onPressed, isNotNull);

    h.currentState!.push(
      room(version: 2, turnSeat: 0, roll: 1, rollSeq: 1, lastSeat: 0),
    );
    await t.pump();
    expect(
      t.widget<ElevatedButton>(rollBtn).onPressed,
      isNull,
      reason: 'locked mid-tumble',
    );
    await t.pumpAndSettle();
    expect(t.widget<ElevatedButton>(rollBtn).onPressed, isNotNull);
    expect(t.widget<DiceTray>(find.byType(DiceTray)).enabled, [
      true,
      true,
      true,
    ]);
  });
}
