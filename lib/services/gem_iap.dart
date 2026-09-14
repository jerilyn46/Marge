import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'coin_ledger.dart';
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

  static const all = <GemPack>[small, medium, large];

  static GemPack? byId(String id) {
    for (final p in all) {
      if (p.productId == id) return p;
    }
    return null;
  }

  static Set<String> get productIds => {for (final p in all) p.productId};
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
  }) =>
      GemIapState(
        available: available ?? this.available,
        loading: loading ?? this.loading,
        products: products ?? this.products,
        lastError: clearError ? null : (lastError ?? this.lastError),
        purchasingId:
            clearPurchasing ? null : (purchasingId ?? this.purchasingId),
      );
}

/// Thin Play Billing wrapper. Credits [PlayerCoinLedger] only — never cash-out.
class GemIapNotifier extends Notifier<GemIapState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Set<String> _handledPurchaseIds = {};

  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  GemIapState build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _sub = null;
    });
    Future.microtask(_bootstrap);
    return const GemIapState(loading: true);
  }

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
      final available = await _iap.isAvailable();
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
      final response = await _iap.queryProductDetails(GemPack.productIds);
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

  /// Start a consumable purchase. Credits the main gem bank on success.
  Future<bool> buy(GemPack pack) async {
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

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      await _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
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

    final dedupe = purchase.purchaseID ??
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
        lastError: 'Could not credit gems — contact support with receipt.',
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
}

final gemIapProvider = NotifierProvider<GemIapNotifier, GemIapState>(
  GemIapNotifier.new,
);
