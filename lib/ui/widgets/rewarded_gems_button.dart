import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ad_ids.dart';
import '../../ads/ads_service.dart';
import '../../engine/gem_label.dart';
import '../../services/coin_ledger.dart';
import '../../services/rewarded_quota.dart';
import '../../services/settings_service.dart';

/// "Watch for +50" — rewarded ad that credits [AdIds.rewardedShortfallGrant]
/// gems to the main gem bank. Shares the 3/day Denver quota with the
/// post-match double. Hidden in ads-off builds; disabled when the quota is
/// spent. Remove Ads ownership does not hide it (rewarded stays opt-in).
class RewardedShortfallButton extends ConsumerStatefulWidget {
  const RewardedShortfallButton({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<RewardedShortfallButton> createState() =>
      _RewardedShortfallButtonState();
}

class _RewardedShortfallButtonState
    extends ConsumerState<RewardedShortfallButton> {
  var _busy = false;

  Future<void> _watch() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ads = ref.read(adsServiceProvider);
      final name = ref.read(settingsProvider).playerName;
      final earned = await ads.showRewardedForVirtualChips(
        amount: AdIds.rewardedShortfallGrant,
        onReward: (amount) async {
          ref
              .read(coinLedgerProvider.notifier)
              .grantHumanPlayCoins(name, cents: amount);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            earned
                ? 'Earned ${gemCount(AdIds.rewardedShortfallGrant)} virtual gems. Not real money.'
                : 'Ad unavailable — try again later.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kAdmobEnabled) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: RewardedQuota.remainingNotifier,
      builder: (context, _, _) {
        final left = RewardedQuota.remaining();
        final label = _busy
            ? 'Loading…'
            : left > 0
            ? 'Watch for +${AdIds.rewardedShortfallGrant} ($left left today)'
            : 'No more videos today';
        final onPressed = (_busy || left <= 0) ? null : _watch;
        final icon = _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ondemand_video_rounded);
        if (widget.compact) {
          return TextButton.icon(
            key: const ValueKey('rewarded-shortfall'),
            onPressed: onPressed,
            icon: icon,
            label: Text(label),
          );
        }
        return FilledButton.icon(
          key: const ValueKey('rewarded-shortfall'),
          onPressed: onPressed,
          icon: icon,
          label: Text(label),
        );
      },
    );
  }
}
