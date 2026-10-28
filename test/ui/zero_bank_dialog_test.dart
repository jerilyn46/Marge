import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/widgets/gem_shortfall_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Dice implements Random {
  _Dice(this.seq);
  List<int> seq;
  int i = 0;
  void next(List<int> s) {
    seq = s;
    i = 0;
  }

  @override
  int nextInt(int max) => seq[i++ % seq.length] % max;
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
}

const kZeroBankBody =
    'You paid out everything you had at this table. Add 10 gems to stay in, '
    'or quit — if you’re the last one out, the other player takes the pot.';

/// Hotseat: Player 2 paid out their last 8 gems → zeroBank pending.
MatchSnapshot _zeroBankSnapshot() {
  final d = _Dice([2, 2, 0]);
  final c = MatchController(
    config: const MatchConfig(
      botCount: 0,
      otherHumanCount: 1,
      localPlayerName: 'Jerilyn',
    ),
    rng: d,
  )..startMatch();
  final other = c.snapshot.players.indexWhere(
    (p) => !p.profile.isBot && p.profile.id != 'human_0',
  );
  c.debugSetBank(other, 8);
  c.roll();
  d.next([0, 0, 0]);
  c.roll();
  if (c.snapshot.phase != MatchPhase.awaitingShortfall) c.bank();
  final s = c.snapshot;
  expect(s.pendingShortfall!.zeroBank, isTrue);
  return s;
}

class _FakeMatch extends MatchNotifier {
  _FakeMatch(this.snap);
  final MatchSnapshot snap;
  int quits = 0;
  int covers = 0;
  @override
  MatchViewState? build() => MatchViewState(snapshot: snap);
  @override
  void quitShortfall() => quits++;
  @override
  bool coverShortfall() {
    covers++;
    return true;
  }
}

Future<_FakeMatch> _pump(WidgetTester tester, {double textScale = 1}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  PlayerCoinLedger.bootstrap = PlayerCoinLedger(
    balances: {'human:Jerilyn': 100},
    loaded: true,
    prefs: prefs,
  );
  SettingsNotifier.bootstrap = GameSettings(
    playerName: 'Jerilyn',
    hasUsername: true,
    loaded: true,
    sfxEnabled: false,
    hapticsEnabled: false,
  );
  addTearDown(() {
    PlayerCoinLedger.bootstrap = null;
    SettingsNotifier.bootstrap = null;
  });
  final snap = _zeroBankSnapshot();
  final fake = _FakeMatch(snap);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [matchProvider.overrideWith(() => fake)],
      child: MaterialApp(
        theme: buildMargeTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(textScale)),
                      child: GemShortfallDialog(
                        shortfall: snap.pendingShortfall!,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('zeroBank: exact title and body, no gem bank line', (t) async {
    await _pump(t);
    expect(find.text('Out of gems'), findsOneWidget);
    expect(find.text(kZeroBankBody), findsOneWidget);
    expect(find.textContaining('Gem bank has'), findsNothing);
  });

  testWidgets('zeroBank: both buttons, exact labels, wired', (t) async {
    final fake = await _pump(t);
    expect(find.widgetWithText(TextButton, 'Quit this game'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Add 10 and keep playing'),
      findsOneWidget,
    );
    expect(find.textContaining('Add 10 gems and keep'), findsNothing);
    final add = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add 10 and keep playing'),
    );
    expect(add.onPressed, isNotNull);
    await t.tap(find.text('Add 10 and keep playing'));
    await t.pumpAndSettle();
    expect(fake.covers, 1);
  });

  testWidgets('zeroBank: quit button calls quitShortfall', (t) async {
    final fake = await _pump(t);
    await t.tap(find.text('Quit this game'));
    await t.pumpAndSettle();
    expect(fake.quits, 1);
  });

  for (final size in const [Size(360, 640), Size(320, 568)]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('zeroBank fits ${size.width}x${size.height} @${scale}x', (
        t,
      ) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await _pump(t, textScale: scale);
        expect(t.takeException(), isNull);
        expect(find.text('Out of gems'), findsOneWidget);
        expect(find.text('Quit this game'), findsOneWidget);
        expect(find.text('Add 10 and keep playing'), findsOneWidget);
        final dialog = t.getRect(find.byType(AlertDialog));
        expect(dialog.bottom, lessThanOrEqualTo(size.height));
        expect(dialog.right, lessThanOrEqualTo(size.width));
      });
    }
  }
}
