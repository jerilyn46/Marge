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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const sizes = {
    'Flip 7 cover 926x820 px @ ~2.6': Size(356, 315),
    'Flip 7 cover landscape-ish': Size(463, 410),
    '360x640': Size(360, 640),
    '320x568': Size(320, 568),
  };
  for (final e in sizes.entries) {
    testWidgets('short screen ${e.key}: dice + action fully visible', (
      tester,
    ) async {
      final (_, after) = _tables();
      await _mount(tester, after, e.value);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final screen = Offset.zero & e.value;
      final btn = find.ancestor(
        of: find.textContaining('KEEP ROLLING'),
        matching: find.byType(ElevatedButton),
      );
      final b = tester.getRect(btn);
      expect(
        screen.contains(b.topLeft) &&
            screen.contains(b.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
        reason: 'button $b on $screen',
      );
      expect(_keepRolling(tester).onPressed, isNotNull);
      final tray = tester.getRect(find.byKey(const ValueKey('dice-tray')));
      // Scroll the table so the dice are in view, if needed.
      if (tray.bottom > b.top) {
        await tester.drag(
          find.byKey(const ValueKey('table-scroll')),
          const Offset(0, -400),
        );
        await tester.pump();
      }
      final t2 = tester.getRect(find.byKey(const ValueKey('dice-tray')));
      expect(
        t2.top >= 0 && t2.bottom <= b.top + 0.5,
        isTrue,
        reason: 'dice $t2 above pinned button $b',
      );
    });
  }
}
