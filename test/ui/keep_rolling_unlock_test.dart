import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/visuals/dice_3d.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Scripted implements Random {
  _Scripted(this.seq);
  final List<int> seq;
  int i = 0;
  @override
  int nextInt(int max) => seq[i++ % seq.length] % max;
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
}

class _Live extends MatchNotifier {
  _Live(this._first);
  final MatchViewState _first;
  @override
  MatchViewState? build() => _first;
  void show(MatchViewState v) => state = v;
}

/// Jerilyn's table: her fresh turn (a celebratory banner from the last
/// beat still up), then she rolls 3, 3, 1 on roll 1 — no score, 2 left.
(MatchViewState, MatchViewState) _tables() {
  final c = MatchController(
    config: const MatchConfig(botCount: 1),
    rng: _Scripted([2, 2, 0, 0, 0, 0, 2, 2, 0]),
  );
  c.startMatch();
  c.roll(); // 3,3,1
  c.roll(); // 1,1,1 on roll 2: triple-ones pay (celebratory)
  c.bank(); // same seat, fresh 3 rolls
  final before = c.snapshot;
  expect(before.lastPayout?.celebratory, isTrue);
  expect(before.turn!.hasRolled, isFalse);
  c.roll(); // 3,3,1
  final after = c.snapshot;
  expect(after.turn!.dice.values, [3, 3, 1]);
  expect(after.turn!.lastScore.kind, ScoreKind.none);
  expect(after.turn!.mustKeepRolling, isTrue);
  return (
    MatchViewState(snapshot: before, rollSerial: 0),
    MatchViewState(snapshot: after, rollSerial: 1),
  );
}

ElevatedButton _keepRolling(WidgetTester t) => t.widget<ElevatedButton>(
  find.ancestor(
    of: find.textContaining('KEEP ROLLING'),
    matching: find.byType(ElevatedButton),
  ),
);

Future<_Live> _mount(
  WidgetTester tester,
  MatchViewState first,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  late _Live live;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [matchProvider.overrideWith(() => live = _Live(first))],
      child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return live;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    '3-3-1 on roll 1: KEEP ROLLING re-enables after the dice settle',
    (tester) async {
      final (before, after) = _tables();
      final live = await _mount(tester, before, const Size(390, 760));
      live.show(after);
      await tester.pump();
      expect(_keepRolling(tester).onPressed, isNull); // locked mid-throw
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(_keepRolling(tester).onPressed, isNotNull);
    },
  );

  testWidgets('unfold (resize to the Flip 7 main screen) mid-roll', (
    tester,
  ) async {
    final (before, after) = _tables();
    final live = await _mount(tester, before, const Size(360, 700));
    live.show(after);
    await tester.pump(const Duration(milliseconds: 120));
    // Cover -> main screen: 1080x2520 px at ~2.625 dpr.
    await tester.binding.setSurfaceSize(const Size(411, 960));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(_keepRolling(tester).onPressed, isNotNull);
    // And back to the cover screen.
    live.show(MatchViewState(snapshot: after.snapshot, rollSerial: 1));
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pump(const Duration(seconds: 3));
    expect(_keepRolling(tester).onPressed, isNotNull);
  });

  // Guards the tray key alone: the banner rows above the tray change on the
  // roll frame; the tray must keep its State (and its throw) across that.
  testWidgets('tray key: same DiceTray State across the roll frame', (
    tester,
  ) async {
    final (before, after) = _tables();
    final live = await _mount(tester, before, const Size(390, 760));
    final s0 = tester.state(find.byType(DiceTray));
    live.show(after);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(identical(tester.state(find.byType(DiceTray)), s0), isTrue);
  });

  // Guards the settled-on-mount report alone: a tray force-mounted mid-throw
  // (new key) must still report the current roll as settled.
  testWidgets('settled-on-mount: a tray re-created mid-throw reports settled', (
    tester,
  ) async {
    final settled = <int>[];
    Widget tray(int serial, String key) => MaterialApp(
      home: Center(
        child: DiceTray(
          key: ValueKey(key),
          values: const [3, 3, 1],
          kept: const [false, false, false],
          animate: const [true, true, true],
          rollSerial: serial,
          onSettled: settled.add,
        ),
      ),
    );
    await tester.pumpWidget(tray(0, 'a'));
    await tester.pump();
    await tester.pumpWidget(tray(1, 'a'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(settled.contains(1), isFalse); // mid-throw
    await tester.pumpWidget(tray(1, 'b')); // re-created
    await tester.pump();
    await tester.pump();
    expect(settled.last, 1);
  });

  // Safety net: an idle tray re-reports its current roll on the next build
  // if the settle report could not be delivered (no listener at the time).
  testWidgets('idle tray re-reports a settle that had no listener', (
    tester,
  ) async {
    final settled = <int>[];
    Widget tray(int serial, {required bool listen}) => MaterialApp(
      home: Center(
        child: DiceTray(
          key: const ValueKey('t'),
          values: const [4, 6, 6],
          kept: const [false, false, false],
          animate: const [true, true, true],
          rollSerial: serial,
          onSettled: listen ? settled.add : null,
        ),
      ),
    );
    await tester.pumpWidget(tray(0, listen: true));
    await tester.pump();
    await tester.pumpWidget(tray(1, listen: false)); // throw, nobody listening
    await tester.pump(const Duration(seconds: 2));
    expect(settled, [0]);
    await tester.pumpWidget(tray(1, listen: true)); // still, idle
    await tester.pump();
    expect(settled, [0, 1]);
  });
}
