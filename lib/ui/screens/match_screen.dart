import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ads_service.dart';
import '../../cosmetics/skins_service.dart';
import '../../engine/engine.dart';
import '../match_provider.dart';
import '../theme/marge_theme.dart';
import '../widgets/confetti_overlay.dart';
import '../widgets/die_widget.dart';
import '../widgets/handoff_strip.dart';
import '../widgets/payout_banner.dart';
import '../widgets/player_chip.dart';
import '../widgets/pot_meter.dart';

class MatchScreen extends ConsumerWidget {
  const MatchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(matchProvider);
    final skinTheme = ref.watch(cosmeticsProvider).equippedTheme;
    if (view == null) {
      return const Scaffold(body: Center(child: Text('No match')));
    }
    final snap = view.snapshot;

    if (snap.phase == MatchPhase.matchEnd) {
      return _MatchEndView(snapshot: snap);
    }

    final turn = snap.turn;
    final handoff = snap.handoff;
    final gated = snap.awaitingHandoff;
    final showStrip = view.showHandoffStrip;
    final isHumanTurn = snap.currentPlayer.profile.isHuman;
    final canInteract = isHumanTurn && !view.busyBot && !gated;
    final hotseat = HandoffState.isHotseatCta(snap.config);

    // Locked faces during handoff (prefer frozen handoff values).
    final List<int>? lockedFaces = handoff?.diceValues ??
        (turn != null && turn.hasRolled ? turn.dice.values : null);

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1B0F3B), MargeColors.felt, Color(0xFF0A3D2A)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _TopBar(snap: snap),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PotMeter(potCents: snap.potCents),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: snap.players.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        return PlayerChip(
                          player: snap.players[i],
                          isActive: i == snap.currentSeatIndex,
                          compact: true,
                        );
                      },
                    ),
                  ),
                  if (snap.lastPayout != null && !showStrip) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: PayoutBanner(event: snap.lastPayout!),
                    ),
                  ],
                  const Spacer(),
                  _TurnBanner(
                    snapshot: snap,
                    busyBot: view.busyBot,
                    gated: gated,
                  ),
                  const SizedBox(height: 16),
                  if (lockedFaces != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          DieWidget(
                            value: lockedFaces[i],
                            kept: gated
                                ? true
                                : (turn?.dice.dice[i].kept ?? false),
                            enabled: canInteract &&
                                turn != null &&
                                turn.rollNumber < 3,
                            theme: skinTheme,
                            onTap: () =>
                                ref.read(matchProvider.notifier).toggleKeep(i),
                          ),
                        ],
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        3,
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Opacity(
                            opacity: 0.35,
                            child: DieWidget(
                              value: 1,
                              kept: false,
                              enabled: false,
                              size: 64,
                              theme: skinTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!gated &&
                      turn != null &&
                      turn.hasRolled &&
                      turn.rollsLeft > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        canInteract
                            ? (turn.canBank
                                ? 'Tap dice to keep · Roll again or Bank'
                                : 'No score yet — tap dice to keep, then Roll again '
                                    '(${turn.rollsLeft} left)')
                            : '',
                        style: TextStyle(
                          color: MargeColors.cream.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (!gated && turn != null && turn.lastScore.isScoring)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _scoreHint(turn.lastScore),
                        style: const TextStyle(
                          color: MargeColors.gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (showStrip && handoff != null)
                    HandoffStrip(
                      handoff: handoff,
                      hotseat: hotseat,
                      skinTheme: skinTheme,
                      onConfirm: () =>
                          ref.read(matchProvider.notifier).confirmHandoff(),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: canInteract &&
                                      turn != null &&
                                      turn.canRoll
                                  ? () =>
                                      ref.read(matchProvider.notifier).roll()
                                  : null,
                              child: Text(
                                turn == null || !turn.hasRolled
                                    ? 'ROLL'
                                    : 'ROLL AGAIN (${turn.rollsLeft} left)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: canInteract &&
                                      turn != null &&
                                      turn.hasRolled &&
                                      (turn.canBank || turn.mustFinish)
                                  ? () =>
                                      ref.read(matchProvider.notifier).bank()
                                  : null,
                              child: Text(
                                turn != null &&
                                        turn.hasRolled &&
                                        !turn.lastScore.isScoring &&
                                        turn.mustFinish
                                    ? 'BUST (2¢)'
                                    : 'BANK',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
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
    );
  }

  String _scoreHint(ScoreResult s) {
    switch (s.kind) {
      case ScoreKind.tripleOnesPotWin:
        return '🎯 POT WIN — triple ones!';
      case ScoreKind.tripleOnesPay:
        return 'Triple ones — others pay 10¢';
      case ScoreKind.threeOfAKind:
        return 'Trips on ${s.faceValue} — others pay ${s.perOpponentCents}¢';
      case ScoreKind.straight:
        return 'Straight — others pay 5¢';
      case ScoreKind.none:
        return '';
    }
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
    final isHotseatOther = player.profile.isHuman &&
        humans > 1 &&
        player.profile.id != 'human_0';

    final String title;
    if (gated) {
      title =
          '${player.profile.avatarEmoji} ${player.profile.name} — result';
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
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        if (isHotseatOther && !busyBot && !gated) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MargeColors.gold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MargeColors.gold.withValues(alpha: 0.5)),
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
  const _TopBar({required this.snap});
  final MatchSnapshot snap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'End match',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('End match?'),
                  content: const Text('See final banks and crow a winner.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Keep playing'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('End'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                ref.read(matchProvider.notifier).endMatch();
              }
            },
            icon: const Icon(Icons.close_rounded),
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
          const SizedBox(width: 48),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNaturalBreak());
  }

  Future<void> _onNaturalBreak() async {
    if (_breakHandled || !mounted) return;
    _breakHandled = true;
    final ads = ref.read(adsServiceProvider);
    // Frequency-gated interstitial only at match end — never mid-roll.
    ads.notifyMatchCompleted();
    await ads.maybeShowInterstitialAtBreak();
  }

  Future<void> _leaveToLobby() async {
    // Second chance if the end-screen attempt was gated / failed to load.
    final ads = ref.read(adsServiceProvider);
    await ads.maybeShowInterstitialAtBreak();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final ranked = [...snapshot.players]
      ..sort((a, b) => b.bankCents.compareTo(a.bankCents));
    final winner = ranked.first;

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
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Text(
                  '🏆 Match over',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: MargeColors.gold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${winner.profile.avatarEmoji} ${winner.profile.name} '
                  'wins with ${winner.bankCents}¢',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.separated(
                    itemCount: ranked.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = ranked[i];
                      return PlayerChip(
                        player: p,
                        isActive: i == 0,
                      );
                    },
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    ref.read(matchProvider.notifier).rematch();
                  },
                  child: const Text('REMATCH'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _leaveToLobby,
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
