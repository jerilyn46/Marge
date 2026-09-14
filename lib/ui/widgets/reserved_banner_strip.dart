import 'package:flutter/material.dart';

import '../theme/marge_theme.dart';

/// Quiet reserved lobby band — house art only. Ads stay off; no AdMob.
class ReservedBannerStrip extends StatelessWidget {
  const ReservedBannerStrip({super.key});

  @override
  Widget build(BuildContext context) {
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
