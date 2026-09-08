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
}
