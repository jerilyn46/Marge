import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/gem_label.dart';
import '../../services/coin_ledger.dart';
import '../../services/settings_service.dart';
import '../theme/marge_theme.dart';
import 'daily_drip_card.dart';
import 'get_more_gems_button.dart';

/// Jewel-tray detail for the gem bank — virtual gems only (not real money).
Future<void> showGemBankSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MargeColors.felt,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => const _GemBankSheet(),
  );
}

class _GemBankSheet extends ConsumerWidget {
  const _GemBankSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final gemBank =
        ref.watch(coinLedgerProvider).availableHumanGems(settings.playerName);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: MargeColors.cream.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Gem bank',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: MargeColors.gold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '${gemCount(gemBank)} available',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Virtual gems (not real money). No unlimited free mint.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MargeColors.cream.withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          const DailyDripCard(compact: true),
          const SizedBox(height: 10),
          const GetMoreGemsButton(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
