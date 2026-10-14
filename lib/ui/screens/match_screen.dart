import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ads_service.dart';
import '../../debug/settle_log.dart';
import '../../cosmetics/skins_service.dart';
import '../../engine/engine.dart';
import '../../engine/gem_label.dart';
import '../../services/coin_ledger.dart';
import '../../services/settings_service.dart';
import '../../services/sfx_service.dart';
import '../match_provider.dart';
import '../theme/marge_theme.dart';
import '../visuals/bank_button.dart';
import '../visuals/dice_3d.dart';
import '../visuals/pot_of_gems.dart';
import '../widgets/confetti_overlay.dart';
import '../widgets/daily_drip_card.dart';
import '../widgets/get_more_gems_button.dart';
import '../widgets/gem_shortfall_dialog.dart';
import '../widgets/handoff_strip.dart';
import '../widgets/payout_banner.dart';
import '../widgets/play_coin_pack_button.dart';
import '../widgets/player_chip.dart';

void _moveIntoGame(BuildContext context, WidgetRef ref, int gems) {
  final next = ref.read(matchProvider.notifier).moveFromMainBank(gems);
  if (!context.mounted || next == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Moved $gems gems into this game. You have $next gems at the table.',
      ),
    ),
  );
}

Future<void> _openTableGemsSheet(BuildContext context, WidgetRef ref) async {
  final view = ref.read(matchProvider);
  if (view == null) return;
  final name = view.snapshot.config.localPlayerName;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Consumer(
          builder: (context, ref, _) {
            final available = ref
                .watch(coinLedgerProvider)
                .availableHumanGems(name);
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Table gems',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Move bank gems onto this table. Virtual gems (not real money). '
                    'No unlimited free mint mid-match.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MargeColors.cream.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const DailyDripCard(compact: true),
                  const SizedBox(height: 8),
                  const GetMoreGemsButton(compact: true),
                  const SizedBox(height: 16),
                  GemDenominationPicker(
                    compact: true,
                    title: 'Move into this game',
                    available: available,
                    hint: 'Draws from the gem bank. Virtual gems (not real money).',
                    onChosen: (gems) => _moveIntoGame(context, ref, gems),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

/// What a bank of the current winning hand pays: the per-opponent amount
/// from every seated opponent, capped by what each can cover (table gems
/// plus a still-unused House stake), mirroring the engine's soft take.
@visibleForTesting
int bankPreviewGems(MatchSnapshot snap) {
  final t = snap.turn;
  if (t == null || !t.lastScore.isScoring) return 0;
  final each = t.lastScore.perOpponentCents;
  var total = 0;
  for (var i = 0; i < snap.players.length; i++) {
    if (i == snap.currentSeatIndex) continue;
    final p = snap.players[i];
    if (!p.profile.participates || p.eliminated) continue;
    final cover =
        p.bankCents + (p.usedHouseStake ? 0 : snap.config.houseStakeCents);
    total += each < cover ? each : cover;
  }
  return total;
}

class MatchScreen extends ConsumerStatefulWidget {
  /// Settle-lock watchdog (see [_MatchScreenState._armWatchdog]).
  @visibleForTesting
  static Duration settleWatchdog = const Duration(milliseconds: 2500);

  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  /// Where Bank's gem particles fly: the table-gems readout in the top bar.
  final GlobalKey _gemsTargetKey = GlobalKey(debugLabel: 'gems-target');

  /// Last roll whose 3D dice have settled. Input stays locked (and the
  /// win/near-miss readout and Bank wait) until it matches the view.
  int? _settledSerial;

  /// Safety net for the settle lock: a throw is ~1 s, so if a roll still
  /// reads as "settling" well after that, nothing is in flight; release it.
  Timer? _watchdog;
  int? _watchSerial;

  void _armWatchdog(int serial) {
    if (_watchSerial == serial) return;
    _watchSerial = serial;
    _watchdog?.cancel();
    _watchdog = Timer(MatchScreen.settleWatchdog, () {
      if (!mounted || _settledSerial == serial) return;
      if (ref.read(matchProvider)?.rollSerial != serial) return;
      SettleLog.add(
        'watchdog-fired',
        serial: serial,
        roll: ref.read(matchProvider)?.snapshot.turn?.rollNumber,
        reason:
            'released after ${MatchScreen.settleWatchdog.inMilliseconds} ms',
      );
      // Snap a still-moving throw to rest first; it reports settled itself.
      DiceTrayState? tray;
      void find(Element e) {
        if (tray != null) return;
        if (e is StatefulElement && e.state is DiceTrayState) {
          tray = e.state as DiceTrayState;
          return;
        }
        e.visitChildren(find);
      }

      (context as Element).visitChildren(find);
      tray?.snapToRest('watchdog');
      if (mounted && _settledSerial != serial) {
        setState(() => _settledSerial = serial);
      }
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(matchProvider);
    final skinTheme = ref.watch(cosmeticsProvider).equippedTheme;
    ref.listen(matchProvider, (prev, next) {
      final pending = next?.snapshot.pendingShortfall;
      if (pending == null) return;
      final previous = prev?.snapshot.pendingShortfall;
      if (previous != null &&
          previous.payerSeatIndex == pending.payerSeatIndex &&
          previous.dueGems == pending.dueGems) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => GemShortfallDialog(shortfall: pending),
        );
      });
    });
    if (view == null) {
      return const Scaffold(body: Center(child: Text('No match')));
    }
    final snap = view.snapshot;

    // Hold the table (dice + pot) through a pot-win reveal, then results.
    if (snap.phase == MatchPhase.matchEnd && !view.revealingRoll) {
      return _MatchEndView(snapshot: snap);
    }

    final turn = snap.turn;
    final handoff = snap.handoff;
    final gated = snap.awaitingHandoff;
    final shortfallGate = snap.phase == MatchPhase.awaitingShortfall;
    final showStrip = view.showHandoffStrip;
    final isHumanTurn = snap.currentPlayer.profile.isHuman;
    // Local human can roll only while the table is live — not during handoff
    // or a shortfall choice. Gem tools live in a sheet so they never crowd
    // Roll off a phone screen.
    _settledSerial ??= view.rollSerial;
    final diceSettling = view.rollSerial != _settledSerial;
    if (diceSettling && _watchSerial != view.rollSerial) {
      SettleLog.add(
        'lock-set',
        serial: view.rollSerial,
        roll: turn?.rollNumber,
        reason: 'waiting on throw (settled=$_settledSerial)',
      );
    }
    if (diceSettling) _armWatchdog(view.rollSerial);
    final canInteract =
        isHumanTurn &&
        !view.busyBot &&
        !gated &&
        !shortfallGate &&
        !view.revealingRoll &&
        !diceSettling;
    final hotseat = HandoffState.isHotseatCta(snap.config);
    final settings = ref.watch(settingsProvider);
    final fx = SfxService(
      sfxEnabled: settings.sfxEnabled,
      hapticsEnabled: settings.hapticsEnabled,
    );

    // Locked faces during handoff (prefer frozen handoff values).
    // A first-roll triple-ones sweep resets the turn immediately; keep the
    // winning dice on the table until the winner rolls again.
    final potWinFaces =
        (turn == null || !turn.hasRolled) &&
            snap.lastPayout?.kind == ScoreKind.tripleOnesPotWin &&
            snap.lastPayout?.seatIndex == snap.currentSeatIndex
        ? snap.lastPayout?.diceValues
        : null;
    final List<int>? lockedFaces =
        handoff?.diceValues ??
        (turn != null && turn.hasRolled ? turn.dice.values : potWinFaces);
    final showingPotWinFaces =
        handoff == null &&
        potWinFaces != null &&
        identical(lockedFaces, potWinFaces);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await ref.read(matchProvider.notifier).leaveUnfinished();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1B0F3B),
                    MargeColors.felt,
                    Color(0xFF0A3D2A),
                  ],
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Short windows (Flip 7 cover screen, small phones): scale
                    // the bowl, dice and seats down; the table scrolls and the
                    // actions stay pinned to the bottom.
                    final h = box.maxHeight;
                    final compact = h < 720;
                    final tiny = h < 600;
                    final pw =
                        (h * (tiny ? 0.11 : 0.15)).clamp(56.0, 150.0) * 1.6;
                    final dieSize = tiny ? 44.0 : (compact ? 52.0 : 64.0);
                    // Seat chips grow with large text so their labels never overflow.
                    final ts = MediaQuery.textScalerOf(context)
                        .scale(1)
                        .clamp(1.0, 1.6);
                    final seatsH = (compact ? 56.0 : 72.0) * ts;
                    return Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, inner) => SingleChildScrollView(
                              key: const ValueKey('table-scroll'),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: inner.maxHeight,
                                ),
                                child: IntrinsicHeight(
                                  child: Column(
                                    children: [
                                      _TopBar(
                                        snap: snap,
                                        gemsKey: _gemsTargetKey,
                                        onGems: () =>
                                            _openTableGemsSheet(context, ref),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: PotOfGems(
                                          potGems: view.displayPotCents,
                                          anteGems: snap.config.anteCents,
                                          seats: snap.players.length,
                                          width: pw,
                                          sfx: fx,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      if (view.turnNotice != null) ...[
                                        const SizedBox(height: 8),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          child: Material(
                                            color: MargeColors.gold.withValues(
                                              alpha: 0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              child: Text(
                                                view.turnNotice!,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: MargeColors.gold,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      SizedBox(
                                        height: seatsH,
                                        child: ListView.separated(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          scrollDirection: Axis.horizontal,
                                          itemCount: snap.players.length,
                                          separatorBuilder: (_, _) =>
                                              const SizedBox(width: 8),
                                          itemBuilder: (context, i) {
                                            return PlayerChip(
                                              player: snap.players[i],
                                              isActive:
                                                  i == snap.currentSeatIndex,
                                              compact: true,
                                            );
                                          },
                                        ),
                                      ),
                                      if (snap.lastPayout != null &&
                                          !showStrip &&
                                          !view.revealingRoll &&
                                          !diceSettling) ...[
                                        const SizedBox(height: 10),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          child: PayoutBanner(
                                            event: snap.lastPayout!,
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      _TurnBanner(
                                        snapshot: snap,
                                        busyBot: view.busyBot,
                                        gated: gated,
                                      ),
                                      const SizedBox(height: 16),
                                      DiceTray(
                                        // Keyed: the conditional banner/notice rows above it
                                        // come and go on the roll frame; without a key the
                                        // Column re-created the tray mid-throw and its settle
                                        // callback never fired (input stayed locked).
                                        key: const ValueKey('dice-tray'),
                                        values: lockedFaces ?? const [1, 1, 1],
                                        dim: lockedFaces == null,
                                        rollSerial: view.rollSerial,
                                        // Gold outline = kept (held through handoff and the
                                        // pot-win display too). Kept dice never tumble.
                                        kept: [
                                          for (var i = 0; i < 3; i++)
                                            lockedFaces != null &&
                                                (gated || showingPotWinFaces
                                                    ? true
                                                    : (turn
                                                              ?.dice
                                                              .dice[i]
                                                              .kept ??
                                                          false)),
                                        ],
                                        animate: [
                                          for (var i = 0; i < 3; i++)
                                            !(turn != null &&
                                                turn.hasRolled &&
                                                turn.dice.dice[i].kept),
                                        ],
                                        enabled: [
                                          for (var i = 0; i < 3; i++)
                                            lockedFaces != null &&
                                                canInteract &&
                                                !showingPotWinFaces &&
                                                turn != null &&
                                                !turn.canBank &&
                                                turn.rollNumber < 3,
                                        ],
                                        onTap: (i) => ref
                                            .read(matchProvider.notifier)
                                            .toggleKeep(i),
                                        size: dieSize,
                                        theme: skinTheme,
                                        sfx: fx,
                                        onSettled: (serial) {
                                          SettleLog.add(
                                            serial == _settledSerial
                                                ? 'report-dup'
                                                : serial == view.rollSerial
                                                ? 'lock-released'
                                                : 'stale-report',
                                            serial: serial,
                                            roll: turn?.rollNumber,
                                            reason:
                                                'tray onSettled (view=${view.rollSerial} settled=$_settledSerial)',
                                          );
                                          if (mounted &&
                                              serial != _settledSerial) {
                                            setState(
                                              () => _settledSerial = serial,
                                            );
                                          }
                                        },
                                      ),
                                      if (diceSettling)
                                        const SizedBox.shrink()
                                      else if (!gated &&
                                          turn != null &&
                                          turn.mustKeepRolling)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 10,
                                          ),
                                          child: Text(
                                            canInteract
                                                ? 'No score yet — keep rolling · ${turn.rollsLeft} rolls left'
                                                : '',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: MargeColors.cream
                                                  .withValues(alpha: 0.7),
                                              fontSize: 13,
                                            ),
                                          ),
                                        )
                                      else if (!gated &&
                                          turn != null &&
                                          turn.hasRolled &&
                                          turn.canBank &&
                                          turn.rollsLeft > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 10,
                                          ),
                                          child: Text(
                                            canInteract
                                                ? 'Winning hand · bank it'
                                                : '',
                                            style: TextStyle(
                                              color: MargeColors.cream
                                                  .withValues(alpha: 0.7),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      if (!gated &&
                                          !diceSettling &&
                                          turn != null &&
                                          turn.lastScore.isScoring)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            _scoreHint(turn.lastScore),
                                            style: const TextStyle(
                                              color: MargeColors.gold,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      const Spacer(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (showStrip && handoff != null)
                          HandoffStrip(
                            handoff: handoff,
                            hotseat: hotseat,
                            skinTheme: skinTheme,
                            onConfirm: () => ref
                                .read(matchProvider.notifier)
                                .confirmHandoff(),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            child: _TurnActions(
                              canInteract: canInteract,
                              turn: turn,
                              bankPreview: bankPreviewGems(snap),
                              diceSettling: diceSettling,
                              sfx: fx,
                              gemsTargetKey: _gemsTargetKey,
                              onRoll: () =>
                                  ref.read(matchProvider.notifier).roll(),
                              onBank: () =>
                                  ref.read(matchProvider.notifier).bank(),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            ConfettiOverlay(active: view.showConfetti),
            if (view.unlockBanner != null)
              Positioned(
                top: 72,
                left: 16,
                right: 16,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: MargeColors.gold,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      view.unlockBanner!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: MargeColors.velvet,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _scoreHint(ScoreResult s) {
    switch (s.kind) {
      case ScoreKind.tripleOnesPotWin:
        return '🎯 POT WIN — triple ones!';
      case ScoreKind.tripleOnesPay:
        return 'Triple ones — others pay 10 gems';
      case ScoreKind.threeOfAKind:
        return 'Trips on ${s.faceValue} — others pay ${s.perOpponentCents} gems';
      case ScoreKind.straight:
        return 'Straight — others pay 5 gems';
      case ScoreKind.none:
        return '';
    }
  }
}

class _TurnActions extends StatelessWidget {
  const _TurnActions({
    required this.canInteract,
    required this.turn,
    required this.onRoll,
    required this.onBank,
    required this.bankPreview,
    required this.sfx,
    required this.gemsTargetKey,
    this.diceSettling = false,
  });

  /// 3D dice still in the air: Bank enters only after they settle.
  final bool diceSettling;

  final bool canInteract;
  final TurnState? turn;
  final int bankPreview;
  final SfxService sfx;
  final GlobalKey gemsTargetKey;
  final VoidCallback onRoll;
  final VoidCallback onBank;

  @override
  Widget build(BuildContext context) {
    final t = turn;

    // After a non-scoring roll with rolls left: do not say Roll or Bank.
    if (t != null && t.mustKeepRolling) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: canInteract ? onRoll : null,
          child: Text('KEEP ROLLING · ${t.rollsLeft} LEFT'),
        ),
      );
    }

    // A winning (bankable) hand: Bank is the only action on this beat.
    if (t != null && t.canBank) {
      if (diceSettling) {
        return const SizedBox(height: BankButton.height);
      }
      return BankButton(
        key: const ValueKey('bank-only'),
        amountGems: bankPreview,
        enabled: canInteract,
        sfx: sfx,
        particleTargetKey: gemsTargetKey,
        onBank: onBank,
      );
    }

    final canRoll = canInteract && t != null && t.canRoll;
    final showBank =
        t != null &&
        t.hasRolled &&
        (t.canBank || (t.mustFinish && !t.lastScore.isScoring));
    final canBankNow = canInteract && showBank;
    final bankLabel =
        t != null && t.hasRolled && !t.lastScore.isScoring && t.mustFinish
        ? 'BUST (2 gems)'
        : 'BANK';
    final rollLabel = t == null || !t.hasRolled
        ? 'ROLL'
        : 'ROLL AGAIN (${t.rollsLeft} left)';

    if (!showBank) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: canRoll ? onRoll : null,
          child: Text(rollLabel),
        ),
      );
    }

    if (!canRoll) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: canBankNow ? onBank : null,
          child: Text(bankLabel),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton(onPressed: onRoll, child: Text(rollLabel)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: canBankNow ? onBank : null,
            child: Text(bankLabel),
          ),
        ),
      ],
    );
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.snapshot,
    required this.busyBot,
    this.gated = false,
  });

  final MatchSnapshot snapshot;
  final bool busyBot;
  final bool gated;

  @override
  Widget build(BuildContext context) {
    final player = snapshot.currentPlayer;
    final turn = snapshot.turn;
    final humans = snapshot.players.where((p) => p.profile.isHuman).length;
    final isHotseatOther =
        player.profile.isHuman && humans > 1 && player.profile.id != 'human_0';

    final String title;
    if (gated) {
      title = '${player.profile.avatarEmoji} ${player.profile.name} — result';
    } else if (busyBot) {
      title =
          '${player.profile.avatarEmoji} ${player.profile.name} is rolling…';
    } else if (player.profile.isHuman) {
      final rollBit = turn != null && turn.hasRolled
          ? (turn.setNumber > 1
                ? ' · set ${turn.setNumber} · roll ${turn.rollNumber}/3'
                : ' · roll ${turn.rollNumber}/3')
          : '';
      title =
          '${player.profile.avatarEmoji} ${player.profile.name}\'s turn$rollBit';
    } else {
      title = '${player.profile.avatarEmoji} ${player.profile.name}\'s turn';
    }

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        if (isHotseatOther && !busyBot && !gated) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MargeColors.gold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: MargeColors.gold.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              'Pass the device to ${player.profile.name}',
              style: const TextStyle(
                color: MargeColors.gold,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.snap,
    required this.onGems,
    required this.gemsKey,
  });
  final MatchSnapshot snap;
  final GlobalKey gemsKey;
  final VoidCallback onGems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Leave table',
            onPressed: () async {
              final choice = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Leave table?'),
                  content: const Text(
                    'Save this unfinished game for Resume on Home, '
                    'or end it now and crow a winner.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, 'keep'),
                      child: const Text('Keep playing'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, 'end'),
                      child: const Text('End match'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'leave'),
                      child: const Text('Save & leave'),
                    ),
                  ],
                ),
              );
              if (!context.mounted) return;
              if (choice == 'leave') {
                await ref.read(matchProvider.notifier).leaveUnfinished();
                if (context.mounted) Navigator.of(context).pop();
              } else if (choice == 'end') {
                ref.read(matchProvider.notifier).endMatch();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text(
              'Round ${snap.roundNumber}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          IconButton(
            key: gemsKey,
            tooltip: 'Table gems',
            onPressed: onGems,
            icon: const Icon(Icons.diamond_outlined),
          ),
        ],
      ),
    );
  }
}

class _MatchEndView extends ConsumerStatefulWidget {
  const _MatchEndView({required this.snapshot});
  final MatchSnapshot snapshot;

  @override
  ConsumerState<_MatchEndView> createState() => _MatchEndViewState();
}

class _MatchEndViewState extends ConsumerState<_MatchEndView> {
  var _breakHandled = false;

  /// Hotseat: each human answers "play another game?" in turn. Bots always
  /// say yes. Index into [_humans]; answers collected in [_quit].
  var _asking = 0;
  final _quit = <String>{};

  List<PlayerState> get _humans => [
    for (final p in widget.snapshot.players)
      if (p.profile.isHuman && p.profile.participates && !p.eliminated) p,
  ];

  bool get _hotseat => _humans.length > 1;

  Future<void> _answer(bool again) async {
    final humans = _humans;
    final who = humans[_asking];
    if (!again) _quit.add(who.profile.id);
    final local = who.profile.name == widget.snapshot.config.localPlayerName;
    if (!again && local) {
      await _leaveQuiet(); // the phone's owner is done: back to Home
      return;
    }
    if (_asking + 1 < humans.length) {
      setState(() => _asking++);
      return;
    }
    final cfg = widget.snapshot.config;
    final others = humans.length - 1 - _quit.length;
    if (others + cfg.botCount < 1) {
      await _leaveQuiet(); // nobody left to play with
      return;
    }
    await _adAfterUserAction();
    if (!mounted) return;
    ref.read(matchProvider.notifier).rematch(otherHumanCount: others);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNaturalBreak());
  }

  Future<void> _onNaturalBreak() async {
    if (_breakHandled || !mounted) return;
    _breakHandled = true;
    // Record the completed match only. No ad while results are on screen;
    // the interstitial waits for the player's own tap (Continue or Quit).
    ref.read(adsServiceProvider).notifyMatchCompleted();
  }

  /// Natural break after a user action. ≤1 interstitial per completed match
  /// (InterstitialGate). Never mid-roll. Fail closed.
  Future<void> _adAfterUserAction() async {
    try {
      await ref.read(adsServiceProvider).maybeShowInterstitialAtBreak();
    } catch (_) {
      // Ads must never block Continue / Quit.
    }
  }

  Future<void> _rematch() async {
    await _adAfterUserAction();
    if (!mounted) return;
    // One tap, same seats / ante, no ready-check. Stay on the table.
    ref.read(matchProvider.notifier).rematch();
  }

  Future<void> _leaveQuiet() async {
    // Quiet out — no confirm dialog. Interstitial only if the gate allows.
    await _adAfterUserAction();
    if (!mounted) return;
    await ref.read(matchProvider.notifier).leaveUnfinished();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Widget _continueBtn(PlayerState? asked, {bool short = false}) {
    final onPressed = asked != null ? () => _answer(true) : _rematch;
    const key = ValueKey('match-end-continue');
    if (short) {
      // One line, scaled down to fit: the row must stay one button tall.
      return FilledButton(
        key: key,
        onPressed: onPressed,
        child: const FittedBox(child: Text('Continue playing')),
      );
    }
    return FilledButton.icon(
      key: key,
      onPressed: onPressed,
      icon: const Icon(Icons.replay_rounded),
      label: const Text('Continue playing', textAlign: TextAlign.center),
    );
  }

  Widget _quitBtn(PlayerState? asked, {bool short = false}) => TextButton(
    key: const ValueKey('match-end-quit'),
    onPressed: asked != null ? () => _answer(false) : _leaveQuiet,
    child: short ? const FittedBox(child: Text('Quit')) : const Text('Quit'),
  );

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final ranked =
        snapshot.players.where((p) => p.profile.participates).toList()
          ..sort((a, b) => b.bankCents.compareTo(a.bankCents));
    final waiting = snapshot.players.where((p) => p.profile.isWaiting).toList();
    final byId = snapshot.winnerId == null
        ? null
        : snapshot.players
              .where((p) => p.profile.id == snapshot.winnerId)
              .firstOrNull;
    final winner =
        byId ?? (ranked.isEmpty ? snapshot.players.first : ranked.first);
    final humans = _humans;
    final asked = _hotseat && _asking < humans.length ? humans[_asking] : null;

    final mq = MediaQuery.of(context);
    final short =
        mq.size.height - mq.padding.vertical <
        420 * mq.textScaler.scale(1).clamp(1.0, 2.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [MargeColors.velvet, MargeColors.felt],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          // The results scroll; the play-again question and Continue / Quit
          // stay pinned so they are reachable at any size or text scale.
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('match-end-scroll'),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '🏆 Match over',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: MargeColors.gold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.endMessage ??
                            '${winner.profile.avatarEmoji} ${winner.profile.name} '
                                'wins with ${gemCount(winner.bankCents)}',
                        key: const ValueKey('match-end-message'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      for (
                        var i = 0;
                        i < ranked.length + waiting.length;
                        i++
                      ) ...[
                        if (i > 0) const SizedBox(height: 8),
                        i < ranked.length
                            ? PlayerChip(player: ranked[i], isActive: i == 0)
                            : PlayerChip(player: waiting[i - ranked.length]),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        '${gemCount(winner.bankCents)} at the table · '
                        'virtual gems (not real money)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: MargeColors.cream.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Center(child: GetMoreGemsButton()),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      asked != null
                          ? '${asked.profile.avatarEmoji} ${asked.profile.name}, '
                                'play another game?'
                          : 'Continue playing or quit?',
                      key: const ValueKey('play-again-prompt'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MargeColors.cream.withValues(alpha: 0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (short)
                      // Short screens / big text: one row saves a line.
                      Row(
                        children: [
                          Expanded(child: _continueBtn(asked, short: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _quitBtn(asked, short: true)),
                        ],
                      )
                    else ...[
                      _continueBtn(asked),
                      const SizedBox(height: 4),
                      _quitBtn(asked),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
