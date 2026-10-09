import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/services/sfx_service.dart';
import 'package:marge/ui/visuals/dice_3d.dart';
import 'package:marge/ui/widgets/die_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_test_utils.dart';

Widget tray({
  required int serial,
  bool lite = true,
  bool reduceMotion = false,
  SfxService? sfx,
  ValueChanged<int>? onSettled,
  ValueChanged<int>? onTap,
}) => feltHost(
  DiceTray(
    key: const ValueKey('tray'),
    values: const [2, 5, 6],
    kept: const [false, true, false],
    animate: const [true, false, true],
    enabled: const [true, true, true],
    rollSerial: serial,
    sfx: sfx,
    onSettled: onSettled,
    onTap: onTap,
    lite: lite,
  ),
  reduceMotion: reduceMotion,
  size: const Size(360, 160),
);

void main() {
  testWidgets('lite: flat faces while tumbling, no cube, same timeline', (
    tester,
  ) async {
    final cues = <SfxCue>[];
    final sfx = SfxService(hapticsEnabled: false)..debugOnCue = cues.add;
    final settled = <int>[];
    await tester.pumpWidget(tray(serial: 0, sfx: sfx, onSettled: settled.add));
    await tester.pumpWidget(tray(serial: 1, sfx: sfx, onSettled: settled.add));
    await tester.pump(const Duration(milliseconds: 300));
    // Movers are one flat face each; the kept die stays a still cube.
    expect(find.byKey(const ValueKey('lite-face-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('lite-face-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('lite-face-1')), findsNothing);
    expect(find.byType(DiceCube), findsOneWidget);
    // Lands on the decided result before settle.
    await tester.pump(const Duration(milliseconds: 450)); // 750 ms
    final faces = tester
        .widgetList<DieFace>(
          find.byWidgetPredicate(
            (w) =>
                w is DieFace &&
                (w.key == const ValueKey('lite-face-0') ||
                    w.key == const ValueKey('lite-face-2')),
          ),
        )
        .map((f) => f.value)
        .toList();
    expect(faces, [2, 6]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(settled, [1]);
    // Settled: same cubes as the full path.
    expect(
      tester.widgetList<DiceCube>(find.byType(DiceCube)).map((c) => c.value),
      [2, 5, 6],
    );
    expect(cues.where((c) => c == SfxCue.cupRattle).length, 1);
    expect(cues.where((c) => c == SfxCue.dieClack).length, 2);
  });

  testWidgets('lite: input still locked until settle', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(tray(serial: 0, onTap: taps.add));
    await tester.pumpWidget(tray(serial: 1, onTap: taps.add));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('die-0')), warnIfMissed: false);
    expect(taps, isEmpty);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('die-0')));
    expect(taps, [0]);
  });

  testWidgets('Reduce Motion beats lite: 200 ms fade, no flat tumble', (
    tester,
  ) async {
    await tester.pumpWidget(tray(serial: 0, reduceMotion: true));
    await tester.pumpWidget(tray(serial: 1, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('lite-face-0')), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.hasRunningAnimations, isFalse);
  });

  test('Simple dice setting persists', () async {
    SharedPreferences.setMockInitialValues({'lite_dice': true});
    final s = await SettingsNotifier.load();
    expect(s.liteDice, isTrue);
    SharedPreferences.setMockInitialValues({});
    expect((await SettingsNotifier.load()).liteDice, isFalse);
  });

  testWidgets('golden: lite dice mid-tumble', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(tray(serial: 0));
    await tester.pumpWidget(tray(serial: 1));
    await tester.pump(const Duration(milliseconds: 360));
    await expectLater(
      find.byKey(const ValueKey('tray')),
      matchesGoldenFile('goldens/dice_lite_tumble.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });
}
