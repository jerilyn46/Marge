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

    test('bootstrap never throws even if platform looks mobile (no plugin)',
        () async {
      // Flutter tests often report TargetPlatform.android; bootstrap must
      // still complete (plugin calls fail open / timeout) and not abort.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = AdsService();
      await expectLater(
        service.bootstrap().timeout(const Duration(seconds: 25)),
        completes,
      );
    });
  });
}
