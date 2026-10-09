import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/gem_label.dart';
import '../../services/coin_ledger.dart';
import '../../services/settings_service.dart';

/// In-app "free gems are ready" prompt for the Home lobby.
///
/// Uses the existing daily-drip clock ([PlayerCoinLedger.canClaimDailyDrip]).
/// Shows at most once per Denver day per app session, and only while Home is
/// the visible route — never over a match or mid-roll.
class DailyGemsReadyPrompt extends ConsumerStatefulWidget {
  const DailyGemsReadyPrompt({super.key, required this.child});

  final Widget child;

  /// Denver day key already prompted this session (shared across rebuilds).
  @visibleForTesting
  static String? promptedDay;

  /// How often Home re-checks while it is open (cheap, no I/O).
  @visibleForTesting
  static Duration pollEvery = const Duration(seconds: 30);

  @override
  ConsumerState<DailyGemsReadyPrompt> createState() =>
      _DailyGemsReadyPromptState();
}

class _DailyGemsReadyPromptState extends ConsumerState<DailyGemsReadyPrompt> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _poll = Timer.periodic(DailyGemsReadyPrompt.pollEvery, (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final ledger = ref.read(coinLedgerProvider);
    if (!ledger.loaded) return;
    final now = DateTime.now().toUtc();
    if (!ledger.canClaimDailyDrip(utcNow: now)) return;
    final day = PlayerCoinLedger.denverDayKey(now);
    if (DailyGemsReadyPrompt.promptedDay == day) return;
    DailyGemsReadyPrompt.promptedDay = day;
    final amount = PlayerCoinLedger.dailyDripGems;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('Your free daily gems are ready: ${gemCount(amount)}.'),
        action: SnackBarAction(
          label: 'Claim',
          onPressed: () {
            final name = ref.read(settingsProvider).playerName;
            ref.read(coinLedgerProvider.notifier).claimDailyDrip(name);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
