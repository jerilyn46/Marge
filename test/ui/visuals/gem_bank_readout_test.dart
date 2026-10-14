import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ui/visuals/bank_button.dart';
import 'package:marge/ui/visuals/gem_bank_readout.dart';
import 'package:marge/ui/visuals/pot_of_gems.dart';

import 'visual_test_utils.dart';

final _key = GlobalKey<GemBankReadoutState>();

Widget readout(int gems, {String owner = 'human_0', bool reduce = false}) =>
    feltHost(
      GemBankReadout(key: _key, gems: gems, ownerId: owner),
      reduceMotion: reduce,
      size: const Size(200, 80),
    );

String count(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey('gem-bank-count'))).data!;

void main() {
  test('shares add up exactly', () {
    expect(gemShares(340, 10), [34, 34, 34, 34, 34, 34, 34, 34, 34, 34]);
    expect(gemShares(16, 10).reduce((a, b) => a + b), 16);
    expect(gemShares(7, 10).where((g) => g > 0).length, 7);
  });

  testWidgets('Bank: holds, ticks per particle, then follows the engine', (
    tester,
  ) async {
    await tester.pumpWidget(readout(100));
    expect(count(tester), '100');
    _key.currentState!.beginIncoming(30);
    await tester.pump();
    expect(count(tester), '100');
    for (final g in gemShares(30, 3)) {
      _key.currentState!.land(g);
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(count(tester), '130'); // all landed, credit not in yet: hold
    await tester.pumpWidget(readout(130)); // engine credit arrives
    expect(count(tester), '130');
    expect(_key.currentState!.ticking, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('credit before the gems land does not jump ahead', (
    tester,
  ) async {
    await tester.pumpWidget(readout(100));
    _key.currentState!.beginIncoming(20);
    await tester.pumpWidget(readout(120)); // early credit
    expect(count(tester), '100');
    _key.currentState!.land(10);
    await tester.pump();
    expect(count(tester), '110');
    _key.currentState!.land(10);
    await tester.pump();
    expect(count(tester), '120');
    expect(_key.currentState!.ticking, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('pot win: already credited, released when the last lands', (
    tester,
  ) async {
    await tester.pumpWidget(readout(80)); // held pre-win value
    _key.currentState!.beginIncoming(20, credited: true);
    await tester.pumpWidget(readout(100));
    expect(count(tester), '80');
    _key.currentState!.land(20);
    await tester.pump();
    expect(count(tester), '100');
    expect(_key.currentState!.ticking, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a new owner cancels the hold', (tester) async {
    await tester.pumpWidget(readout(100));
    _key.currentState!.beginIncoming(20);
    await tester.pumpWidget(readout(55, owner: 'human_1'));
    expect(count(tester), '55');
  });

  testWidgets('Reduce Motion: ticks without the pop', (tester) async {
    await tester.pumpWidget(readout(10, reduce: true));
    _key.currentState!.beginIncoming(5);
    _key.currentState!.land(5);
    await tester.pump();
    expect(count(tester), '15');
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Bank button particles report shares that add up', (
    tester,
  ) async {
    final landed = <int>[];
    var started = 0;
    await tester.pumpWidget(
      feltHost(
        SizedBox(
          width: 340,
          child: BankButton(
            amountGems: 23,
            onBank: () {},
            onBurstStart: () => started++,
            onParticleLanded: landed.add,
          ),
        ),
        size: const Size(380, 140),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byType(BankButton));
    await tester.pump();
    expect(started, 1);
    expect(landed, isEmpty);
    await tester.pump(
      const Duration(milliseconds: BankButton.particleFlightMs + 5),
    );
    expect(landed.length, 1); // first particle in after 500 ms
    await tester.pump(BankButton.burstDuration);
    await tester.pump();
    expect(landed.length, BankButton.particleCount);
    expect(landed.reduce((a, b) => a + b), 23);
  });

  testWidgets('golden: gem bank readout mid-tick', (tester) async {
    await tester.binding.setSurfaceSize(const Size(200, 80));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await precacheAssets(tester, GemArt.potAssets);
    await tester.pumpWidget(readout(1240));
    _key.currentState!.beginIncoming(340);
    _key.currentState!.land(102);
    await tester.pump(const Duration(milliseconds: 80)); // top of the pop
    await settleImages(tester);
    expect(count(tester), '1342');
    await expectLater(
      find.byType(GemBankReadout),
      matchesGoldenFile('goldens/gem_bank_readout_tick.png'),
    );
    await tester.pump(const Duration(milliseconds: 300));
  });
}
