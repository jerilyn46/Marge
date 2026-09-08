import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cosmetics/skins_service.dart';
import '../engine/engine.dart';
import '../services/settings_service.dart';
import '../services/sfx_service.dart';

class MatchViewState {
  const MatchViewState({
    required this.snapshot,
    this.showConfetti = false,
    this.busyBot = false,
    this.unlockBanner,

    /// When true, pot-win celebration is playing; sticky strip waits.
    this.holdHandoffStrip = false,
  });

  final MatchSnapshot snapshot;
  final bool showConfetti;
  final bool busyBot;
  final String? unlockBanner;
  final bool holdHandoffStrip;

  /// Sticky result strip is ready to show (gate active, celebration done).
  bool get showHandoffStrip =>
      snapshot.awaitingHandoff && !holdHandoffStrip && !showConfetti;

  MatchViewState copyWith({
    MatchSnapshot? snapshot,
    bool? showConfetti,
    bool? busyBot,
    String? unlockBanner,
    bool clearUnlockBanner = false,
    bool? holdHandoffStrip,
  }) => MatchViewState(
    snapshot: snapshot ?? this.snapshot,
    showConfetti: showConfetti ?? this.showConfetti,
    busyBot: busyBot ?? this.busyBot,
    unlockBanner: clearUnlockBanner
        ? null
        : (unlockBanner ?? this.unlockBanner),
    holdHandoffStrip: holdHandoffStrip ?? this.holdHandoffStrip,
  );
}

class MatchNotifier extends Notifier<MatchViewState?> {
  MatchController? _controller;
  final SfxService _sfx = SfxService();
  Timer? _botTimer;

  /// Seat index of the local (device) player — always 0.
  static const int localSeat = 0;

  @override
  MatchViewState? build() {
    ref.onDispose(() => _botTimer?.cancel());
    return null;
  }

  void start({int botCount = 3, int otherHumanCount = 0, String? playerName}) {
    _botTimer?.cancel();
    final clamped = MatchConfig.clampLobby(botCount, otherHumanCount);
    botCount = clamped.$1;
    otherHumanCount = clamped.$2;
    // Ensure at least one opponent (lobby UI should already enforce this).
    if (botCount + otherHumanCount < 1) {
      botCount = 1;
    }

    final localName = playerName ?? 'You';
    final names = <String>[
      localName,
      for (var i = 0; i < otherHumanCount; i++) 'Player ${i + 2}',
    ];
    _controller = MatchController(
      config: MatchConfig(
        botCount: botCount,
        otherHumanCount: otherHumanCount,
        localPlayerName: localName,
        humanNames: names,
      ),
      rng: Random(),
    );
    _controller!.startMatch();
    ref.read(cosmeticsProvider.notifier).beginMatch();
    _syncSettings();
    state = MatchViewState(snapshot: _controller!.snapshot);
    _scheduleBots();
  }

  void rematch() {
    final cfg = _controller?.config;
    final name = ref.read(settingsProvider).playerName;
    start(
      botCount: cfg?.botCount ?? 3,
      otherHumanCount: cfg?.otherHumanCount ?? 0,
      playerName: name,
    );
  }

  void _syncSettings() {
    final s = ref.read(settingsProvider);
    _sfx.sfxEnabled = s.sfxEnabled;
    _sfx.hapticsEnabled = s.hapticsEnabled;
  }

  void _publish({
    bool confetti = false,
    String? unlockBanner,
    bool? holdHandoffStrip,
  }) {
    final c = _controller;
    if (c == null) return;
    state = MatchViewState(
      snapshot: c.snapshot,
      showConfetti: confetti,
      busyBot: state?.busyBot ?? false,
      unlockBanner: unlockBanner ?? state?.unlockBanner,
      holdHandoffStrip: holdHandoffStrip ?? false,
    );
  }

  void clearUnlockBanner() {
    if (state?.unlockBanner != null) {
      state = state!.copyWith(clearUnlockBanner: true);
    }
  }

  Future<void> _applyLocalCosmetics(int actingSeat, PayoutEvent? payout) async {
    if (payout == null || actingSeat != localSeat) return;
    final cos = ref.read(cosmeticsProvider.notifier);
    List<String> toasts = const [];
    if (payout.kind == ScoreKind.tripleOnesPotWin && payout.celebratory) {
      toasts = await cos.recordLocalPotWin();
    } else if (payout.kind != ScoreKind.none &&
        payout.kind != ScoreKind.tripleOnesPotWin) {
      // Scoring bank (trips / straight / triple-ones pay).
      toasts = await cos.recordLocalHandWin();
    } else if (payout.kind == ScoreKind.none) {
      toasts = await cos.recordLocalBust();
    }
    if (toasts.isNotEmpty && state != null) {
      state = state!.copyWith(unlockBanner: toasts.join('\n'));
      Future.delayed(const Duration(seconds: 4), clearUnlockBanner);
    }
  }

  void toggleKeep(int index) {
    _controller?.toggleKeep(index);
    _publish();
  }

  Future<void> roll() async {
    final c = _controller;
    if (c == null) return;
    if (c.snapshot.phase == MatchPhase.awaitingHandoff) return;
    if (c.snapshot.currentPlayer.profile.isBot) return;
    final seat = c.snapshot.currentSeatIndex;
    _syncSettings();
    await _sfx.roll();
    c.roll();
    final afterTurn = c.snapshot.turn;
    // Miss with rolls left: same player, still playing. Do not bust or hand off.
    if (afterTurn != null &&
        afterTurn.mustKeepRolling &&
        c.snapshot.phase == MatchPhase.playing) {
      _publish();
      return;
    }
    final payout = c.snapshot.lastPayout;
    if (payout?.celebratory == true &&
        c.snapshot.phase == MatchPhase.awaitingHandoff) {
      await _sfx.potWin();
      // Celebration first; sticky strip after confetti.
      _publish(confetti: true, holdHandoffStrip: true);
      await _applyLocalCosmetics(seat, payout);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (state != null && _controller != null) {
        state = state!.copyWith(
          showConfetti: false,
          holdHandoffStrip: false,
          snapshot: _controller!.snapshot,
        );
      }
      // Do not schedule bots — wait for Next/Continue.
      return;
    }
    _publish();
    // Bust can auto-resolve on the 3rd roll.
    if (payout != null &&
        payout.kind == ScoreKind.none &&
        c.snapshot.phase == MatchPhase.awaitingHandoff) {
      await _sfx.bust();
      await _applyLocalCosmetics(seat, payout);
    }
    if (c.snapshot.phase == MatchPhase.awaitingHandoff) {
      // Gate: human must tap Continue / Next player.
      return;
    }
    _scheduleBots();
  }

  Future<void> bank() async {
    final c = _controller;
    if (c == null) return;
    if (c.snapshot.phase == MatchPhase.awaitingHandoff) return;
    if (c.snapshot.currentPlayer.profile.isBot) return;
    final seat = c.snapshot.currentSeatIndex;
    final t = c.snapshot.turn;
    if (t == null || !t.hasRolled) return;
    // Do not end the turn early without a winning hand while rolls remain.
    if (t.mustKeepRolling || (!t.canBank && !t.mustFinish)) return;
    _syncSettings();
    if (t.lastScore.isScoring) {
      await _sfx.bank();
    } else {
      await _sfx.bust();
    }
    c.bank();
    final payout = c.snapshot.lastPayout;
    if (payout?.celebratory == true &&
        c.snapshot.phase == MatchPhase.awaitingHandoff) {
      await _sfx.potWin();
      _publish(confetti: true, holdHandoffStrip: true);
      await _applyLocalCosmetics(seat, payout);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (state != null && _controller != null) {
        state = state!.copyWith(
          showConfetti: false,
          holdHandoffStrip: false,
          snapshot: _controller!.snapshot,
        );
      }
      return;
    }
    _publish();
    await _applyLocalCosmetics(seat, payout);
    if (c.snapshot.phase == MatchPhase.awaitingHandoff) {
      return;
    }
    _scheduleBots();
  }

  /// Dismiss last-roll strip and hand off to the next seat.
  void confirmHandoff() {
    final c = _controller;
    if (c == null) return;
    if (c.snapshot.phase != MatchPhase.awaitingHandoff) return;
    _botTimer?.cancel();
    c.confirmHandoff();
    _publish();
    _scheduleBots();
  }

  void endMatch() {
    _botTimer?.cancel();
    _controller?.endMatch();
    _publish();
  }

  void _scheduleBots() {
    _botTimer?.cancel();
    final c = _controller;
    if (c == null) return;
    if (c.snapshot.phase == MatchPhase.matchEnd) return;
    // Bots must not act while the handoff strip is up.
    if (c.snapshot.phase == MatchPhase.awaitingHandoff) {
      if (state != null) state = state!.copyWith(busyBot: false);
      return;
    }
    if (!c.snapshot.currentPlayer.profile.isBot) {
      if (state != null) state = state!.copyWith(busyBot: false);
      return;
    }
    if (state != null) state = state!.copyWith(busyBot: true);
    _botTimer = Timer(const Duration(milliseconds: 700), () async {
      if (_controller == null) return;
      if (_controller!.snapshot.phase == MatchPhase.awaitingHandoff) {
        if (state != null) state = state!.copyWith(busyBot: false);
        return;
      }
      _syncSettings();
      final before = _controller!.snapshot.lastPayout;
      _controller!.tickBot();
      final after = _controller!.snapshot.lastPayout;
      if (after != null &&
          after != before &&
          after.celebratory &&
          _controller!.snapshot.phase == MatchPhase.awaitingHandoff) {
        await _sfx.potWin();
        _publish(confetti: true, holdHandoffStrip: true);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (state != null && _controller != null) {
          state = state!.copyWith(
            showConfetti: false,
            holdHandoffStrip: false,
            snapshot: _controller!.snapshot,
          );
        }
        // Wait for human to tap Continue / Next player.
        return;
      }
      if (after != null && after != before && after.kind == ScoreKind.none) {
        await _sfx.bust();
      } else if (_controller!.snapshot.phase != MatchPhase.awaitingHandoff ||
          after == before) {
        await _sfx.roll();
      }
      _publish();
      if (_controller!.snapshot.phase == MatchPhase.awaitingHandoff) {
        if (state != null) state = state!.copyWith(busyBot: false);
        return;
      }
      _scheduleBots();
    });
  }
}

final matchProvider = NotifierProvider<MatchNotifier, MatchViewState?>(
  MatchNotifier.new,
);
