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
  size: const Size(360, 160),
);

List<double> poses(WidgetTester t) => [
  for (final c in t.widgetList<DiceCube>(find.byType(DiceCube))) c.rx + c.ry,
];

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
    final keptPos = tester.getCenter(find.byKey(const ValueKey('die-cube-1')));
    await tester.pumpWidget(tray(serial: 1, sfx: sfx, onSettled: settled.add));
    expect(cues, [SfxCue.cupRattle]);
    for (var ms = 0; ms < 3200; ms += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester
            .widgetList<DiceCube>(
              find.byKey(const ValueKey('die-cube-0')).evaluate().isEmpty
                  ? find.byType(DiceCube)
                  : find.descendant(
                      of: find.byKey(const ValueKey('die-cube-0')),
                      matching: find.byType(DiceCube),
                    ),
            )
            .map((c) => c.value)
            .toSet(),
        {2},
      );
      // Kept die (index 1) never moves (only the 4–6 dp table shake).
      final d =
          tester.getCenter(find.byKey(const ValueKey('die-cube-1'))) - keptPos;
      expect(d.distance, lessThan(8));
    }
    expect(cues.where((c) => c == SfxCue.dieClack).length, 2); // 2 movers
    expect(tester.getCenter(find.byKey(const ValueKey('die-cube-1'))), keptPos);
    expect(settled, [1]);
    expect(poses(tester).toSet(), {DiceCube.restRx + DiceCube.restRy});
  });

  testWidgets('input locked until settle', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(tray(serial: 0, onTap: taps.add));
    await tester.pumpWidget(tray(serial: 1, onTap: taps.add));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('die-0')), warnIfMissed: false);
    expect(taps, isEmpty);
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('die-0')));
    expect(taps, [0]);
  });

  testWidgets('kept dice show the gold outline and stay still', (tester) async {
    await tester.pumpWidget(tray(serial: 0));
    expect(find.byKey(const ValueKey('kept-outline')), findsOneWidget);
  });

  testWidgets('Reduce Motion: 250 ms fade + drop, no throw', (tester) async {
    final settled = <int>[];
    await tester.pumpWidget(
      tray(serial: 0, reduceMotion: true, onSettled: settled.add),
    );
    final rest = poses(tester);
    final spot = tester.getCenter(find.byKey(const ValueKey('die-0')));
    await tester.pumpWidget(
      tray(serial: 1, reduceMotion: true, onSettled: settled.add),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(poses(tester), rest); // orientation never leaves the result
    expect(find.byKey(const ValueKey('ghost-0-0')), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(settled, [1]);
    // Final spot = its holding spot; no shake/zoom layers.
    expect(tester.getCenter(find.byKey(const ValueKey('die-0'))), spot);
    expect(find.byKey(const ValueKey('big-vignette')), findsNothing);
  });

  testWidgets('golden: settled dice frame', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(tray(serial: 0));
    await tester.pumpWidget(tray(serial: 1));
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    } // settled
    expect(tester.hasRunningAnimations, isFalse);
    await expectLater(
      find.byKey(const ValueKey('tray')),
      matchesGoldenFile('goldens/dice_settled.png'),
    );
  });
}
