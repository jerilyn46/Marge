import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

MatchViewState _state(String which) {
  final c = MatchController(
    config: const MatchConfig(botCount: 1),
    rng: _Scripted(which == 'bank' ? [3, 4, 5] : [2, 2, 0]),
  );
  c.startMatch();
  if (which != 'roll') c.roll();
  return MatchViewState(
    snapshot: c.snapshot,
    rollSerial: which == 'roll' ? 0 : 1,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Real Flip 7 cover: 948x1048 px @ 342 ppi, at its three display sizes.
  const covers = {
    '361x399 dp': (2.625),
    '421x466 dp': (2.25),
    '474x524 dp': (2.0),
  };
  const phones = {'360x640': Size(360, 640), '320x568': Size(320, 568)};
  final cases = <(String, Size, double, double)>[
    for (final e in covers.entries)
      for (final s in [1.0, 1.3, 2.0])
        ('Flip 7 cover ${e.key}', const Size(948, 1048) / e.value, e.value, s),
    for (final e in phones.entries)
      for (final s in [1.0, 1.3]) (e.key, e.value, 2.0, s),
  ];
  for (final (name, dp, dpr, scale) in cases) {
    for (final which in ['roll', 'keep', 'bank']) {
      testWidgets('$name text x$scale [$which]: no overflow, action visible', (
        tester,
      ) async {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = dp * dpr;
        // 28 dp status bar, 24 dp nav bar.
        final pad = FakeViewPadding(top: 28 * dpr, bottom: 24 * dpr);
        tester.view.padding = pad;
        tester.view.viewPadding = pad;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final st = _state(which);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [matchProvider.overrideWith(() => _Live(st))],
            child: MaterialApp(
              theme: buildMargeTheme(),
              home: const MatchScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 4));
        expect(tester.takeException(), isNull, reason: 'no overflow');
        final usable = Rect.fromLTRB(0, 28, dp.width, dp.height - 24);
        final Finder btn = switch (which) {
          'roll' => find.ancestor(
            of: find.text('ROLL'),
            matching: find.byType(ElevatedButton),
          ),
          'keep' => find.ancestor(
            of: find.textContaining('KEEP ROLLING'),
            matching: find.byType(ElevatedButton),
          ),
          _ => find.byKey(const ValueKey('bank-only')),
        };
        expect(btn, findsOneWidget);
        final b = tester.getRect(btn);
        expect(
          b.top >= usable.top - 0.5 &&
              b.bottom <= usable.bottom + 0.5 &&
              b.left >= -0.5 &&
              b.right <= usable.right + 0.5,
          isTrue,
          reason: 'button $b in $usable',
        );
        if (which == 'bank') {
          expect((tester.widget(btn) as dynamic).enabled, isTrue);
        } else {
          expect((tester.widget(btn) as ElevatedButton).onPressed, isNotNull);
        }
        // Enabled AND hit-testable at its centre.
        final target = tester.renderObject(btn);
        expect(
          tester
              .hitTestOnBinding(b.center)
              .path
              .any((e) => identical(e.target, target)),
          isTrue,
          reason: 'button hit-testable',
        );
        final tray = tester.getRect(find.byKey(const ValueKey('dice-tray')));
        if (tray.bottom > b.top || tray.top < 0) {
          await tester.ensureVisible(find.byKey(const ValueKey('dice-tray')));
          await tester.pump();
        }
        final t2 = tester.getRect(find.byKey(const ValueKey('dice-tray')));
        expect(
          t2.top >= -0.5 && t2.bottom <= b.top + 0.5,
          isTrue,
          reason: 'dice $t2 above button $b',
        );
        //DIE_BOUNDS
      });
    }
  }

  // Match over (incl. the long first-roll triple 1s message): the results
  // scroll and Continue / Quit stay pinned, visible and tappable.
  final endCases = <(String, Size, double, double)>[
    for (final e in covers.entries)
      for (final s in [1.0, 1.3, 2.0])
        ('Flip 7 cover ${e.key}', const Size(948, 1048) / e.value, e.value, s),
    for (final e in phones.entries)
      for (final s in [1.0, 1.3, 2.0]) (e.key, e.value, 2.0, s),
  ];
  for (final (name, dp, dpr, scale) in endCases) {
    for (final which in ['ones-vs-bot', 'ones-hotseat-5']) {
      testWidgets('$name text x$scale [match over $which]: buttons pinned', (
        tester,
      ) async {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = dp * dpr;
        final pad = FakeViewPadding(top: 28 * dpr, bottom: 24 * dpr);
        tester.view.padding = pad;
        tester.view.viewPadding = pad;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final c = MatchController(
          config: which == 'ones-vs-bot'
              ? const MatchConfig(botCount: 1)
              : const MatchConfig(
                  botCount: 0,
                  otherHumanCount: 4,
                  localPlayerName: 'Jerilyn-Alexandria Roberts',
                ),
          rng: _Scripted([0, 0, 0]),
        )..startMatch();
        c.roll();
        expect(c.snapshot.phase, MatchPhase.matchEnd);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchProvider.overrideWith(
                () => _Live(MatchViewState(snapshot: c.snapshot)),
              ),
            ],
            child: MaterialApp(
              theme: buildMargeTheme(),
              home: const MatchScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: 'no overflow');
        expect(
          find.textContaining('rolled three 1s on the first roll'),
          findsOneWidget,
        );
        final usable = Rect.fromLTRB(0, 28, dp.width, dp.height - 24);
        for (final key in ['match-end-continue', 'match-end-quit']) {
          final btn = find.byKey(ValueKey(key));
          expect(btn, findsOneWidget, reason: key);
          final b = tester.getRect(btn);
          expect(
            b.top >= usable.top - 0.5 &&
                b.bottom <= usable.bottom + 0.5 &&
                b.left >= -0.5 &&
                b.right <= usable.right + 0.5,
            isTrue,
            reason: '$key $b in $usable',
          );
          expect(
            (tester.widget(btn) as ButtonStyleButton).onPressed,
            isNotNull,
          );
          final target = tester.renderObject(btn);
          expect(
            tester
                .hitTestOnBinding(b.center)
                .path
                .any((e) => identical(e.target, target)),
            isTrue,
            reason: '$key hit-testable',
          );
        }
      });
    }
  }
}
