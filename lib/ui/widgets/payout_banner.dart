import 'package:flutter/material.dart';

import '../../engine/turn_state.dart';
import '../theme/marge_theme.dart';

class PayoutBanner extends StatelessWidget {
  const PayoutBanner({super.key, required this.event});

  final PayoutEvent event;

  @override
  Widget build(BuildContext context) {
    final bg = event.celebratory
        ? MargeColors.gold
        : event.amountCents > 0 && event.kind.name != 'none'
            ? MargeColors.sky
            : MargeColors.chipBlue;

    final fg = event.celebratory ? MargeColors.velvet : MargeColors.cream;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              event.celebratory ? '🎉' : '💸',
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                event.message,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
