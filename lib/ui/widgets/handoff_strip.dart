import 'package:flutter/material.dart';

import '../../cosmetics/dice_skin.dart';
import '../../engine/engine.dart';
import '../theme/marge_theme.dart';
import 'die_widget.dart';

/// Bottom sticky strip after a turn settles: locked dice, outcome, bank delta,
/// and a single Next player / Continue CTA (no timer, no second confirm).
class HandoffStrip extends StatelessWidget {
  const HandoffStrip({
    super.key,
    required this.handoff,
    required this.hotseat,
    required this.onConfirm,
    this.skinTheme,
  });

  final HandoffState handoff;
  final bool hotseat;
  final VoidCallback onConfirm;
  final DiceSkinTheme? skinTheme;

  @override
  Widget build(BuildContext context) {
    final delta = handoff.bankDeltaCents;
    final deltaLabel = delta > 0
        ? '+$delta¢'
        : delta < 0
            ? '$delta¢'
            : '0¢';
    final deltaColor = delta > 0
        ? MargeColors.gold
        : delta < 0
            ? MargeColors.coral
            : MargeColors.cream;

    return Material(
      elevation: 12,
      color: const Color(0xFF160A30),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (var i = 0; i < handoff.diceValues.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    DieWidget(
                      value: handoff.diceValues[i],
                      kept: true,
                      enabled: false,
                      size: 44,
                      theme: skinTheme,
                    ),
                  ],
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          handoff.outcomeText,
                          style: const TextStyle(
                            color: MargeColors.cream,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          deltaLabel,
                          style: TextStyle(
                            color: deltaColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: MargeColors.gold,
                    foregroundColor: MargeColors.velvet,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        hotseat ? 'Next player' : 'Continue',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      if (hotseat) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Pass the phone',
                          style: TextStyle(
                            color: MargeColors.velvet.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
