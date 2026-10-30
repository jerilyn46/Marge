import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../ui/legal_links.dart';
import 'remove_ads.dart';
import 'coin_ledger.dart';
import 'denver_time.dart';
import 'settings_service.dart';

/// Play Billing gem packs. Virtual gems only — not real money, no cash-out.
///
/// SKUs must match Play Console product IDs (consumable managed products).
class GemPack {
  const GemPack({
    required this.productId,
    required this.gems,
    required this.title,
    required this.blurb,
  });

  final String productId;
  final int gems;
  final String title;
  final String blurb;

  static const small = GemPack(
    productId: 'marge_gems_small',
    gems: 100,
    title: 'Small gem pack',
    blurb: '100 virtual gems for the table.',
  );

  static const medium = GemPack(
    productId: 'marge_gems_medium',
    gems: 500,
    title: 'Medium gem pack',
    blurb: '500 virtual gems for the table.',
  );

  static const large = GemPack(
    productId: 'marge_gems_large',
    gems: 1200,
    title: 'Large gem pack',
    blurb: '1200 virtual gems for the table.',
  );

  /// Weekend-only bag. Offered Friday–Sunday America/Denver only.
  /// SKU is already Active in Play Console — do not rename.
  static const weekend = GemPack(
    productId: 'marge_gems_weekend',
    gems: 650,
    title: 'Weekend bag',
    blurb: '650 virtual gems — Fridays to Sundays only (Denver time).',
  );

  /// Copy shown on the Shop card describing the window.
  static const weekendWindowCopy =
      'Available Friday–Sunday (Mountain Time) only.';

  /// Every SKU we query and can credit. Includes [weekend] so a weekend
  /// purchase that lands/restores on a Monday is still credited.
  static const all = <GemPack>[small, medium, large, weekend];

  /// Test hook for "now" (UTC).
  @visibleForTesting
  static DateTime Function() clock = () => DateTime.now().toUtc();

  /// True Friday 00:00 → Sunday 23:59 America/Denver.
  static bool isWeekendDenver(DateTime utc) {
    final wd = DenverTime.wallClock(utc).weekday;
    return wd == DateTime.friday ||
        wd == DateTime.saturday ||
        wd == DateTime.sunday;
  }

  /// Whether this pack may be bought at [utc] (default: now).
  bool isOfferedAt([DateTime? utc]) =>
      productId != weekend.productId || isWeekendDenver(utc ?? clock());

  /// Packs the Shop may offer for purchase at [utc].
  static List<GemPack> offeredAt([DateTime? utc]) => [
    for (final p in all)
      if (p.isOfferedAt(utc)) p,
  ];

  static GemPack? byId(String id) {
    for (final p in all) {
      if (p.productId == id) return p;
    }
    return null;
  }

  static Set<String> get productIds => {for (final p in all) p.productId};

  /// SKUs queried at IAP bootstrap (cold start). Excludes [weekend]: querying
  /// it at launch crashed Flip 7 on 0.1.43. The weekend SKU is queried lazily
  /// by [GemIapNotifier.loadWeekendProduct] when the Shop opens.
  static Set<String> get bootstrapProductIds =>
      {for (final p in all) if (p.productId != weekend.productId) p.productId};
}

/// Purchase / store readiness for the Shop UI.
class GemIapState {
  const GemIapState({
    this.available = false,
    this.loading = false,
    this.products = const {},
    this.lastError,
    this.purchasingId,
  });

  final bool available;
  final bool loading;
  final Map<String, ProductDetails> products;
  final String? lastError;
  final String? purchasingId;

  GemIapState copyWith({
    bool? available,
    bool? loading,
    Map<String, ProductDetails>? products,
    String? lastError,
    bool clearError = false,
    String? purchasingId,
    bool clearPurchasing = false,
  }) => GemIapState(
    available: available ?? this.available,
    loading: loading ?? this.loading,
    products: products ?? this.products,
    lastError: clearError ? null : (lastError ?? this.lastError),
    purchasingId: clearPurchasing ? null : (purchasingId ?? this.purchasingId),
  );
}

/// Thin Play Billing wrapper. Credits [PlayerCoinLedger] only — never cash-out.
class GemIapNotifier extends Notifier<GemIapState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Set<String> _handledPurchaseIds = {};

  /// True between a successful restorePurchases() call and the snapshot
  /// batch it emits (the full list of what Play says is owned).
  bool _restoreSnapshotPending = false;

  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  GemIapState build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _sub = null;
    });
    // Errors inside the microtask are caught in [_bootstrap]; never thrown
    // into the app zone.
    if (debugSkipBootstrap) return const GemIapState(available: true);
    Future.microtask(_bootstrap);
    return const GemIapState(loading: true);
  }

  /// Test hook: do not touch the Billing plugin.
  @visibleForTesting
  static bool debugSkipBootstrap = false;

  /// Max wait for Play Billing to report availability.
  static Duration billingTimeout = const Duration(seconds: 10);

  /// True once the purchase stream is attached (test/diagnostic hook).
  bool get listening => _sub != null;

  Future<void> _bootstrap() async {
    if (kIsWeb) {
      state = const GemIapState(
        available: false,
        loading: false,
        lastError: 'Billing unavailable on this platform.',
      );
      return;
    }
    try {
      // Never leave the Shop spinning if Billing does not answer.
      final available = await _iap.isAvailable().timeout(billingTimeout);
      if (!available) {
        state = const GemIapState(
          available: false,
          loading: false,
          lastError: 'Play Billing unavailable.',
        );
        return;
      }
      _sub ??= _iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e, StackTrace st) {
          debugPrint('GemIap: purchaseStream error: $e\n$st');
          state = state.copyWith(
            lastError: 'Purchase stream error — try again later.',
            clearPurchasing: true,
          );
        },
      );
      await refreshProducts();
      // Re-deliver gem packs that were paid for but never completed (e.g. the
      // app died mid-purchase) so they are credited and acknowledged instead
      // of being auto-refunded by Play after 3 days. Consumed packs are not
      // returned, so this cannot double-credit a finished purchase.
      try {
        await _restoreWithSnapshot();
      } catch (e, st) {
        debugPrint('GemIap: restorePurchases failed (non-fatal): $e\n$st');
      }
    } catch (e, st) {
      debugPrint('GemIap: bootstrap failed: $e\n$st');
      state = GemIapState(
        available: false,
        loading: false,
        lastError: 'Billing failed to start.',
      );
    }
  }

  Future<void> refreshProducts() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final response = await _iap
          .queryProductDetails(
              {...GemPack.bootstrapProductIds, RemoveAds.productId})
          .timeout(billingTimeout);
      if (response.error != null) {
        debugPrint('GemIap: query error ${response.error}');
        state = state.copyWith(
          available: true,
          loading: false,
          lastError: 'Could not load gem packs.',
        );
        return;
      }
      final map = <String, ProductDetails>{
        for (final p in response.productDetails) p.id: p,
      };
      state = state.copyWith(
        available: true,
        loading: false,
        products: map,
        clearError: true,
      );
    } catch (e, st) {
      debugPrint('GemIap: refreshProducts failed: $e\n$st');
      state = state.copyWith(
        available: false,
        loading: false,
        lastError: 'Could not load gem packs.',
      );
    }
  }

  /// Lazily query the weekend SKU (Shop open). Never throws; merges into
  /// existing products on success.
  Future<void> loadWeekendProduct() async {
    if (state.products.containsKey(GemPack.weekend.productId)) return;
    try {
      final response = await _iap
          .queryProductDetails({GemPack.weekend.productId})
          .timeout(billingTimeout);
      if (response.error != null) {
        debugPrint('GemIap: weekend query error ${response.error}');
        return;
      }
      final extra = <String, ProductDetails>{
        for (final p in response.productDetails) p.id: p,
      };
      if (extra.isEmpty) return;
      state = state.copyWith(products: {...state.products, ...extra});
    } catch (e, st) {
      debugPrint('GemIap: loadWeekendProduct failed (non-fatal): $e\n$st');
    }
  }

  /// Start a consumable purchase. Credits the main gem bank on success.
  Future<bool> buy(GemPack pack) async {
    if (!pack.isOfferedAt()) {
      state = state.copyWith(lastError: 'Weekend bag is back on Friday.');
      return false;
    }
    final details = state.products[pack.productId];
    if (details == null) {
      state = state.copyWith(lastError: 'Pack not available yet.');
      return false;
    }
    if (state.purchasingId != null) return false;
    state = state.copyWith(purchasingId: pack.productId, clearError: true);
    try {
      final param = PurchaseParam(productDetails: details);
      final started = await _iap.buyConsumable(purchaseParam: param);
      if (!started) {
        state = state.copyWith(
          clearPurchasing: true,
          lastError: 'Purchase did not start.',
        );
      }
      return started;
    } catch (e, st) {
      debugPrint('GemIap: buy failed: $e\n$st');
      state = state.copyWith(
        clearPurchasing: true,
        lastError: 'Purchase failed — no charge applied.',
      );
      return false;
    }
  }

  /// Start the Remove Ads **non-consumable** purchase. Never consumed:
  /// [completePurchase] only acknowledges it, so Play keeps it owned and
  /// returns it from [restore] after a reinstall.
  Future<bool> buyRemoveAds() async {
    if (RemoveAds.owned.value) return false;
    final details = state.products[RemoveAds.productId];
    if (details == null) {
      state = state.copyWith(lastError: 'Remove ads is not available yet.');
      return false;
    }
    if (state.purchasingId != null) return false;
    state = state.copyWith(purchasingId: RemoveAds.productId, clearError: true);
    try {
      final param = PurchaseParam(productDetails: details);
      final started = await _iap.buyNonConsumable(purchaseParam: param);
      if (!started) {
        state = state.copyWith(
          clearPurchasing: true,
          lastError: 'Purchase did not start.',
        );
      }
      return started;
    } catch (e, st) {
      debugPrint('GemIap: remove-ads buy failed: $e\n$st');
      state = state.copyWith(
        clearPurchasing: true,
        lastError: 'Purchase failed — no charge applied.',
      );
      return false;
    }
  }

  /// "Restore purchase": asks Play to re-deliver owned non-consumables.
  /// Restored items arrive on the purchase stream as [PurchaseStatus.restored].
  Future<bool> restore() async {
    try {
      await _restoreWithSnapshot().timeout(billingTimeout);
      return true;
    } catch (e, st) {
      debugPrint('GemIap: restore failed: $e\n$st');
      state = state.copyWith(lastError: 'Could not reach Google Play.');
      return false;
    }
  }

  /// restorePurchases() throws on any Billing error (then nothing is
  /// emitted and ownership is left alone). On success it emits ONE batch of
  /// every owned purchase, all [PurchaseStatus.restored] — possibly empty.
  Future<void> _restoreWithSnapshot() async {
    _restoreSnapshotPending = true;
    try {
      await _iap.restorePurchases();
    } catch (_) {
      _restoreSnapshotPending = false;
      rethrow;
    }
  }

  @visibleForTesting
  void debugExpectRestoreSnapshot() => _restoreSnapshotPending = true;

  @visibleForTesting
  Future<void> debugOnPurchases(List<PurchaseDetails> purchases) =>
      _onPurchases(purchases);

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    final snapshot =
        _restoreSnapshotPending &&
        purchases.every((p) => p.status == PurchaseStatus.restored);
    if (snapshot) _restoreSnapshotPending = false;
    for (final purchase in purchases) {
      try {
        await _handlePurchase(purchase);
      } catch (e, st) {
        // Fail closed: an unexpected purchase (e.g. weekend SKU arriving in an
        // upgrade restore before its details were queried) must never kill
        // the app. Not completed here, so Play re-delivers it next launch.
        debugPrint('GemIap: handle ${purchase.productID} failed: $e\n$st');
      }
    }
    if (snapshot) {
      try {
        await reconcileRemoveAds(purchases);
      } catch (e, st) {
        debugPrint('GemIap: reconcileRemoveAds failed: $e\n$st');
      }
    }
  }

  /// Play's restore snapshot is the source of truth: a restore can grant,
  /// and absence revokes (refund / chargeback / revoked in Play Console).
  @visibleForTesting
  static Future<void> reconcileRemoveAds(List<PurchaseDetails> snapshot) async {
    final ownedOnPlay = snapshot.any(
      (p) => p.productID == RemoveAds.productId && !isPendingOnPlay(p),
    );
    if (!ownedOnPlay && RemoveAds.owned.value) {
      debugPrint('GemIap: marge_remove_ads not owned on Play — revoking');
      await RemoveAds.revoke();
    }
  }

  /// The Android plugin reports every queried purchase as `restored`, even
  /// ones still awaiting payment (e.g. cash). Those must not grant.
  static bool isPendingOnPlay(PurchaseDetails p) =>
      p is GooglePlayPurchaseDetails &&
      p.billingClientPurchase.purchaseState == PurchaseStateWrapper.pending;

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (purchase.productID == RemoveAds.productId) {
      await handleRemoveAdsPurchase(
        purchase,
        complete: (p) => _iap.completePurchase(p),
      );
      return;
    }
    final pack = GemPack.byId(purchase.productID);
    if (pack == null) {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      return;
    }

    switch (purchase.status) {
      case PurchaseStatus.pending:
        state = state.copyWith(purchasingId: pack.productId);
        return;
      case PurchaseStatus.error:
        debugPrint('GemIap: purchase error ${purchase.error}');
        state = state.copyWith(
          clearPurchasing: true,
          lastError: 'Purchase error — no gems credited.',
        );
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        return;
      case PurchaseStatus.canceled:
        state = state.copyWith(clearPurchasing: true, clearError: true);
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        break;
    }

    final dedupe =
        purchase.purchaseID ??
        '${purchase.productID}:${purchase.transactionDate}';
    if (_handledPurchaseIds.contains(dedupe)) {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      return;
    }
    _handledPurchaseIds.add(dedupe);

    final name = ref.read(settingsProvider).playerName;
    final next = ref
        .read(coinLedgerProvider.notifier)
        .grantHumanPlayCoins(name, cents: pack.gems);
    if (next == null) {
      debugPrint('GemIap: grant refused for ${pack.productId}');
      state = state.copyWith(
        clearPurchasing: true,
        lastError:
            'Could not credit gems. Email ${LegalLinks.supportEmail} '
            'with your Google Play receipt.',
      );
    } else {
      state = state.copyWith(clearPurchasing: true, clearError: true);
    }

    if (purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
      } catch (e, st) {
        debugPrint('GemIap: completePurchase failed: $e\n$st');
      }
    }
  }

  /// Remove Ads (non-consumable) purchase update. Visible for tests.
  @visibleForTesting
  Future<void> handleRemoveAdsPurchase(
    PurchaseDetails purchase, {
    required Future<void> Function(PurchaseDetails) complete,
  }) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        state = state.copyWith(purchasingId: RemoveAds.productId);
        return;
      case PurchaseStatus.error:
        debugPrint('GemIap: remove-ads error ${purchase.error}');
        state = state.copyWith(
          clearPurchasing: true,
          lastError: 'Purchase error — ads unchanged, no charge applied.',
        );
        break;
      case PurchaseStatus.canceled:
        state = state.copyWith(clearPurchasing: true, clearError: true);
        break;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        if (isPendingOnPlay(purchase)) {
          // Paid-later purchase not settled yet: no grant, no acknowledge.
          state = state.copyWith(purchasingId: RemoveAds.productId);
          return;
        }
        // Unlike gem packs, a restore MUST grant again (reinstall / new
        // device). Granting is idempotent, so no purchaseID de-dupe.
        await RemoveAds.grant();
        state = state.copyWith(clearPurchasing: true, clearError: true);
        break;
    }
    if (purchase.pendingCompletePurchase) {
      // Acknowledge only. Bought with buyNonConsumable, so the plugin never
      // consumes it and Play keeps it owned for restore.
      try {
        await complete(purchase);
      } catch (e, st) {
        debugPrint('GemIap: remove-ads acknowledge failed: $e\n$st');
      }
    }
  }
}

final gemIapProvider = NotifierProvider<GemIapNotifier, GemIapState>(
  GemIapNotifier.new,
);
