import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ads/ad_ids.dart';
import 'package:marge/services/rewarded_quota.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RewardedQuota.debugReset();
  });

  test('locked constants', () {
    expect(AdIds.rewardedDailyCap, 3);
    expect(AdIds.rewardedShortfallGrant, 50);
  });

  test('3 per Denver day, resets at Denver midnight', () async {
    // 2026-10-30 23:30 MDT = 2026-10-31 05:30 UTC.
    var now = DateTime.utc(2026, 10, 31, 5, 30);
    RewardedQuota.clock = () => now;
    await RewardedQuota.load();
    expect(RewardedQuota.remaining(), 3);
    for (var i = 0; i < 3; i++) {
      expect(await RewardedQuota.consume(), isTrue);
    }
    expect(RewardedQuota.canWatch(), isFalse);
    expect(await RewardedQuota.consume(), isFalse);
    // 00:30 MDT next day.
    now = DateTime.utc(2026, 10, 31, 6, 30);
    expect(RewardedQuota.remaining(), 3);
  });

  test('persists across reload', () async {
    RewardedQuota.clock = () => DateTime.utc(2026, 10, 30, 18);
    await RewardedQuota.consume();
    await RewardedQuota.consume();
    RewardedQuota.debugReset();
    RewardedQuota.clock = () => DateTime.utc(2026, 10, 30, 20);
    await RewardedQuota.load();
    expect(RewardedQuota.remaining(), 1);
  });
}
