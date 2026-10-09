import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ads/ad_ids.dart';

void main() {
  test('defaults to Google official Android test IDs', () {
    expect(kAdmobEnabled, isFalse);
    expect(AdIds.appId, AdIds.testAppId);
    expect(AdIds.banner, AdIds.testBanner);
    expect(AdIds.interstitial, AdIds.testInterstitial);
    expect(AdIds.rewarded, AdIds.testRewarded);
    expect(AdIds.usingTestDefaults, isTrue);
    expect(AdIds.rewardedChipGrant, greaterThan(0));
  });

  group('release fails closed without injected unit IDs', () {
    test('debug/profile may use sample IDs', () {
      expect(AdIds.idsReady(release: false), isTrue);
    });

    test('release with sample defaults keeps ads off', () {
      expect(AdIds.idsReady(release: true, allowTest: false), isFalse);
    });

    test('release with one missing unit still keeps ads off', () {
      expect(
        AdIds.idsReady(
          release: true,
          allowTest: false,
          bannerId: 'injected-unit-placeholder/1',
          interstitialId: 'injected-unit-placeholder/2',
          rewardedId: AdIds.testRewarded,
        ),
        isFalse,
      );
    });

    test('release with all units injected may start ads', () {
      expect(
        AdIds.idsReady(
          release: true,
          allowTest: false,
          bannerId: 'injected-unit-placeholder/1',
          interstitialId: 'injected-unit-placeholder/2',
          rewardedId: 'injected-unit-placeholder/3',
        ),
        isTrue,
      );
    });

    test('explicit ADMOB_ALLOW_TEST_IDS opt-in for Tester builds', () {
      expect(AdIds.idsReady(release: true, allowTest: true), isTrue);
    });
  });
}
