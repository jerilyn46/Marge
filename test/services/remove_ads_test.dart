import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:marge/ads/ads_service.dart';
import 'package:marge/services/gem_iap.dart';
import 'package:marge/services/remove_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

PurchaseDetails _p(PurchaseStatus status, {bool pending = true}) =>
    PurchaseDetails(
      purchaseID: 'GPA.remove-ads-1',
      productID: RemoveAds.productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'google_play',
      ),
      transactionDate: '0',
      status: status,
    )..pendingCompletePurchase = pending;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoveAds.debugReset();
  });

  test('product ID is marge_remove_ads; gem pack SKUs unchanged', () {
    expect(RemoveAds.productId, 'marge_remove_ads');
    expect(GemPack.productIds, {
      'marge_gems_small',
      'marge_gems_medium',
      'marge_gems_large',
    });
    expect(GemPack.byId(RemoveAds.productId), isNull);
  });

  test('grant persists and survives a cold start', () async {
    expect(await RemoveAds.load(), isFalse);
    await RemoveAds.grant();
    expect(RemoveAds.owned.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(RemoveAds.prefsKey), isTrue);

    RemoveAds.owned.value = false; // simulate process death
    expect(await RemoveAds.load(), isTrue);
  });

  test('reinstall (empty prefs) starts unowned until Play restores', () async {
    expect(await RemoveAds.load(), isFalse);
  });

  group('purchase handling (non-consumable)', () {
    late ProviderContainer c;
    late List<PurchaseDetails> completed;
    Future<void> complete(PurchaseDetails p) async => completed.add(p);

    setUp(() async {
      completed = [];
      GemIapNotifier.debugSkipBootstrap = true;
      c = ProviderContainer();
    });
    tearDown(() {
      c.dispose();
      GemIapNotifier.debugSkipBootstrap = false;
    });

    test('purchased grants and acknowledges once', () async {
      await c
          .read(gemIapProvider.notifier)
          .handleRemoveAdsPurchase(
            _p(PurchaseStatus.purchased),
            complete: complete,
          );
      expect(RemoveAds.owned.value, isTrue);
      expect(c.read(removeAdsOwnedProvider), isTrue);
      expect(completed, hasLength(1));
      expect(c.read(gemIapProvider).purchasingId, isNull);
    });

    test('restored (reinstall) grants again, no de-dupe skip', () async {
      final n = c.read(gemIapProvider.notifier);
      await n.handleRemoveAdsPurchase(
        _p(PurchaseStatus.restored, pending: false),
        complete: complete,
      );
      expect(RemoveAds.owned.value, isTrue);
      expect(completed, isEmpty); // already acknowledged
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(RemoveAds.prefsKey), isTrue);
    });

    test('pending shows spinner state, grants nothing', () async {
      await c
          .read(gemIapProvider.notifier)
          .handleRemoveAdsPurchase(
            _p(PurchaseStatus.pending, pending: false),
            complete: complete,
          );
      expect(c.read(gemIapProvider).purchasingId, RemoveAds.productId);
      expect(RemoveAds.owned.value, isFalse);
    });

    test('error and cancel grant nothing', () async {
      final n = c.read(gemIapProvider.notifier);
      await n.handleRemoveAdsPurchase(
        _p(PurchaseStatus.error),
        complete: complete,
      );
      expect(c.read(gemIapProvider).lastError, isNotNull);
      await n.handleRemoveAdsPurchase(
        _p(PurchaseStatus.canceled),
        complete: complete,
      );
      expect(RemoveAds.owned.value, isFalse);
      expect(c.read(gemIapProvider).purchasingId, isNull);
    });
  });

  test('owned: interstitial never shows', () async {
    await RemoveAds.grant();
    final ads = AdsService()..notifyMatchCompleted();
    expect(await ads.maybeShowInterstitialAtBreak(), isFalse);
  });

  group('restore snapshot reconciles (refund revokes)', () {
    late ProviderContainer c;
    setUp(() {
      GemIapNotifier.debugSkipBootstrap = true;
      c = ProviderContainer();
    });
    tearDown(() {
      c.dispose();
      GemIapNotifier.debugSkipBootstrap = false;
    });

    test('empty snapshot revokes a cached owned flag', () async {
      await RemoveAds.grant();
      final n = c.read(gemIapProvider.notifier)..debugExpectRestoreSnapshot();
      await n.debugOnPurchases(const []);
      expect(RemoveAds.owned.value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(RemoveAds.prefsKey), isNull);
    });

    test('snapshot with the product keeps / grants ownership', () async {
      final n = c.read(gemIapProvider.notifier)..debugExpectRestoreSnapshot();
      await n.debugOnPurchases([_p(PurchaseStatus.restored, pending: false)]);
      expect(RemoveAds.owned.value, isTrue);
    });

    test('snapshot of other products only (gem pack) still revokes', () async {
      await RemoveAds.grant();
      final other = PurchaseDetails(
        purchaseID: 'GPA.gems',
        productID: 'marge_gems_small',
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: '',
          source: 'google_play',
        ),
        transactionDate: '0',
        status: PurchaseStatus.restored,
      );
      final n = c.read(gemIapProvider.notifier)..debugExpectRestoreSnapshot();
      await n.debugOnPurchases([other]);
      expect(RemoveAds.owned.value, isFalse);
    });

    test('no restore in flight: ordinary update never revokes', () async {
      await RemoveAds.grant();
      await c.read(gemIapProvider.notifier).debugOnPurchases(const []);
      expect(RemoveAds.owned.value, isTrue);
    });

    test(
      'a purchase batch during restore is not treated as snapshot',
      () async {
        await RemoveAds.grant();
        final n = c.read(gemIapProvider.notifier)..debugExpectRestoreSnapshot();
        await n.debugOnPurchases([_p(PurchaseStatus.canceled, pending: false)]);
        expect(RemoveAds.owned.value, isTrue);
        // The real snapshot still arrives afterwards and is reconciled.
        await n.debugOnPurchases([_p(PurchaseStatus.restored, pending: false)]);
        expect(RemoveAds.owned.value, isTrue);
      },
    );

    test('Play-pending (pay later) restored purchase does not grant', () async {
      final pending = GooglePlayPurchaseDetails.fromPurchase(
        const PurchaseWrapper(
          orderId: 'o',
          packageName: 'p',
          purchaseTime: 0,
          purchaseToken: 't',
          signature: 's',
          products: [RemoveAds.productId],
          isAutoRenewing: false,
          originalJson: '{}',
          isAcknowledged: false,
          purchaseState: PurchaseStateWrapper.pending,
        ),
      ).single..status = PurchaseStatus.restored;
      expect(GemIapNotifier.isPendingOnPlay(pending), isTrue);
      await GemIapNotifier.reconcileRemoveAds([pending]);
      expect(RemoveAds.owned.value, isFalse);
    });
  });
}
