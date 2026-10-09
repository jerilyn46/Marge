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

  testWidgets('result decided first: faces never change, land at 650 ms', (
    tester,
  ) async {
    final cues = <SfxCue>[];
    final sfx = SfxService(hapticsEnabled: false)..debugOnCue = cues.add;
    final settled = <int>[];
    await tester.pumpWidget(tray(serial: 0, sfx: sfx, onSettled: settled.add));
    final rest = poses(tester);
    await tester.pumpWidget(tray(serial: 1, sfx: sfx, onSettled: settled.add));
    expect(cues, [SfxCue.cupRattle]);
    for (var ms = 0; ms < 1000; ms += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      // The value shown is always the engine result.
      expect(
        tester.widgetList<DiceCube>(find.byType(DiceCube)).map((c) => c.value),
        [2, 5, 6],
      );
      final p = poses(tester);
      // Kept die (index 1) never moves.
      expect(p[1], rest[1]);
      if (ms == 300) expect(p[0], isNot(rest[0])); // tumbling
    }
    expect(poses(tester), rest); // landed exactly on the result pose
    expect(cues.where((c) => c == SfxCue.dieClack).length, 2); // 2 movers
    expect(settled, [1]);
  });

  testWidgets('input locked until settle', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(tray(serial: 0, onTap: taps.add));
    await tester.pumpWidget(tray(serial: 1, onTap: taps.add));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('die-0')));
    expect(taps, isEmpty);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('die-0')));
    expect(taps, [0]);
  });

  testWidgets('kept dice show the gold outline and stay still', (tester) async {
    await tester.pumpWidget(tray(serial: 0));
    expect(find.byKey(const ValueKey('kept-outline')), findsOneWidget);
  });

  testWidgets('Reduce Motion: 200 ms fade/scale, no tumble', (tester) async {
    final settled = <int>[];
    await tester.pumpWidget(
      tray(serial: 0, reduceMotion: true, onSettled: settled.add),
    );
    final rest = poses(tester);
    await tester.pumpWidget(
      tray(serial: 1, reduceMotion: true, onSettled: settled.add),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(poses(tester), rest); // orientation never leaves the result
    await tester.pump(const Duration(milliseconds: 150));
    expect(settled, [1]);
  });

  testWidgets('golden: settled dice frame', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(tray(serial: 0));
    await tester.pumpWidget(tray(serial: 1));
    await tester.pump(const Duration(milliseconds: 1200)); // settled
    expect(tester.hasRunningAnimations, isFalse);
    await expectLater(
      find.byKey(const ValueKey('tray')),
      matchesGoldenFile('goldens/dice_settled.png'),
    );
  });
}
