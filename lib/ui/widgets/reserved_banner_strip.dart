import 'package:flutter/material.dart';

import '../../ads/ad_ids.dart';
import '../../ads/ads_service.dart';
import '../../ads/banner_ad_widget.dart';
import '../theme/marge_theme.dart';

/// Lobby reserved band: AdMob banner when ads are enabled and ready;
/// quiet house art otherwise (fail closed — never crashes the lobby).
///
/// Never place on [MatchScreen] or over Roll / Keep.
class ReservedBannerStrip extends StatelessWidget {
  const ReservedBannerStrip({super.key});

  @override
  Widget build(BuildContext context) {
    if (kAdmobEnabled && adsPlatformSupported) {
      return Semantics(
        label: 'Lobby advertisement',
        child: const ColoredBox(
          color: Colors.transparent,
          child: Center(child: LobbyBannerAd()),
        ),
      );
    }
    return Semantics(
      label: 'Reserved decorative band',
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              MargeColors.wood.withValues(alpha: 0.28),
              MargeColors.felt.withValues(alpha: 0.45),
              MargeColors.wood.withValues(alpha: 0.28),
            ],
          ),
          border: Border.all(
            color: MargeColors.woodEdge.withValues(alpha: 0.35),
          ),
        ),
        child: Center(
          child: Text(
            'Evening table',
            style: TextStyle(
              color: MargeColors.cream.withValues(alpha: 0.35),
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
