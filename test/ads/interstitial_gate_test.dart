import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ads/interstitial_gate.dart';

void main() {
  group('InterstitialGate', () {
    test('allows at most one show per completed match', () {
      final g = InterstitialGate();
      expect(g.matchesRequired, 1);
      expect(g.canShow, isFalse);
      g.onMatchCompleted();
      expect(g.canShow, isTrue);
      g.onShown();
      expect(g.canShow, isFalse);
    });

    test('never back-to-back after onShown on the same break', () {
      final g = InterstitialGate();
      g.onMatchCompleted();
      expect(g.canShow, isTrue);
      g.onShown();
      expect(g.canShow, isFalse);
      expect(g.canShow, isFalse);
    });

    test('next completed match unlocks again', () {
      final g = InterstitialGate();
      g.onMatchCompleted();
      g.onShown();
      expect(g.canShow, isFalse);
      g.onMatchCompleted();
      expect(g.canShow, isTrue);
      expect(g.matchesRequired, 1);
    });
  });
}
