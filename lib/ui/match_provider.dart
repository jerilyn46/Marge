import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';
import '../services/settings_service.dart';
import '../services/sfx_service.dart';

class MatchViewState {
  const MatchViewState({
    required this.snapshot,
    this.showConfetti = false,
    this.busyBot = false,
  });

  final MatchSnapshot snapshot;
  final bool showConfetti;
  final bool busyBot;

  MatchViewState copyWith({
    MatchSnapshot? snapshot,
    bool? showConfetti,
    bool? busyBot,
  }) =>
      MatchViewState(
        snapshot: snapshot ?? this.snapshot,
        showConfetti: showConfetti ?? this.showConfetti,
        busyBot: busyBot ?? this.busyBot,
      );
}

class MatchNotifier extends Notifier<MatchViewState?> {
  MatchController? _controller;
  final SfxService _sfx = SfxService();
  Timer? _botTimer;

  @override
  MatchViewState? build() {
    ref.onDispose(() => _botTimer?.cancel());
    return null;
  }

  void start({required int humanCount, String? playerName}) {
    _botTimer?.cancel();
    final names = <String>[
      playerName ?? 'You',
      for (var i = 1; i < humanCount; i++) 'Player ${i + 1}',
    ];
    _controller = MatchController(
      config: MatchConfig(humanCount: humanCount, humanNames: names),
      rng: Random(),
    );
    _controller!.startMatch();
    _syncSettings();
    state = MatchViewState(snapshot: _controller!.snapshot);
    _scheduleBots();
  }

  void rematch() {
    final humans = _controller?.config.humanCount ?? 1;
    final name = ref.read(settingsProvider).playerName;
    start(humanCount: humans, playerName: name);
  }

  void _syncSettings() {
    final s = ref.read(settingsProvider);
    _sfx.sfxEnabled = s.sfxEnabled;
    _sfx.hapticsEnabled = s.hapticsEnabled;
  }

  void _publish({bool confetti = false}) {
    final c = _controller;
    if (c == null) return;
    state = MatchViewState(
      snapshot: c.snapshot,
      showConfetti: confetti,
      busyBot: state?.busyBot ?? false,
    );
  }

  void toggleKeep(int index) {
    _controller?.toggleKeep(index);
    _publish();
  }

  Future<void> roll() async {
    final c = _controller;
    if (c == null) return;
    if (c.snapshot.currentPlayer.profile.isBot) return;
    _syncSettings();
    await _sfx.roll();
    c.roll();
    final payout = c.snapshot.lastPayout;
    if (payout?.celebratory == true) {
      await _sfx.potWin();
      _publish(confetti: true);
      Future.delayed(const Duration(seconds: 2), () {
        if (state != null) {
          state = state!.copyWith(showConfetti: false);
        }
      });
    } else {
      _publish();
    }
    _scheduleBots();
  }

  Future<void> bank() async {
    final c = _controller;
    if (c == null) return;
    if (c.snapshot.currentPlayer.profile.isBot) return;
    final t = c.snapshot.turn;
    if (t == null || !t.hasRolled) return;
    _syncSettings();
    if (t.lastScore.isScoring) {
      await _sfx.bank();
    } else {
      await _sfx.bust();
    }
    c.bank();
    final payout = c.snapshot.lastPayout;
    if (payout?.celebratory == true) {
      await _sfx.potWin();
      _publish(confetti: true);
      Future.delayed(const Duration(seconds: 2), () {
        if (state != null) {
          state = state!.copyWith(showConfetti: false);
        }
      });
    } else {
      _publish();
    }
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
    if (!c.snapshot.currentPlayer.profile.isBot) {
      if (state != null) state = state!.copyWith(busyBot: false);
      return;
    }
    if (state != null) state = state!.copyWith(busyBot: true);
    _botTimer = Timer(const Duration(milliseconds: 700), () async {
      if (_controller == null) return;
      _syncSettings();
      final before = _controller!.snapshot.lastPayout;
      _controller!.tickBot();
      final after = _controller!.snapshot.lastPayout;
      if (after != null && after != before && after.celebratory) {
        await _sfx.potWin();
        _publish(confetti: true);
        Future.delayed(const Duration(seconds: 2), () {
          if (state != null) {
            state = state!.copyWith(showConfetti: false);
          }
        });
      } else {
        if (after != null &&
            after != before &&
            after.kind == ScoreKind.none) {
          await _sfx.bust();
        } else {
          await _sfx.roll();
        }
        _publish();
      }
      _scheduleBots();
    });
  }
}

final matchProvider =
    NotifierProvider<MatchNotifier, MatchViewState?>(MatchNotifier.new);
