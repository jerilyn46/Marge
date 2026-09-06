import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ads/interstitial_gate.dart';

void main() {
  group('InterstitialGate', () {
    test('blocks until required matches complete', () {
      final g = InterstitialGate(initialMatchesRequired: 2);
      expect(g.canShow, isFalse);
      g.onMatchCompleted();
      expect(g.canShow, isFalse);
      g.onMatchCompleted();
      expect(g.canShow, isTrue);
    });

    test('never back-to-back after onShown', () {
      final g = InterstitialGate(initialMatchesRequired: 2);
      g.onMatchCompleted();
      g.onMatchCompleted();
      expect(g.canShow, isTrue);
      g.onShown();
      expect(g.canShow, isFalse);
      // Same break / immediate re-check still blocked.
      expect(g.canShow, isFalse);
    });

    test('alternates required matches between 2 and 3', () {
      final g = InterstitialGate(initialMatchesRequired: 2);
      g.onMatchCompleted();
      g.onMatchCompleted();
      g.onShown();
      expect(g.matchesRequired, 3);

      g.onMatchCompleted();
      g.onMatchCompleted();
      expect(g.canShow, isFalse);
      g.onMatchCompleted();
      expect(g.canShow, isTrue);
      g.onShown();
      expect(g.matchesRequired, 2);
    });
  });
}
