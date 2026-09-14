import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/ui/match_provider.dart';
import 'package:marge/ui/screens/match_screen.dart';
import 'package:marge/ui/theme/marge_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone-sized table: Roll must stay on screen (not clipped by gem UI).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local human sees ROLL on a phone-sized match table', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = MatchController(
      config: const MatchConfig(botCount: 1, otherHumanCount: 0),
      rng: Random(7),
    );
    controller.startMatch();
    final snap = controller.snapshot;
    expect(snap.phase, MatchPhase.playing);
    expect(snap.currentPlayer.profile.isHuman, isTrue);
    expect(snap.turn, isNotNull);

    final view = MatchViewState(snapshot: snap);

    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchProvider.overrideWith(() => _SeededMatchNotifier(view)),
        ],
        child: MaterialApp(
          theme: buildMargeTheme(),
          home: const MatchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No layout overflow from the play Column.
    expect(tester.takeException(), isNull);

    final roll = find.text('ROLL');
    expect(roll, findsOneWidget);

    final box = tester.renderObject<RenderBox>(roll);
    final topLeft = box.localToGlobal(Offset.zero);
    final bottom = topLeft.dy + box.size.height;
    expect(
      topLeft.dy,
      greaterThanOrEqualTo(0),
      reason: 'ROLL must not sit above the viewport',
    );
    expect(
      bottom,
      lessThanOrEqualTo(700),
      reason: 'ROLL must stay inside the phone viewport, not under gem pickers',
    );

    // Inline gem denomination pickers must not live on the play Column.
    expect(find.text('Add gems'), findsNothing);
    expect(find.text('Move into this game'), findsNothing);

    // Compact entry still opens the sheet when needed.
    await tester.tap(find.byTooltip('Table gems'));
    await tester.pumpAndSettle();
    expect(find.text('Add gems'), findsOneWidget);
    expect(find.text('Move into this game'), findsOneWidget);
  });
}

class _SeededMatchNotifier extends MatchNotifier {
  _SeededMatchNotifier(this._seed);
  final MatchViewState _seed;

  @override
  MatchViewState? build() => _seed;
}
