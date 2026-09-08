import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_ids.dart';
import 'interstitial_gate.dart';

/// Whether this build can host AdMob (mobile native only; not web/desktop).
///
/// [kAdmobEnabled] defaults to false (`--dart-define=ADMOB_ENABLED=true` to
/// turn ads back on). When false, no UMP / MobileAds / ad-load calls run.
bool get adsPlatformSupported =>
    kAdmobEnabled &&
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Bootstraps UMP consent + Mobile Ads SDK, and owns interstitial / rewarded.
class AdsService {
  AdsService();

  final InterstitialGate interstitialGate = InterstitialGate();

  bool _initialized = false;
  bool _consentReady = false;
  bool _mobileAdsInitialized = false;
  bool _startingAds = false;

  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;

  RewardedAd? _rewarded;
  bool _loadingRewarded = false;

  bool get isReady => _initialized && _consentReady && _mobileAdsInitialized;

  bool get canRequestAdsFlag => _consentReady;

  /// Run once after first frame (never await before [runApp]). Safe on
  /// unsupported platforms (no-op). Never throws — ads failures must not
  /// abort cold start.
  Future<void> bootstrap() async {
    if (_initialized) return;
    _initialized = true;
    if (!kAdmobEnabled) {
      debugPrint('AdsService: ADMOB_ENABLED=false — skip MobileAds/UMP');
      return;
    }
    if (!adsPlatformSupported) {
      debugPrint('AdsService: platform unsupported — ads disabled');
      return;
    }
    // Platform channel errors from UMP/GMA can surface as uncaught async
    // zone errors (not only as thrown Futures). Contain them so ads never
    // abort the app isolate after lobby is up.
    final done = Completer<void>();
    runZonedGuarded(
      () async {
        try {
          await _gatherConsentThenInit();
        } catch (e, st) {
          debugPrint('AdsService: bootstrap failed: $e\n$st');
          try {
            _consentReady = true;
            await _ensureMobileAdsInitialized();
          } catch (e2, st2) {
            debugPrint(
              'AdsService: fail-open MobileAds init failed: $e2\n$st2',
            );
          }
        } finally {
          if (!done.isCompleted) done.complete();
        }
      },
      (e, st) {
        debugPrint('AdsService: uncaught ads zone error: $e\n$st');
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
  }

  Future<void> _gatherConsentThenInit() async {
    final completer = Completer<void>();
    final params = ConsentRequestParameters();

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          try {
            ConsentForm.loadAndShowConsentFormIfRequired((
              FormError? error,
            ) async {
              if (error != null) {
                debugPrint(
                  'AdsService: consent form error ${error.errorCode}: ${error.message}',
                );
              }
              await _finishConsentAndMaybeInitAds();
              if (!completer.isCompleted) completer.complete();
            });
          } catch (e, st) {
            debugPrint('AdsService: loadAndShowConsentForm failed: $e\n$st');
            await _finishConsentAndMaybeInitAds();
            if (!completer.isCompleted) completer.complete();
          }
        },
        (FormError error) async {
          debugPrint(
            'AdsService: consent info error ${error.errorCode}: ${error.message}',
          );
          await _finishConsentAndMaybeInitAds();
          if (!completer.isCompleted) completer.complete();
        },
      );
    } catch (e, st) {
      debugPrint('AdsService: requestConsentInfoUpdate failed: $e\n$st');
      await _finishConsentAndMaybeInitAds();
      if (!completer.isCompleted) completer.complete();
    }

    // Don't hang forever if UMP never callbacks (post-runApp, so UI already up).
    await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () async {
        debugPrint('AdsService: consent timed out — continuing');
        await _finishConsentAndMaybeInitAds();
      },
    );
  }

  Future<void> _finishConsentAndMaybeInitAds() async {
    if (!adsPlatformSupported) return;
    try {
      final allowed = await ConsentInformation.instance.canRequestAds();
      _consentReady = allowed;
      if (allowed) {
        await _ensureMobileAdsInitialized();
      } else {
        debugPrint(
          'AdsService: canRequestAds=false — deferring MobileAds init',
        );
      }
    } catch (e) {
      debugPrint('AdsService: consent finish failed: $e');
      // Fail open for test builds so Google test IDs still load outside EEA.
      _consentReady = true;
      await _ensureMobileAdsInitialized();
    }
  }

  Future<void> _ensureMobileAdsInitialized() async {
    if (_mobileAdsInitialized || _startingAds) return;
    _startingAds = true;
    try {
      final ads = MobileAds.instance;
      await ads.initialize();
      _mobileAdsInitialized = true;
      debugPrint(
        'AdsService: MobileAds ready '
        '(testDefaults=${AdIds.usingTestDefaults})',
      );
      unawaited(preloadInterstitial());
      unawaited(preloadRewarded());
    } catch (e) {
      debugPrint('AdsService: MobileAds.initialize failed: $e');
    } finally {
      _startingAds = false;
    }
  }

  /// Re-check consent (e.g. after privacy options). May unlock ads.
  Future<void> refreshConsentAndAds() async {
    if (!kAdmobEnabled || !adsPlatformSupported) return;
    await _finishConsentAndMaybeInitAds();
  }

  Future<bool> isPrivacyOptionsRequired() async {
    if (!kAdmobEnabled || !adsPlatformSupported) return false;
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  Future<void> showPrivacyOptions() async {
    if (!kAdmobEnabled || !adsPlatformSupported) return;
    final completer = Completer<void>();
    try {
      ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (error != null) {
          debugPrint(
            'AdsService: privacy options ${error.errorCode}: ${error.message}',
          );
        }
        if (!completer.isCompleted) completer.complete();
      });
    } catch (e, st) {
      debugPrint('AdsService: showPrivacyOptions failed: $e\n$st');
      if (!completer.isCompleted) completer.complete();
    }
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('AdsService: privacy options timed out');
      },
    );
    await refreshConsentAndAds();
  }

  Future<bool> _adsAllowed() async {
    if (!kAdmobEnabled || !adsPlatformSupported) return false;
    if (!_mobileAdsInitialized) {
      try {
        final allowed = await ConsentInformation.instance.canRequestAds();
        if (!allowed) return false;
        await _ensureMobileAdsInitialized();
      } catch (_) {
        return false;
      }
    }
    return _mobileAdsInitialized;
  }

  AdRequest _request() {
    // UMP gates personalized vs non-personalized; RequestConfiguration is
    // managed by the SDK after consent. Empty AdRequest is correct here.
    return const AdRequest();
  }

  Future<void> preloadInterstitial() async {
    if (_loadingInterstitial || _interstitial != null) return;
    if (!await _adsAllowed()) return;
    _loadingInterstitial = true;
    await InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: _request(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loadingInterstitial = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitial = null;
              unawaited(preloadInterstitial());
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('AdsService: interstitial show failed: $error');
              ad.dispose();
              _interstitial = null;
              unawaited(preloadInterstitial());
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('AdsService: interstitial load failed: $error');
          _loadingInterstitial = false;
          _interstitial = null;
        },
      ),
    );
  }

  Future<void> preloadRewarded() async {
    if (_loadingRewarded || _rewarded != null) return;
    if (!await _adsAllowed()) return;
    _loadingRewarded = true;
    await RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: _request(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _loadingRewarded = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('AdsService: rewarded load failed: $error');
          _loadingRewarded = false;
          _rewarded = null;
        },
      ),
    );
  }

  /// Call when a match ends (before leaving the table / rematch).
  void notifyMatchCompleted() {
    interstitialGate.onMatchCompleted();
  }

  /// Show interstitial only at a natural break if the frequency gate allows.
  /// Returns true if an ad was presented.
  Future<bool> maybeShowInterstitialAtBreak() async {
    if (!kAdmobEnabled) return false;
    if (!interstitialGate.canShow) return false;
    if (!await _adsAllowed()) return false;

    var ad = _interstitial;
    if (ad == null) {
      await preloadInterstitial();
      ad = _interstitial;
    }
    if (ad == null) return false;

    interstitialGate.onShown();
    _interstitial = null;
    await ad.show();
    return true;
  }

  /// Show a rewarded ad. On earn reward, invokes [onReward] (grant virtual chips).
  /// Returns true if the user earned the reward.
  Future<bool> showRewardedForVirtualChips({
    required FutureOr<void> Function(int amount) onReward,
  }) async {
    if (!kAdmobEnabled) return false;
    if (!await _adsAllowed()) {
      // Test / unsupported: still allow a local grant in debug when using
      // test IDs so UI wiring can be verified without a device ad fill.
      if (kDebugMode && !adsPlatformSupported) {
        await onReward(AdIds.rewardedChipGrant);
        return true;
      }
      return false;
    }

    var ad = _rewarded;
    if (ad == null) {
      await preloadRewarded();
      ad = _rewarded;
    }
    if (ad == null) return false;

    final earned = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewarded = null;
        unawaited(preloadRewarded());
        if (!earned.isCompleted) earned.complete(false);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdsService: rewarded show failed: $error');
        ad.dispose();
        _rewarded = null;
        unawaited(preloadRewarded());
        if (!earned.isCompleted) earned.complete(false);
      },
    );

    _rewarded = null;
    await ad.show(
      onUserEarnedReward: (AdWithoutView unused, RewardItem reward) async {
        await onReward(AdIds.rewardedChipGrant);
        if (!earned.isCompleted) earned.complete(true);
      },
    );
    return earned.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => false,
    );
  }

  void dispose() {
    _interstitial?.dispose();
    _interstitial = null;
    _rewarded?.dispose();
    _rewarded = null;
  }
}

/// Process-wide ads service (bootstrapped from [main] after first frame).
final adsServiceProvider = Provider<AdsService>((ref) {
  final service = AdsService();
  ref.onDispose(service.dispose);
  return service;
});
