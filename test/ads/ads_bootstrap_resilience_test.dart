import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ads/ads_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdsService bootstrap resilience', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('bootstrap completes without throwing when ads unsupported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final service = AdsService();
      expect(adsPlatformSupported, isFalse);
      await expectLater(service.bootstrap(), completes);
      expect(service.isReady, isFalse);
      // Second call is a no-op.
      await expectLater(service.bootstrap(), completes);
    });

    test('consent helpers are no-ops when ads unsupported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final service = AdsService();
      await expectLater(service.refreshConsentAndAds(), completes);
      expect(await service.isPrivacyOptionsRequired(), isFalse);
      await expectLater(service.showPrivacyOptions(), completes);
    });
  });
}
