import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/saved_games.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Scripted implements Random {
  _Scripted(this.seq);
  List<int> seq;
  int i = 0;
  @override
  int nextInt(int max) => seq[i++ % seq.length] % max;
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
}

Finder _btn(String text) => find.ancestor(
  of: find.textContaining(text),
  matching: find.byWidgetPredicate(
    (w) => w is ElevatedButton || w is FilledButton,
  ),
);

bool _enabled(WidgetTester t, Finder f) {
  final w = t.widget(f);
  if (w is ElevatedButton) return w.onPressed != null;
  if (w is FilledButton) return w.onPressed != null;
  return false;
}

/// Device-like haptics: on, and the platform answers after a short delay.
int hapticDelayMs = 0;

Future<ProviderContainer> _boot(
  WidgetTester tester,
  List<int> seq, {
  int others = 0,
  int bots = 1,
}) async {
  if (hapticDelayMs > 0) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          await Future<void>.delayed(Duration(milliseconds: hapticDelayMs));
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }
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
    hapticsEnabled: hapticDelayMs > 0,
  );
  SavedGameStore.bootstrap = SavedGameStore(loaded: true, prefs: prefs);
  final shared = _Scripted(seq); // one stream across rematches
  MatchNotifier.rngFactory = () => shared;
  addTearDown(() {
    MatchNotifier.rngFactory = Random.new;
    PlayerCoinLedger.bootstrap = null;
    SettingsNotifier.bootstrap = null;
    SavedGameStore.bootstrap = null;
  });
  final container = ProviderContainer();
  _last = container;
  addTearDown(container.dispose);
  container
      .read(matchProvider.notifier)
      .start(botCount: bots, otherHumanCount: others, playerName: 'Jerilyn');
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  final f = _btn(label);
  expect(f, findsOneWidget, reason: label);
  expect(_enabled(tester, f), isTrue, reason: '$label enabled');
  await tester.tap(f);
  await tester.pump();
  await _settle(tester);
}

String _prompt(WidgetTester t) =>
    (t.widget(find.byKey(const ValueKey('play-again-prompt'))) as Text).data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ones = [0, 0, 0];
  const after = [3, 5, 5];

  _tw('3-player hotseat: message, then each human asked in turn', (t) async {
    final c = await _boot(t, [...ones, ...after], others: 2, bots: 0);
    await _settle(t);
    await _tap(t, 'ROLL');
    await _settle(t);
    expect(
      find.text(
        'Jerilyn rolled three 1s on the first roll! Everyone pays '
        '10 gems and Jerilyn wins the pot.',
      ),
      findsOneWidget,
    );
    expect(_prompt(t), contains('Jerilyn, play another game?'));
    await _tap(t, 'Continue playing');
    expect(_prompt(t), contains('Player 2, play another game?'));
    await t.tap(find.text('Quit')); // Player 2 drops out
    await _settle(t);
    expect(_prompt(t), contains('Player 3, play another game?'));
    await _tap(t, 'Continue playing');
    await _settle(t);
    final s = c.read(matchProvider)!.snapshot;
    expect(s.phase, isNot(MatchPhase.matchEnd));
    expect(s.players.length, 2, reason: 'Player 2 left');
    expect(s.currentPlayer.profile.isHuman, isTrue);
    await _tap(t, 'ROLL');
    expect(_enabled(t, _btn('KEEP ROLLING')), isTrue);
  });

  _tw('vs bot: single prompt, bot auto-yes, no Keep Rolling lock', (t) async {
    final c = await _boot(t, [...ones, ...after]);
    await _settle(t);
    await _tap(t, 'ROLL');
    await _settle(t);
    expect(_prompt(t), 'Continue playing or quit?');
    await _tap(t, 'Continue playing');
    expect(c.read(matchProvider)!.snapshot.players.length, 2);
    await _tap(t, 'ROLL');
    expect(_enabled(t, _btn('KEEP ROLLING')), isTrue);
  });
}

ProviderContainer? _last;

void _tw(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    _last?.read(matchProvider.notifier).endMatch();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
  });
}
