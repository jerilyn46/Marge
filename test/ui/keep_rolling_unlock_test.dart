import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
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
    rng: _Scripted([0, 0, 0, 2, 2, 0]),
  );
  c.startMatch();
  c.roll(); // 1,1,1 first roll: pot sweep, same seat, fresh 3 rolls
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
}
