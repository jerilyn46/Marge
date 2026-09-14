import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/gem_label.dart';
import '../../services/coin_ledger.dart';
import '../../services/settings_service.dart';
import '../theme/marge_theme.dart';

/// Once-per-day free grant. The only uncapped-looking free path is capped here.
class DailyDripCard extends ConsumerWidget {
  const DailyDripCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(coinLedgerProvider);
    final canClaim = ledger.canClaimDailyDrip();
    final amount = PlayerCoinLedger.dailyDripGems;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Daily free gems',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: compact ? 15 : 16,
                color: MargeColors.gold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              canClaim
                  ? 'Claim ${gemCount(amount)} today. Free gems. Not a real charge.'
                  : 'Already claimed today. Come back tomorrow.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.78),
                fontSize: compact ? 12 : 13,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: canClaim
                  ? () {
                      final name = ref.read(settingsProvider).playerName;
                      final granted = ref
                          .read(coinLedgerProvider.notifier)
                          .claimDailyDrip(name);
                      if (!context.mounted || granted == null) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Claimed ${gemCount(granted)}. Free gems. Not a real charge.',
                          ),
                        ),
                      );
                    }
                  : null,
              child: Text(
                canClaim ? 'Claim ${gemCount(amount)}' : 'Claimed today',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
