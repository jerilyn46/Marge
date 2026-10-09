import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:marge/ui/visuals/bank_button.dart';
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

class _Seeded extends MatchNotifier {
  _Seeded(this._seed);
  final MatchViewState _seed;
  @override
  MatchViewState? build() => _seed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Bank: the top-bar gem bank ticks up as particles land', (
    tester,
  ) async {
    // Three 4s on the first roll, two bots → Bank pays 2 × trips.
    final c = MatchController(
      config: const MatchConfig(botCount: 2),
      rng: _Scripted([3, 3, 3]),
    );
    c.startMatch();
    c.roll();
    final snap = c.snapshot;
    expect(snap.turn!.canBank, isTrue);
    final start = snap.players[0].bankCents;
    final amount = snap.bankGems;
    expect(amount, greaterThan(0));

    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchProvider.overrideWith(
            () => _Seeded(MatchViewState(snapshot: snap)),
          ),
        ],
        child: MaterialApp(theme: buildMargeTheme(), home: const MatchScreen()),
      ),
    );
    String count() =>
        tester.widget<Text>(find.byKey(const ValueKey('gem-bank-count'))).data!;
    expect(count(), '$start');

    await tester.pump(const Duration(milliseconds: 600)); // Bank entered
    await tester.tap(find.byKey(const ValueKey('bank-only')));
    await tester.pump();
    expect(count(), '$start'); // gems still in the air

    await tester.pump(
      const Duration(
        milliseconds:
            BankButton.particleFlightMs + 2 * BankButton.particleStaggerMs + 5,
      ),
    );
    final mid = int.parse(count());
    expect(mid, greaterThan(start));
    expect(mid, lessThan(start + amount));

    await tester.pump(BankButton.burstDuration);
    await tester.pump(const Duration(milliseconds: 200));
    expect(count(), '${start + amount}');
  });
}
