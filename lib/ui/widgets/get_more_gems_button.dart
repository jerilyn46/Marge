import 'package:flutter/material.dart';

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

  static Future<void> openShop(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ShopScreen()),
    );
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
