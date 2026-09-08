import 'package:flutter/material.dart';

import '../../engine/player.dart';
import '../theme/marge_theme.dart';

class PlayerChip extends StatelessWidget {
  const PlayerChip({
    super.key,
    required this.player,
    this.isActive = false,
    this.compact = false,
  });

  final PlayerState player;
  final bool isActive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = [
      MargeColors.coral,
      MargeColors.sky,
      MargeColors.gold,
      MargeColors.lilac,
      MargeColors.chipBlue,
    ];
    final accent = colors[player.profile.colorSeed % colors.length];
    final waiting = player.profile.isWaiting;
    final active = isActive && !waiting;

    return Opacity(
      opacity: waiting ? 0.72 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 10,
        ),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: waiting ? 0.18 : 0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? accent
                : (waiting
                      ? MargeColors.gold.withValues(alpha: 0.45)
                      : Colors.white24),
            width: active ? 2.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              player.profile.avatarEmoji,
              style: TextStyle(fontSize: compact ? 18 : 22),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  player.profile.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 12 : 14,
                    color: player.eliminated || waiting
                        ? Colors.white70
                        : MargeColors.cream,
                    decoration: player.eliminated
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                Text(
                  waiting
                      ? 'Waiting'
                      : (player.eliminated ? 'OUT' : '${player.bankCents}¢'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 11 : 13,
                    color: waiting && player.profile.name == WaitingSeat.name
                        ? MargeColors.cream
                        : MargeColors.gold,
                  ),
                ),
              ],
            ),
            if (player.usedHouseStake) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'House stake used',
                child: Text('🏠', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
