import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../debug/settle_log.dart';
import '../../ads/ads_service.dart';
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
import '../visuals/gem_bank_readout.dart';
import '../visuals/pot_of_gems.dart';
import '../visuals/pot_win_flight.dart';
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

/// Whose table gems the top-bar readout shows: the seat taking its turn when
/// that is a person at this device, otherwise this device's player.
/// -1 when no person is seated (no number to show).
@visibleForTesting
int gemBankOwnerSeat(MatchSnapshot snap) {
  final players = snap.players;
  if (snap.currentSeatIndex >= 0 &&
      snap.currentSeatIndex < players.length &&
      players[snap.currentSeatIndex].profile.isHuman) {
    return snap.currentSeatIndex;
  }
  final local = players.indexWhere(
    (p) => p.profile.isHuman && p.profile.name == snap.config.localPlayerName,
  );
  if (local >= 0) return local;
  return players.indexWhere((p) => p.profile.isHuman);
}

class MatchScreen extends ConsumerStatefulWidget {
  /// Settle-lock watchdog. The longest throw (big result) is 2.6 s on
  /// screen, so a roll still "settling" after this has nothing in flight.
  @visibleForTesting
  static Duration settleWatchdog = const Duration(milliseconds: 4000);

  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  /// Where Bank's gem particles fly: the table-gems readout in the top bar.
  final GlobalKey _gemsTargetKey = GlobalKey(debugLabel: 'gems-target');

  /// The gem bank readout, so flights can tick it up as gems land.
  final GlobalKey<GemBankReadoutState> _readoutKey = GlobalKey(
    debugLabel: 'gem-bank-readout',
  );

  /// Last roll whose 3D dice have settled. Input stays locked (and the
  /// win/near-miss readout and Bank wait) until it matches the view.
  int? _settledSerial;

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
      ref.read(matchProvider.notifier).diceSettled(serial);
    });
  }

  /// The bowl, so a pot win's gems can lift out of it.
  final GlobalKey _potKey = GlobalKey(debugLabel: 'pot');

  /// One key per seat chip: where a pot win's gems land first.
  final List<GlobalKey> _seatKeys = [];

  final List<OverlayEntry> _flights = [];

  GlobalKey _seatKey(int i) {
    while (_seatKeys.length <= i) {
      _seatKeys.add(GlobalKey(debugLabel: 'seat-${_seatKeys.length}'));
    }
    return _seatKeys[i];
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    for (final e in _flights) {
      if (e.mounted) e.remove();
    }
    _flights.clear();
    super.dispose();
  }

  static Offset? _centerOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  /// Pot win (DESIGNER_SPEC §3 "Pot taken"): once the winning dice have been
  /// seen, gems lift out of the bowl, fly to the winner's seat, then on into
  /// the Bank flow (the gem readout) when a person at this device won.
  /// Reduce Motion: nothing flies; the numbers just change.
  /// A first-roll triple-1s win ends the match: keep the table up while the
  /// pot flies to the winner, then show the results.
  bool _potFlightHold = false;

  void _endFlightHold() {
    if (!_potFlightHold || _flights.isNotEmpty) return;
    if (mounted) {
      setState(() => _potFlightHold = false);
    } else {
      _potFlightHold = false;
    }
  }

  void _launchPotWinFlight(MatchSnapshot snap, PayoutEvent payout) {
    if (!mounted) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final overlay = Overlay.maybeOf(context);
    final potBox = _potKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || potBox == null || !potBox.hasSize) {
      _readoutKey.currentState?.cancel();
      _endFlightHold();
      return;
    }
    final s = potBox.size.width / PotOfGems.canvas.width;
    final from = potBox.localToGlobal(PotOfGems.landingCenter * s);
    final seatIndex = payout.seatIndex ?? snap.currentSeatIndex;
    final seat =
        (seatIndex >= 0 && seatIndex < _seatKeys.length
            ? _centerOf(_seatKeys[seatIndex])
            : null) ??
        from + const Offset(0, 90);
    final toReadout = seatIndex == gemBankOwnerSeat(snap);
    final bank = toReadout ? _centerOf(_gemsTargetKey) : null;
    if (bank == null) _readoutKey.currentState?.cancel();
    final sprites = PotWinFlight.spritesFor(
      payout.amountCents,
      snap.config.anteCents,
    );
    final shares = gemShares(payout.amountCents, sprites);
    final settings = ref.read(settingsProvider);
    final fx = SfxService(
      sfxEnabled: settings.sfxEnabled,
      hapticsEnabled: settings.hapticsEnabled,
    );
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => PotWinFlight(
        key: const ValueKey('pot-win-flight'),
        from: from,
        seat: seat,
        bank: bank,
        gems: sprites,
        sfx: fx,
        onGemBanked: (i) => _readoutKey.currentState?.land(shares[i]),
        onDone: () {
          _flights.remove(entry);
          if (entry.mounted) entry.remove();
          _endFlightHold();
        },
      ),
    );
    _flights.add(entry);
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(matchProvider);
    final skinTheme = ref.watch(cosmeticsProvider).equippedTheme;
    ref.listen(matchProvider, (prev, next) {
      // The reveal beat ends: the pot is taken now, so the gems fly.
      final payout = next?.snapshot.lastPayout;
      if (prev?.revealingRoll != true ||
          next == null ||
          next.revealingRoll ||
          payout == null ||
          payout.kind != ScoreKind.tripleOnesPotWin ||
          payout.amountCents <= 0) {
        return;
      }
      final snap = next.snapshot;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
      if (payout.seatIndex == gemBankOwnerSeat(snap)) {
        // Hold the readout at its pre-win value; the flight ticks it up.
        _readoutKey.currentState?.beginIncoming(
          payout.amountCents,
          credited: true,
        );
      }
      _potFlightHold = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _launchPotWinFlight(snap, payout),
      );
    });
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
    if (snap.phase == MatchPhase.matchEnd &&
        !view.revealingRoll &&
        !_potFlightHold) {
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
                    // the bowl, dice and seats down. The felt flexes, so the
                    // actions stay pinned at the bottom.
                    final h = box.maxHeight;
                    final compact = h < 720;
                    final tiny = h < 600;
                    final potWidth =
                        (h * (tiny ? 0.11 : 0.15)).clamp(56.0, 150.0) * 1.6;
                    final dieSize = h < 480
                        ? 40.0
                        : tiny
                        ? 44.0
                        : (compact ? 52.0 : 64.0);
                    // Seat chips grow with large text so their labels never overflow.
                    final ts = MediaQuery.textScalerOf(context)
                        .scale(1)
                        .clamp(1.0, 1.6);
                    final seatsH = (compact ? 56.0 : 72.0) * ts;
                    return Column(
                      children: [
                        // Header (bar, bowl, seats, banners) is capped on
                        // short windows and scrolls; the felt keeps the rest.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: h * (h < 480 ? 0.2 : 0.42),
                          ),
                          child: SingleChildScrollView(
                            key: const ValueKey('table-scroll'),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _TopBar(
                                  snap: snap,
                                  gemsKey: _gemsTargetKey,
                                  readoutKey: _readoutKey,
                                  heldWinGems:
                                      view.revealingRoll &&
                                          snap.lastPayout?.kind ==
                                              ScoreKind.tripleOnesPotWin
                                      ? snap.lastPayout!.amountCents
                                      : 0,
                                  onGems: () =>
                                      _openTableGemsSheet(context, ref),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: PotOfGems(
                                    key: _potKey,
                                    potGems: view.displayPotCents,
                                    anteGems: snap.config.anteCents,
                                    seats: snap.players.length,
                                    width: potWidth,
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
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
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
                                      return KeyedSubtree(
                                        key: _seatKey(i),
                                        child: PlayerChip(
                                          key: ValueKey('seat-chip-$i'),
                                          player: snap.players[i],
                                          isActive: i == snap.currentSeatIndex,
                                          compact: true,
                                        ),
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
                                const SizedBox(height: 8),
                                _TurnBanner(
                                  snapshot: snap,
                                  busyBot: view.busyBot,
                                  gated: gated,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // The felt: dice are thrown across this area (DICE_SPEC).
                        // Keyed: the conditional banner/notice rows above come
                        // and go on the roll frame; unkeyed, the Column re-created
                        // the tray mid-throw, its settle callback never fired and
                        // input stayed locked (Keep Rolling greyed out).
                        Expanded(
                          key: const ValueKey('dice-tray-slot'),
                          flex: 3,
                          // Dice never outgrow a short felt.
                          child: LayoutBuilder(
                            builder: (context, felt) => DiceTray(
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
                                          : (turn?.dice.dice[i].kept ?? false)),
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
                              size: math.min(dieSize, felt.maxHeight * 0.42),
                              theme: skinTheme,
                              sfx: fx,
                              lite: settings.liteDice,
                              firstRoll: turn != null && turn.rollNumber == 1,
                              // Winning hand: big-result slow-mo/zoom (2.6 s cap).
                              highlight:
                                  turn != null &&
                                  turn.hasRolled &&
                                  turn.lastScore.isScoring,
                              throwEdge: DiceTray.edgeForSeat(
                                snap.currentSeatIndex,
                                snap.players
                                    .where((p) => p.profile.participates)
                                    .length,
                              ),
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
                                if (mounted && serial != _settledSerial) {
                                  setState(() => _settledSerial = serial);
                                }
                                if (mounted) {
                                  ref
                                      .read(matchProvider.notifier)
                                      .diceSettled(serial);
                                }
                              },
                            ),
                          ),
                        ),
                        if (diceSettling)
                          const SizedBox.shrink()
                        else if (!gated && turn != null && turn.mustKeepRolling)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _OneLine(
                              Text(
                                canInteract
                                    ? 'No score yet — keep rolling · ${turn.rollsLeft} rolls left'
                                    : '',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: MargeColors.cream.withValues(
                                    alpha: 0.7,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          )
                        else if (h >= 480 &&
                            !gated &&
                            turn != null &&
                            turn.hasRolled &&
                            turn.canBank &&
                            turn.rollsLeft > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _OneLine(
                              Text(
                                canInteract ? 'Winning hand · bank it' : '',
                                style: TextStyle(
                                  color: MargeColors.cream.withValues(
                                    alpha: 0.7,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        if (!gated &&
                            !diceSettling &&
                            turn != null &&
                            turn.lastScore.isScoring)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _OneLine(
                              Text(
                                _scoreHint(turn.lastScore),
                                style: const TextStyle(
                                  color: MargeColors.gold,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        if (h >= 480) const Spacer(),
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
                              bankPreview: snap.bankGems, // engine's own number
                              diceSettling: diceSettling,
                              sfx: fx,
                              gemsTargetKey: _gemsTargetKey,
                              onBurstStart: (gems) =>
                                  _readoutKey.currentState?.beginIncoming(gems),
                              onParticleLanded: (gems) =>
                                  _readoutKey.currentState?.land(gems),
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
    this.onBurstStart,
    this.onParticleLanded,
    this.diceSettling = false,
  });

  final ValueChanged<int>? onBurstStart;
  final ValueChanged<int>? onParticleLanded;

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
          child: _OneLine(Text('KEEP ROLLING · ${t.rollsLeft} LEFT')),
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
        onBurstStart: onBurstStart == null
            ? null
            : () => onBurstStart!(bankPreview),
        onParticleLanded: onParticleLanded,
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
          child: _OneLine(Text(rollLabel)),
        ),
      );
    }

    if (!canRoll) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: canBankNow ? onBank : null,
          child: _OneLine(Text(bankLabel)),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: onRoll,
            child: _OneLine(Text(rollLabel)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: canBankNow ? onBank : null,
            child: _OneLine(Text(bankLabel)),
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
          ? ' · roll ${turn.rollNumber}/3'
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
    required this.readoutKey,
    this.heldWinGems = 0,
  });
  final MatchSnapshot snap;
  final GlobalKey gemsKey;
  final GlobalKey<GemBankReadoutState> readoutKey;

  /// A pot win still being revealed: show the bank as it was before it.
  final int heldWinGems;
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
          Builder(
            builder: (context) {
              final owner = gemBankOwnerSeat(snap);
              final seat = owner >= 0 ? snap.players[owner] : null;
              final held = seat != null && snap.lastPayout?.seatIndex == owner
                  ? heldWinGems
                  : 0;
              return GemBankReadout(
                key: readoutKey,
                gems: seat == null ? null : seat.bankCents - held,
                ownerId: seat?.profile.id ?? '',
                targetKey: gemsKey,
                onTap: onGems,
              );
            },
          ),
          const SizedBox(width: 4),
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
                      // Last player with gems takes the pot (shown with the win).
                      if (snapshot.lastPayout case final p?
                          when p.kind == ScoreKind.tripleOnesPotWin &&
                              p.diceValues == null) ...[
                        const SizedBox(height: 12),
                        KeyedSubtree(
                          key: const ValueKey('last-standing-banner'),
                          child: PayoutBanner(event: p),
                        ),
                      ],
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

/// Action labels stay on one line and scale down at large text sizes, so the
/// pinned buttons never grow tall enough to push the table off a cover screen.
class _OneLine extends StatelessWidget {
  const _OneLine(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: child);
}
