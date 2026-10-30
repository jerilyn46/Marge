import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ads/ad_ids.dart';
import 'coin_ledger.dart';

/// Shared rewarded-ad quota: [AdIds.rewardedDailyCap] earned watches per
/// America/Denver calendar day, across every rewarded placement (post-match
/// double gems + shortfall / gem-bank "Watch for +50").
///
/// Persisted in SharedPreferences. Never throws; load failures leave the
/// in-memory count (fresh day) in place. Not a free-mint cap — rewarded
/// grants are counted only here.
class RewardedQuota {
  RewardedQuota._();

  static const prefsKey = 'rewarded_quota_v1';

  static String _day = '';
  static int _used = 0;

  /// Remaining watches today; UI listens to refresh labels.
  static final ValueNotifier<int> remainingNotifier = ValueNotifier<int>(
    AdIds.rewardedDailyCap,
  );

  @visibleForTesting
  static DateTime Function() clock = () => DateTime.now().toUtc();

  static String _today() => PlayerCoinLedger.denverDayKey(clock());

  static void _roll() {
    final today = _today();
    if (_day != today) {
      _day = today;
      _used = 0;
    }
    remainingNotifier.value = (AdIds.rewardedDailyCap - _used).clamp(
      0,
      AdIds.rewardedDailyCap,
    );
  }

  static int used() {
    _roll();
    return _used;
  }

  static int remaining() {
    _roll();
    return remainingNotifier.value;
  }

  static bool canWatch() => remaining() > 0;

  static Future<void> load({SharedPreferences? prefs}) async {
    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      final raw = store.getString(prefsKey);
      if (raw != null) {
        final parts = raw.split('|');
        if (parts.length == 2) {
          _day = parts[0];
          _used = int.tryParse(parts[1]) ?? 0;
        }
      }
    } catch (e, st) {
      debugPrint('RewardedQuota: load failed: $e\n$st');
    }
    _roll();
  }

  /// Record one earned watch. Returns false when today's cap is spent.
  static Future<bool> consume({SharedPreferences? prefs}) async {
    _roll();
    if (_used >= AdIds.rewardedDailyCap) return false;
    _used++;
    _roll();
    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      await store.setString(prefsKey, '$_day|$_used');
    } catch (e, st) {
      debugPrint('RewardedQuota: persist failed: $e\n$st');
    }
    return true;
  }

  @visibleForTesting
  static void debugReset() {
    _day = '';
    _used = 0;
    clock = () => DateTime.now().toUtc();
    remainingNotifier.value = AdIds.rewardedDailyCap;
  }
}
