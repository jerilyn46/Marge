import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../engine/gem_label.dart';
import '../../engine/gem_shortfall.dart';
import '../../services/coin_ledger.dart';
import '../match_provider.dart';
import 'play_coin_pack_button.dart';

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
            GemDenominationPicker(
              compact: true,
              title: 'Add gems',
              hint: 'Free gems. Not a real charge.',
              onChosen: (gems) {
                final next = ref
                    .read(coinLedgerProvider.notifier)
                    .grantHumanPlayCoins(name, cents: gems);
                if (!context.mounted || next == null) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added $gems gems. Gem bank has $next gems.'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(matchProvider.notifier).quitShortfall();
            Navigator.of(context).pop();
          },
          child: Text('Pay ${gemCount(table)} and quit this game'),
        ),
        FilledButton(
          onPressed: canCover
              ? () {
                  final ok = ref.read(matchProvider.notifier).coverShortfall();
                  if (ok && context.mounted) Navigator.of(context).pop();
                }
              : null,
          child: Text('Pay ${gemCount(due)}'),
        ),
      ],
    );
  }

  static PlayerState snapPlayer(MatchSnapshot snap, int index) {
    if (index < 0 || index >= snap.players.length) return snap.players.first;
    return snap.players[index];
  }
}
