import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../engine/gem_label.dart';
import '../../engine/gem_shortfall.dart';
import '../../services/coin_ledger.dart';
import '../match_provider.dart';
import '../theme/marge_theme.dart';
import 'daily_drip_card.dart';
import 'get_more_gems_button.dart';

/// Choice when a seated human cannot cover a first-roll trips payment.
class GemShortfallDialog extends ConsumerWidget {
  const GemShortfallDialog({super.key, required this.shortfall});

  final GemShortfall shortfall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(matchProvider);
    final pending = view?.snapshot.pendingShortfall;
    if (view == null || pending == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }
    final snap = view.snapshot;
    final payer = snapPlayer(snap, pending.payerSeatIndex);
    final table = payer.bankCents;
    final due = pending.dueGems;
    final name = snap.config.localPlayerName;
    final bank = ref.watch(coinLedgerProvider).availableHumanGems(name);
    final canCover = table + bank >= due;

    return AlertDialog(
      title: const Text('Need more gems'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${payer.profile.name} owes ${gemCount(due)} for three ${pending.face}s on the first roll. '
              'This table has ${gemCount(table)}. Gem bank has ${gemCount(bank)}.',
            ),
            const SizedBox(height: 12),
            Text(
              'Virtual gems (not real money). Daily drip, gem packs, '
              'or a rewarded ad — not an unlimited free mint.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            const DailyDripCard(compact: true),
            const SizedBox(height: 8),
            const GetMoreGemsButton(compact: true),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(matchProvider.notifier).quitShortfall();
            Navigator.of(context).pop();
          },
          child: Text('Spend ${gemCount(table)} and quit this game'),
        ),
        FilledButton(
          onPressed: canCover
              ? () {
                  final ok = ref.read(matchProvider.notifier).coverShortfall();
                  if (ok && context.mounted) Navigator.of(context).pop();
                }
              : null,
          child: Text('Cover ${gemCount(due)}'),
        ),
      ],
    );
  }

  static PlayerState snapPlayer(MatchSnapshot snap, int index) {
    if (index < 0 || index >= snap.players.length) return snap.players.first;
    return snap.players[index];
  }
}
