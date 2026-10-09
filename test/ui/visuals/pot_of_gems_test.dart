import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/sfx_service.dart';
import 'package:marge/ui/visuals/pot_of_gems.dart';

import 'visual_test_utils.dart';

String plate(WidgetTester t) => t
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('pot-plate')),
        matching: find.byType(Text),
      ),
    )
    .data!;

Widget pot(int gems, {SfxService? sfx}) => PotOfGems(
  key: const ValueKey('pot'),
  potGems: gems,
  anteGems: 10,
  seats: 2,
  width: 320,
  sfx: sfx,
);

void main() {
  test('tier = clamp(pot / (ante × seats), 0..5); any gems ≥ tier 1', () {
    expect(PotOfGems.tierFor(0, 10, 2), 0);
    expect(PotOfGems.tierFor(5, 10, 2), 1);
    expect(PotOfGems.tierFor(20, 10, 2), 1);
    expect(PotOfGems.tierFor(40, 10, 2), 2);
    expect(PotOfGems.tierFor(60, 10, 2), 3);
    expect(PotOfGems.tierFor(80, 10, 2), 4);
    expect(PotOfGems.tierFor(100, 10, 2), 5);
    expect(PotOfGems.tierFor(5000, 10, 2), 5);
  });

  test('one gem per ante unit, capped at 12', () {
    expect(PotOfGems.gemsForDelta(10, 10), 1);
    expect(PotOfGems.gemsForDelta(30, 10), 3);
    expect(PotOfGems.gemsForDelta(5, 10), 1);
    expect(PotOfGems.gemsForDelta(400, 10), 12);
  });

  testWidgets('drop: number ticks up as gems land, then settles', (
    tester,
  ) async {
    final cues = <SfxCue>[];
    final sfx = SfxService(hapticsEnabled: false)..debugOnCue = cues.add;
    await tester.pumpWidget(feltHost(pot(20, sfx: sfx)));
    expect(plate(tester), 'Pot · 20');

    await tester.pumpWidget(feltHost(pot(60, sfx: sfx))); // 4 gems
    expect(plate(tester), 'Pot · 20'); // nothing landed yet
    await tester.pump(const Duration(milliseconds: 300));
    expect(plate(tester), 'Pot · 20'); // still falling (520 ms flight)
    await tester.pump(const Duration(milliseconds: 250)); // 550: gem 1 in
    expect(plate(tester), 'Pot · 30');
    await tester.pump(const Duration(milliseconds: 600));
    expect(plate(tester), 'Pot · 60');
    expect(cues.where((c) => c == SfxCue.gemTink).length, 4);
    expect(cues, contains(SfxCue.tierSwell)); // tier 1 → 3
  });

  testWidgets('drain: pot taken ticks down over ~500 ms', (tester) async {
    await tester.pumpWidget(feltHost(pot(100)));
    await tester.pumpWidget(feltHost(pot(20)));
    await tester.pump(const Duration(milliseconds: 250));
    final mid = int.parse(plate(tester).split('· ').last);
    expect(mid, inExclusiveRange(20, 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(plate(tester), 'Pot · 20');
  });

  testWidgets('Reduce Motion: instant value, nothing flies', (tester) async {
    await tester.pumpWidget(feltHost(pot(20), reduceMotion: true));
    await tester.pumpWidget(feltHost(pot(80), reduceMotion: true));
    expect(plate(tester), 'Pot · 80');
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('sound off: no cue hooks fire', (tester) async {
    final cues = <SfxCue>[];
    final sfx = SfxService(sfxEnabled: false, hapticsEnabled: false)
      ..debugOnCue = cues.add;
    await tester.pumpWidget(feltHost(pot(20, sfx: sfx)));
    await tester.pumpWidget(feltHost(pot(60, sfx: sfx)));
    await tester.pump(const Duration(seconds: 1));
    expect(cues, isEmpty);
  });

  for (var tier = 0; tier <= 5; tier++) {
    testWidgets('golden: pot tier $tier', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 280));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await precacheAssets(tester, GemArt.potAssets);
      await tester.pumpWidget(feltHost(pot(tier * 20)));
      await tester.pump();
      expect(
        PotOfGems.tierFor(tier * 20, 10, 2),
        tier,
      );
      await expectLater(
        find.byKey(const ValueKey('pot')),
        matchesGoldenFile('goldens/pot_tier_$tier.png'),
      );
    });
  }
}
