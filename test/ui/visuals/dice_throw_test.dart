import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ui/visuals/dice_3d.dart';
import 'package:marge/ui/visuals/dice_throw_sim.dart';

import 'visual_test_utils.dart';

ThrowResult sim(
  int seed, {
  List<bool> moving = const [true, true, true],
  double width = 360,
  double height = 420,
  int edge = DiceThrowSim.edgeBottom,
}) => DiceThrowSim.simulate(
  seed: seed,
  width: width,
  height: height,
  dieSize: 64,
  moving: moving,
  values: const [3, 5, 6],
  edge: edge,
);

void main() {
  group('DiceThrowSim (deterministic seed)', () {
    test('same seed -> identical positions at 0.3 s, 0.8 s and settled', () {
      final a = sim(42), b = sim(42);
      for (final t in [0.3, 0.8]) {
        for (var i = 0; i < 3; i++) {
          expect(a.at(t, i).p.x, b.at(t, i).p.x);
          expect(a.at(t, i).p.y, b.at(t, i).p.y);
          expect(a.at(t, i).p.z, b.at(t, i).p.z);
        }
      }
      for (var i = 0; i < 3; i++) {
        expect(a.finalFrame[i].p.x, b.finalFrame[i].p.x);
        expect(a.finalFrame[i].p.y, b.finalFrame[i].p.y);
      }
      expect(a.at(0.3, 0).p.y, isNot(a.finalFrame[0].p.y)); // still flying
      expect(sim(43).finalFrame[0].p.x, isNot(a.finalFrame[0].p.x));
    });

    test('settle time: >= 80% in 1.4–1.8 s sim; on-screen <= 2.2 s', () {
      for (final h in [300.0, 420.0]) {
        var inWindow = 0;
        for (var seed = 0; seed < 300; seed++) {
          final r = sim(seed, height: h);
          final d = r.duration;
          if (d >= 1.4 && d <= 1.8) inWindow++;
          expect(d, lessThanOrEqualTo(1.85), reason: 'seed $seed');
          for (final (big, epic) in [
            (false, false),
            (true, false),
            (true, true),
          ]) {
            // + 250 ms beat before the readout.
            final wall =
                DiceThrowSim.warp(r, big: big, epic: epic).length + 250;
            expect(wall, lessThanOrEqualTo(2200), reason: 'seed $seed');
          }
        }
        expect(inWindow / 300, greaterThanOrEqualTo(0.8), reason: 'h $h');
      }
    });

    test('dice travel up the table and settle flat', () {
      for (var seed = 0; seed < 60; seed++) {
        final r = sim(seed);
        for (final d in r.finalFrame) {
          expect(d.settled, isTrue);
          expect(d.p.z, closeTo(32, 0.01));
        }
        var minY = 1e9;
        for (final f in r.frames) {
          for (final d in f) {
            if (d.p.y < minY) minY = d.p.y;
          }
        }
        expect((420 - minY) / 420, greaterThan(0.5), reason: 'seed $seed');
      }
    });

    test('decided face ends on top for every die (relabel)', () {
      for (var seed = 0; seed < 60; seed++) {
        final r = sim(seed);
        for (var i = 0; i < 3; i++) {
          final up = (r.finalFrame[i].q * r.relabel[i]).rotate(
            const V3(0, 0, 1),
          );
          expect(up.z, closeTo(1, 1e-6), reason: 'seed $seed die $i');
        }
      }
    });

    test('zero die overlap at rest (OBB/SAT footprints)', () {
      for (var seed = 0; seed < 100; seed++) {
        final r = sim(seed, moving: [true, seed.isEven, true]);
        for (var i = 0; i < 3; i++) {
          for (var j = i + 1; j < 3; j++) {
            expect(
              r.footprint(i).overlap(r.footprint(j)),
              isNull,
              reason: 'seed $seed dice $i/$j',
            );
          }
        }
      }
    });

    test('rest framing: fully on screen, no perspective overlap', () {
      for (final (w, h) in [(360.0, 280.0), (360.0, 420.0), (390.0, 520.0)]) {
        for (var seed = 0; seed < 100; seed++) {
          final r = sim(seed, width: w, height: h);
          final b = [
            for (var i = 0; i < 3; i++)
              DiceThrowSim.restBounds(
                r.finalFrame[i].p.x,
                r.finalFrame[i].p.y,
                DiceThrowSim.restYaw(r.finalFrame[i].q * r.relabel[i]),
                32,
              ),
          ];
          for (var i = 0; i < 3; i++) {
            expect(b[i].$1, greaterThanOrEqualTo(0), reason: '$w×$h s$seed');
            expect(b[i].$2, greaterThanOrEqualTo(0), reason: '$w×$h s$seed');
            expect(b[i].$3, lessThanOrEqualTo(w), reason: '$w×$h s$seed');
            expect(b[i].$4, lessThanOrEqualTo(h), reason: '$w×$h s$seed');
            for (var j = i + 1; j < 3; j++) {
              final apart =
                  b[i].$3 <= b[j].$1 ||
                  b[j].$3 <= b[i].$1 ||
                  b[i].$4 <= b[j].$2 ||
                  b[j].$4 <= b[i].$2;
              expect(apart, isTrue, reason: '$w×$h seed $seed dice $i/$j');
            }
          }
        }
      }
    });

    test('kept dice are fixed obstacles', () {
      final r = sim(7, moving: const [true, false, true]);
      final p0 = r.frames.first[1].p;
      for (final f in r.frames) {
        expect(f[1].p.x, p0.x);
        expect(f[1].p.y, p0.y);
      }
    });

    test('throws start at the thrower\'s edge', () {
      const w = 360.0, h = 420.0;
      for (var seed = 0; seed < 20; seed++) {
        final bottom = sim(seed, edge: DiceThrowSim.edgeBottom).frames.first;
        final top = sim(seed, edge: DiceThrowSim.edgeTop).frames.first;
        final left = sim(seed, edge: DiceThrowSim.edgeLeft).frames.first;
        final right = sim(seed, edge: DiceThrowSim.edgeRight).frames.first;
        for (var i = 0; i < 3; i++) {
          expect(bottom[i].p.y, greaterThan(h * 0.75));
          expect(top[i].p.y, lessThan(h * 0.25));
          expect(left[i].p.x, lessThan(w * 0.25));
          expect(right[i].p.x, greaterThan(w * 0.75));
        }
      }
    });

    test('hotseat seat -> edge', () {
      expect(DiceTray.edgeForSeat(0, 2), DiceThrowSim.edgeBottom);
      expect(DiceTray.edgeForSeat(1, 2), DiceThrowSim.edgeTop);
      expect(DiceTray.edgeForSeat(1, 3), DiceThrowSim.edgeLeft);
      expect(DiceTray.edgeForSeat(2, 3), DiceThrowSim.edgeRight);
      expect(
        {for (var s = 1; s < 4; s++) DiceTray.edgeForSeat(s, 4)},
        {DiceThrowSim.edgeLeft, DiceThrowSim.edgeTop, DiceThrowSim.edgeRight},
      );
    });

    test('camera tilt constants match DiceCube', () {
      expect(DiceThrowSim.viewTiltX, DiceCube.restRx);
      expect(DiceThrowSim.viewTiltY, DiceCube.restRy);
      expect(DiceThrowSim.perspective, DiceCube.perspective);
    });
  });

  group('DiceTray throw playback', () {
    Widget tray(
      int serial, {
      List<int> values = const [3, 5, 6],
      int edge = DiceThrowSim.edgeBottom,
    }) => feltHost(
      SizedBox(
        width: 360,
        height: 420,
        child: DiceTray(
          values: values,
          kept: const [false, false, false],
          animate: const [true, true, true],
          rollSerial: serial,
          throwEdge: edge,
        ),
      ),
      size: const Size(360, 480),
    );

    DiceTrayState st(WidgetTester t) =>
        t.state<DiceTrayState>(find.byType(DiceTray));

    testWidgets('faces equal the decided values at 0.3 s, 0.8 s, settled', (
      tester,
    ) async {
      await tester.pumpWidget(tray(0));
      await tester.pumpWidget(tray(1));
      final at = <Offset>[];
      for (final ms in [300, 500]) {
        await tester.pump(Duration(milliseconds: ms));
        expect(st(tester).debugValues, [3, 5, 6]);
        at.add(st(tester).debugCenters[0]);
      }
      expect(at[0], isNot(at[1])); // moving across the felt
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(st(tester).settling, isFalse);
      expect(st(tester).debugFrontFaces, [3, 5, 6]);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('hotseat: the top seat throws from the top edge', (
      tester,
    ) async {
      await tester.pumpWidget(tray(0, edge: DiceThrowSim.edgeTop));
      await tester.pumpWidget(tray(1, edge: DiceThrowSim.edgeTop));
      await tester.pump(const Duration(milliseconds: 20));
      for (final c in st(tester).debugCenters) {
        expect(c.dy, lessThan(420 * 0.3));
      }
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(st(tester).settling, isFalse);
    });

    testWidgets('triples: big-result glow + sparkle, settles by 2.2 s', (
      tester,
    ) async {
      await tester.pumpWidget(tray(0, values: const [4, 4, 4]));
      await tester.pumpWidget(tray(1, values: const [4, 4, 4]));
      var sawSparkle = false;
      var ms = 0;
      while (st(tester).settling) {
        await tester.pump(const Duration(milliseconds: 50));
        ms += 50;
        if (find
            .byKey(const ValueKey('triple-sparkle-0'))
            .evaluate()
            .isNotEmpty) {
          sawSparkle = true;
        }
      }
      expect(ms, lessThanOrEqualTo(2250));
      expect(sawSparkle, isTrue);
    });
  });
}
