import 'package:flutter/material.dart';

import '../theme/marge_theme.dart';

/// Visual "heat" meter for the pot.
class PotMeter extends StatelessWidget {
  const PotMeter({super.key, required this.potCents, this.maxHint = 200});

  final int potCents;
  final int maxHint;

  @override
  Widget build(BuildContext context) {
    final t = (potCents / maxHint).clamp(0.0, 1.0);
    final heat = Color.lerp(MargeColors.sky, MargeColors.coral, t)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MargeColors.felt,
            Color.lerp(MargeColors.felt, heat, 0.35)!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: heat.withValues(alpha: 0.7), width: 2),
        boxShadow: [
          BoxShadow(
            color: heat.withValues(alpha: 0.35),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'POT',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 3,
                  color: MargeColors.gold,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '$potCents¢',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: MargeColors.cream,
                ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: t,
              minHeight: 10,
              backgroundColor: Colors.black26,
              color: heat,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t > 0.75
                ? '🔥 HOT POT'
                : t > 0.4
                    ? 'Warming up…'
                    : 'Ante brewing',
            style: TextStyle(
              color: heat,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
