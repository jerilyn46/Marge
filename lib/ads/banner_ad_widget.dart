import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_ids.dart';
import 'ads_service.dart';

/// Anchored banner for the **main menu / lobby only**.
///
/// Do not place on [MatchScreen] or over active dice/roll UI.
class LobbyBannerAd extends ConsumerStatefulWidget {
  const LobbyBannerAd({super.key});

  @override
  ConsumerState<LobbyBannerAd> createState() => _LobbyBannerAdState();
}

class _LobbyBannerAdState extends ConsumerState<LobbyBannerAd> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  Future<void> _loadIfNeeded() async {
    if (_banner != null || !adsPlatformSupported) return;
    final ads = ref.read(adsServiceProvider);
    // Wait briefly for consent + SDK init started in main().
    for (var i = 0; i < 30 && !ads.isReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (!adsPlatformSupported) return;
      // canRequestAds may still unlock later
      if (ads.canRequestAdsFlag && !ads.isReady) {
        await ads.refreshConsentAndAds();
      }
      if (ads.isReady) break;
    }
    if (!mounted || !ads.isReady) return;

    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;

    final banner = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('LobbyBannerAd: failed to load: $error');
          ad.dispose();
          if (mounted) {
            setState(() {
              _banner = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    setState(() => _banner = banner);
    await banner.load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!adsPlatformSupported) {
      return const SizedBox.shrink();
    }
    final banner = _banner;
    if (!_loaded || banner == null) {
      return const SizedBox(height: 0);
    }
    return SizedBox(
      width: banner.size.width.toDouble(),
      height: banner.size.height.toDouble(),
      child: AdWidget(ad: banner),
    );
  }
}
