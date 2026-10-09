import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../match_provider.dart';

import '../screens/shop_screen.dart';
import '../theme/marge_theme.dart';

/// Soft lobby / match-end CTA into Shop. Never a mid-match interrupt.
class GetMoreGemsButton extends StatelessWidget {
  const GetMoreGemsButton({
    super.key,
    this.compact = false,
    this.label = 'Get more gems',
  });

  final bool compact;
  final String label;

  /// Open the Shop. If a match is live, it is frozen (bots wait, table
  /// saved) and picked back up unchanged when the Shop closes — the pot and
  /// turn are never reset by a trip to the store.
  static Future<void> openShop(BuildContext context) async {
    MatchNotifier? match;
    try {
      match = ProviderScope.containerOf(context, listen: false)
          .read(matchProvider.notifier);
    } catch (_) {
      match = null;
    }
    match?.suspendForShop();
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ShopScreen()),
      );
    } finally {
      match?.resumeAfterShop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return TextButton(
        onPressed: () => openShop(context),
        child: Text(
          label,
          style: const TextStyle(
            color: MargeColors.gold,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => openShop(context),
      icon: const Icon(Icons.diamond_outlined, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: MargeColors.gold,
        side: BorderSide(color: MargeColors.gold.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
