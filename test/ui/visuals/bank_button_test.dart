import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/sfx_service.dart';
import 'package:marge/ui/visuals/bank_button.dart';
import 'package:marge/ui/visuals/pot_of_gems.dart';

import 'visual_test_utils.dart';

Widget host(Widget child, {bool reduceMotion = false}) => feltHost(
  SizedBox(width: 340, child: child),
  reduceMotion: reduceMotion,
  size: const Size(380, 140),
);

void main() {
  testWidgets('label is Bank with +N gems, no other copy', (tester) async {
    await tester.pumpWidget(host(BankButton(amountGems: 340, onBank: () {})));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('+340 gems'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(2));
    expect(tester.getSize(find.byType(BankButton)).height, 64);
  });

  testWidgets('enter: 0.85 → 1.05 → 1.0 after a 150 ms beat', (tester) async {
    double scale() => tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byType(BankButton),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .storage[0]; // x scale
    final cues = <SfxCue>[];
    final sfx = SfxService(hapticsEnabled: false)..debugOnCue = cues.add;
    await tester.pumpWidget(
      host(BankButton(amountGems: 10, onBank: () {}, sfx: sfx)),
    );
    expect(scale(), closeTo(0.85, 0.001));
    await tester.pump(const Duration(milliseconds: 100));
    expect(cues, isEmpty); // chime waits for the beat
    await tester.pump(const Duration(milliseconds: 280)); // 380 ms: peak
    expect(scale(), closeTo(1.05, 0.01));
    expect(cues, [SfxCue.bankChime]);
    await tester.pump(const Duration(milliseconds: 120)); // 500 ms
    expect(scale(), closeTo(1.0, 0.031)); // pulse may have started
  });

  testWidgets('one tap only: burst, then onBank exactly once', (tester) async {
    var banks = 0;
    await tester.pumpWidget(
      host(BankButton(amountGems: 10, onBank: () => banks++)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byType(BankButton));
    await tester.pump();
    await tester.tap(find.byType(BankButton), warnIfMissed: false);
    await tester.tap(find.byType(BankButton), warnIfMissed: false);
    expect(find.byType(GemBurst), findsOneWidget);
    expect(banks, 0); // bank lands with the gems
    await tester.pump(BankButton.burstDuration);
    await tester.pump(const Duration(milliseconds: 50));
    expect(banks, 1);
    expect(find.byType(GemBurst), findsNothing);
  });

  testWidgets('disabled: taps do nothing', (tester) async {
    var banks = 0;
    await tester.pumpWidget(
      host(BankButton(amountGems: 10, enabled: false, onBank: () => banks++)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(BankButton));
    await tester.pump(const Duration(seconds: 1));
    expect(banks, 0);
  });

  testWidgets('Reduce Motion: static, no loops, banks at once', (tester) async {
    var banks = 0;
    await tester.pumpWidget(
      host(
        BankButton(amountGems: 10, onBank: () => banks++),
        reduceMotion: true,
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tap(find.byType(BankButton));
    expect(banks, 1);
    expect(find.byType(GemBurst), findsNothing);
  });

  testWidgets('golden: Bank button idle', (tester) async {
    await tester.binding.setSurfaceSize(const Size(380, 140));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await precacheAssets(tester, GemArt.potAssets);
    await tester.pumpWidget(
      host(
        BankButton(key: const ValueKey('bank'), amountGems: 340, onBank: () {}),
      ),
    );
    // Past the enter (500 ms), one frame to start the idle loops, then a
    // fixed idle phase: sheen 300 ms into its 600 ms sweep (mid-button),
    // pulse 300 ms into its 1.2 s loop. Fake time makes this deterministic.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(const ValueKey('bank')),
      matchesGoldenFile('goldens/bank_button_idle.png'),
    );
  });
}
