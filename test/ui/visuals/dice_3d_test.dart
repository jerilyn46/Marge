import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/sfx_service.dart';
import 'package:marge/ui/visuals/dice_3d.dart';

import 'visual_test_utils.dart';

Widget tray({
  required int serial,
  List<int> values = const [2, 5, 6],
  List<bool> kept = const [false, true, false],
  List<bool>? animate,
  SfxService? sfx,
  ValueChanged<int>? onSettled,
  ValueChanged<int>? onTap,
  bool reduceMotion = false,
}) => feltHost(
  DiceTray(
    key: const ValueKey('tray'),
    values: values,
    kept: kept,
    animate: animate ?? [for (final k in kept) !k],
    enabled: const [true, true, true],
    rollSerial: serial,
    sfx: sfx,
    onSettled: onSettled,
    onTap: onTap,
  ),
  reduceMotion: reduceMotion,
  size: const Size(360, 280),
);

void main() {
  test('cube faces: result in front, opposite faces sum to 7', () {
    for (var v = 1; v <= 6; v++) {
      final faces = DiceCube.facesFor(v, 10).map((f) => f.$1).toList();
      expect(faces.first, v);
      expect(faces.toSet(), {1, 2, 3, 4, 5, 6});
      expect(faces[0] + faces[1], 7);
      expect(faces[2] + faces[3], 7);
      expect(faces[4] + faces[5], 7);
    }
  });

  testWidgets('result decided first: faces never change, settles', (
    tester,
  ) async {
    final cues = <SfxCue>[];
    final sfx = SfxService(hapticsEnabled: false)..debugOnCue = cues.add;
    final settled = <int>[];
    await tester.pumpWidget(tray(serial: 0, sfx: sfx, onSettled: settled.add));
    DiceTrayState st() => tester.state<DiceTrayState>(find.byType(DiceTray));
    final keptPos = st().debugCenters[1];
    await tester.pumpWidget(tray(serial: 1, sfx: sfx, onSettled: settled.add));
    expect(cues, [SfxCue.cupRattle]);
    for (var ms = 0; ms < 2300; ms += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(st().debugValues, [2, 5, 6]); // always the engine result
      expect(st().debugCenters[1], keptPos); // kept die never moves
    }
    expect(st().settling, isFalse);
    expect(cues.where((c) => c == SfxCue.dieClack).length, 2); // 2 movers
    expect(settled, [1]);
    expect(st().debugFrontFaces, [2, 5, 6]);
  });

  testWidgets('input locked until settle', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(tray(serial: 0, onTap: taps.add));
    await tester.pumpWidget(tray(serial: 1, onTap: taps.add));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('die-0')), warnIfMissed: false);
    expect(taps, isEmpty);
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('die-0')));
    expect(taps, [0]);
  });

  testWidgets('kept dice show the gold outline and stay still', (tester) async {
    await tester.pumpWidget(tray(serial: 0));
    expect(
      tester.state<DiceTrayState>(find.byType(DiceTray)).debugKeptOutline,
      [false, true, false],
    );
  });

  testWidgets('one CustomPainter inside a RepaintBoundary draws the dice', (
    tester,
  ) async {
    await tester.pumpWidget(tray(serial: 0));
    await tester.pumpWidget(tray(serial: 1));
    await tester.pump(const Duration(milliseconds: 300));
    final paint = find.byKey(const ValueKey('dice-table-painter'));
    expect(paint, findsOneWidget);
    expect(
      find.ancestor(of: paint, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    expect(find.byType(DiceCube), findsNothing); // no per-die widgets
    // Mid-throw frames repaint without rebuilding the tray.
    final st = tester.state<DiceTrayState>(find.byType(DiceTray));
    final builds = st.debugBuilds;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(st.debugBuilds, builds);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets('Reduce Motion: 250 ms fade + drop, no throw', (tester) async {
    final settled = <int>[];
    await tester.pumpWidget(
      tray(serial: 0, reduceMotion: true, onSettled: settled.add),
    );
    DiceTrayState st() => tester.state<DiceTrayState>(find.byType(DiceTray));
    final spot = tester.getCenter(find.byKey(const ValueKey('die-0')));
    await tester.pumpWidget(
      tray(serial: 1, reduceMotion: true, onSettled: settled.add),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(st().debugFrontFaces, [2, 5, 6]); // never leaves the result pose
    await tester.pump(const Duration(milliseconds: 200));
    expect(settled, [1]);
    expect(tester.getCenter(find.byKey(const ValueKey('die-0'))), spot);
  });

  testWidgets('golden: settled dice frame', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(tray(serial: 0));
    await tester.pumpWidget(tray(serial: 1));
    for (var i = 0; i < 23; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    } // settled
    final st = tester.state<DiceTrayState>(find.byType(DiceTray));
    final b = st.debugBounds;
    final table = Offset.zero & st.debugTable;
    for (var i = 0; i < 3; i++) {
      // Every die fully visible...
      expect(
        table.contains(b[i].topLeft) && table.contains(b[i].bottomRight),
        isTrue,
        reason: 'die $i ${b[i]} in $table',
      );
      // ...and none overlap on screen.
      for (var j = i + 1; j < 3; j++) {
        expect(b[i].overlaps(b[j]), isFalse, reason: 'dice $i/$j');
      }
    }
    expect(tester.hasRunningAnimations, isFalse);
    await expectLater(
      find.byKey(const ValueKey('tray')),
      matchesGoldenFile('goldens/dice_settled.png'),
    );
  });
}
