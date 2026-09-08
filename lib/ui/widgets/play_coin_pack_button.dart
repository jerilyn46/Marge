import 'package:flutter/material.dart';

import '../theme/marge_theme.dart';

/// Free play-money pack control. Not a cash purchase and not Play Billing.
class PlayCoinPackButton extends StatelessWidget {
  const PlayCoinPackButton({
    super.key,
    required this.onPressed,
    this.compact = false,
  });

  /// Visible label. Must stay obviously play money, not a cash checkout.
  static const label = 'Add 100¢ play coins';

  static const hint = 'Free play money. Not a real purchase.';

  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(Icons.savings_outlined, size: compact ? 18 : 20),
      label: const Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: MargeColors.gold,
        side: const BorderSide(color: MargeColors.gold),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 8 : 12,
        ),
        textStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: compact ? 13 : 15,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        SizedBox(height: compact ? 2 : 4),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MargeColors.cream.withValues(alpha: 0.72),
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
