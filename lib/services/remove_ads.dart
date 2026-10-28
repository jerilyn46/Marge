import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ads/ad_ids.dart';

/// "Remove Ads" entitlement — Play Billing **non-consumable**
/// `marge_remove_ads`.
///
/// Owning it turns off the lobby banner and the match-end interstitial only.
/// Rewarded (bonus-gem) videos stay optional and UMP consent is unchanged.
/// Never gates gameplay.
///
/// Persistence: a local flag in SharedPreferences for instant cold start, and
/// Play is the source of truth — `restorePurchases()` at billing bootstrap
/// (and the "Restore purchase" link) re-delivers the owned purchase as
/// `restored`, which sets the flag again after a reinstall / new device.
class RemoveAds {
  RemoveAds._();

  /// Play Console product ID (the purchase option may show as `remove-ads`).
  static const productId = 'marge_remove_ads';

  static const prefsKey = 'remove_ads_owned_v1';

  /// Process-wide owned flag. Read by [AdsService] (no Riverpod there) and
  /// mirrored into [removeAdsOwnedProvider] for the UI.
  static final ValueNotifier<bool> owned = ValueNotifier<bool>(false);

  /// Test hook: force the Remove Ads entry points on/off. Production follows
  /// [kAdmobEnabled] — there is nothing to remove in an ads-off build.
  @visibleForTesting
  static bool? debugOffersEnabled;

  /// Whether Remove Ads offers (Shop tile, Settings row, match-end card) may
  /// be shown at all in this build.
  static bool get offersEnabled => debugOffersEnabled ?? kAdmobEnabled;

  /// Load the cached flag before the lobby paints. Never throws.
  static Future<bool> load({SharedPreferences? prefs}) async {
    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      owned.value = store.getBool(prefsKey) ?? false;
    } catch (e, st) {
      debugPrint('RemoveAds: load failed (ads stay on): $e\n$st');
    }
    return owned.value;
  }

  /// Record ownership (purchased or restored). Idempotent.
  static Future<void> grant({SharedPreferences? prefs}) async {
    owned.value = true;
    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      await store.setBool(prefsKey, true);
    } catch (e, st) {
      debugPrint('RemoveAds: persist failed (restore re-grants): $e\n$st');
    }
  }

  /// Clear ownership (refund / revoke: Play no longer returns the product).
  static Future<void> revoke({SharedPreferences? prefs}) async {
    owned.value = false;
    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      await store.remove(prefsKey);
    } catch (e, st) {
      debugPrint('RemoveAds: revoke persist failed: $e\n$st');
    }
  }

  @visibleForTesting
  static void debugReset() {
    owned.value = false;
    debugOffersEnabled = null;
  }
}

/// UI view of [RemoveAds.owned].
class RemoveAdsNotifier extends Notifier<bool> {
  @override
  bool build() {
    void sync() => state = RemoveAds.owned.value;
    RemoveAds.owned.addListener(sync);
    ref.onDispose(() => RemoveAds.owned.removeListener(sync));
    return RemoveAds.owned.value;
  }
}

final removeAdsOwnedProvider = NotifierProvider<RemoveAdsNotifier, bool>(
  RemoveAdsNotifier.new,
);
