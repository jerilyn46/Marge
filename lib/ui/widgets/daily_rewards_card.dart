import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/gem_label.dart';
import '../../services/coin_ledger.dart';
import '../../services/free_mint.dart';
import '../../services/settings_service.dart';
import '../theme/marge_theme.dart';

/// Daily goals (15 + 20 gems) and the streak ladder. All grants go through
/// the free-mint caps (85/day, 280/week).
class DailyRewardsCard extends ConsumerWidget {
  const DailyRewardsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(coinLedgerProvider);
    final now = DateTime.now().toUtc();
    final mint = ledger.freeMint;
    final room = mint.remaining(now);
    final streakClaimed = mint.streakClaimedToday(now);
    final pendingDay = mint.pendingStreakDay(now);
    final pendingGems = FreeMintLedger.ladderGems(pendingDay);
    final name = ref.read(settingsProvider).playerName;
    final notifier = ref.read(coinLedgerProvider.notifier);

    void toast(String msg) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    String granted(int g) => g > 0
        ? 'Claimed ${gemCount(g)}. Free gems. Not a real charge.'
        : 'Free gem limit reached for now.';

    final muted = TextStyle(
      color: MargeColors.cream.withValues(alpha: 0.78),
      fontSize: 13,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Daily goals & streak',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: MargeColors.gold,
              ),
            ),
            const SizedBox(height: 4),
            Text('Free gems left today: ${gemCount(room)}', style: muted),
            for (final g in DailyGoal.values)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${g.title} · ${gemCount(g.gems)}',
                        style: muted,
                      ),
                    ),
                    FilledButton(
                      onPressed:
                          mint.goalDone(g, now) && !mint.goalClaimed(g, now)
                          ? () {
                              final got = notifier.claimGoal(name, g);
                              if (got != null) toast(granted(got));
                            }
                          : null,
                      child: Text(
                        mint.goalClaimed(g, now)
                            ? 'Claimed'
                            : mint.goalDone(g, now)
                            ? 'Claim'
                            : 'To do',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              streakClaimed
                  ? 'Streak: day ${mint.currentStreak(now)}. Come back tomorrow.'
                  : 'Streak day $pendingDay · ${gemCount(pendingGems)}',
              style: muted,
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: streakClaimed
                  ? null
                  : () {
                      final got = notifier.claimStreakDay(name);
                      if (got != null) toast(granted(got));
                    },
              child: Text(
                streakClaimed ? 'Streak claimed' : 'Claim streak day',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
