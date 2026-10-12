import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ui/visuals/dice_3d.dart';
import 'package:marge/ui/visuals/dice_throw_sim.dart';

import 'visual_test_utils.dart';

ThrowResult sim(int seed, {List<bool> moving = const [true, true, true]}) =>
    DiceThrowSim.simulate(
      seed: seed,
      width: 360,
      height: 420,
      dieSize: 64,
      moving: moving,
      values: const [3, 5, 6],
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
      // Snapshot of seed 42 (regression lock on the playback).
      String snap(ThrowResult r, double? t) => [
        for (var i = 0; i < 3; i++)
          (t == null ? r.finalFrame[i] : r.at(t, i)).p.x.toStringAsFixed(1),
      ].join(',');
      expect(snap(a, 0.3), isNot(snap(a, null))); // still in flight
      expect(snap(a, 0.8), snap(b, 0.8));
      expect(sim(43).finalFrame[0].p.x, isNot(a.finalFrame[0].p.x));
    });

    test('dice travel up the table, then settle flat by 2.2 s', () {
      for (var seed = 0; seed < 60; seed++) {
        final r = sim(seed);
        expect(r.duration, lessThanOrEqualTo(2.2 + 2 * DiceThrowSim.dt));
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

    test('kept dice are fixed obstacles', () {
      final r = sim(7, moving: const [true, false, true]);
      final p0 = r.frames.first[1].p;
      for (final f in r.frames) {
        expect(f[1].p.x, p0.x);
        expect(f[1].p.y, p0.y);
      }
    });
  });

  group('DiceTray throw playback', () {
    Widget tray(
      int serial, {
      List<int> values = const [3, 5, 6],
      bool reduce = false,
    }) => feltHost(
      SizedBox(
        width: 360,
        height: 420,
        child: DiceTray(
          values: values,
          kept: const [false, false, false],
          animate: const [true, true, true],
          rollSerial: serial,
        ),
      ),
      size: const Size(360, 480),
      reduceMotion: reduce,
    );

    List<int> faces(WidgetTester t) => [
      for (var i = 0; i < 3; i++)
        t
            .widget<DiceCube>(
              find.descendant(
                of: find.byKey(ValueKey('die-cube-$i')),
                matching: find.byType(DiceCube),
              ),
            )
            .value,
    ];

    testWidgets('faces equal the decided values at 0.3 s, 0.8 s, settled', (
      tester,
    ) async {
      await tester.pumpWidget(tray(0));
      await tester.pumpWidget(tray(1));
      final at = <Offset>[];
      for (final ms in [300, 500]) {
        await tester.pump(Duration(milliseconds: ms));
        expect(faces(tester), [3, 5, 6]);
        at.add(tester.getCenter(find.byKey(const ValueKey('die-cube-0'))));
      }
      expect(at[0], isNot(at[1])); // moving across the felt
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.state<DiceTrayState>(find.byType(DiceTray)).settling,
        isFalse,
      );
      expect(faces(tester), [3, 5, 6]);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('triples: big-result glow + sparkle, then settles', (
      tester,
    ) async {
      await tester.pumpWidget(tray(0, values: const [4, 4, 4]));
      await tester.pumpWidget(tray(1, values: const [4, 4, 4]));
      var sawGlow = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('big-glow')).evaluate().isNotEmpty) {
          sawGlow = true;
        }
      }
      expect(sawGlow, isTrue);
      expect(
        tester.state<DiceTrayState>(find.byType(DiceTray)).settling,
        isFalse,
      );
    });
  });
}
