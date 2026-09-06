/// AdMob IDs resolved from `--dart-define` with Google official **test** defaults.
///
/// Never commit production App / unit IDs. Inject them at build time only.
///
/// Dart-define keys:
/// - `ADMOB_APP_ID` (documented; Android also uses Gradle `-PADMOB_APP_ID=`)
/// - `ADMOB_BANNER_ID`
/// - `ADMOB_INTERSTITIAL_ID`
/// - `ADMOB_REWARDED_ID`
class AdIds {
  AdIds._();

  static const String appIdDefine = 'ADMOB_APP_ID';
  static const String bannerDefine = 'ADMOB_BANNER_ID';
  static const String interstitialDefine = 'ADMOB_INTERSTITIAL_ID';
  static const String rewardedDefine = 'ADMOB_REWARDED_ID';

  /// Google sample / test AdMob **App ID** (Android).
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';

  /// Google official Android **test** unit IDs.
  static const String testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const String testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  /// Virtual chips granted after a successful rewarded ad (cosmetics wallet).
  static const int rewardedChipGrant = 25;

  static String get appId {
    const v = String.fromEnvironment(appIdDefine, defaultValue: '');
    return v.isEmpty ? testAppId : v;
  }

  static String get banner {
    const v = String.fromEnvironment(bannerDefine, defaultValue: '');
    return v.isEmpty ? testBanner : v;
  }

  static String get interstitial {
    const v = String.fromEnvironment(interstitialDefine, defaultValue: '');
    return v.isEmpty ? testInterstitial : v;
  }

  static String get rewarded {
    const v = String.fromEnvironment(rewardedDefine, defaultValue: '');
    return v.isEmpty ? testRewarded : v;
  }

  /// True when all resolved IDs are still Google's public test samples.
  static bool get usingTestDefaults =>
      appId == testAppId &&
      banner == testBanner &&
      interstitial == testInterstitial &&
      rewarded == testRewarded;
}
