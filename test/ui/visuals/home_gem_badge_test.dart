import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ui/screens/home_screen.dart';
import 'package:marge/ui/visuals/pot_of_gems.dart';
import 'package:marge/ui/widgets/felt_hero_backdrop.dart';

import 'visual_test_utils.dart';

void main() {
  testWidgets('Home gem bank badge is the ruby, not a gold disc', (
    tester,
  ) async {
    await tester.pumpWidget(feltHost(GemJewelTray(gems: 1240, onTap: () {})));
    final ruby = tester.widget<Image>(
      find.byKey(const ValueKey('home-gem-ruby')),
    );
    expect(
      (ruby.image as AssetImage).assetName,
      'assets/visuals/gems/gem_ruby.png',
    );
    expect(find.byType(GemChipAccent), findsNothing);
    expect(find.text('1240 gems'), findsOneWidget);
  });

  testWidgets('golden: Home gem bank badge', (tester) async {
    await tester.binding.setSurfaceSize(const Size(200, 80));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await precacheAssets(tester, GemArt.potAssets);
    await tester.pumpWidget(
      feltHost(
        GemJewelTray(gems: 1240, onTap: () {}),
        size: const Size(200, 80),
      ),
    );
    await settleImages(tester);
    await expectLater(
      find.byType(GemJewelTray),
      matchesGoldenFile('goldens/home_gem_badge.png'),
    );
  });
}
