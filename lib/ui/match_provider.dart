import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cosmetics/skins_service.dart';
import '../engine/engine.dart';
import '../services/saved_games.dart';
import '../services/table_gem_book.dart';
import '../services/coin_ledger.dart';
import '../services/friends_service.dart';
import '../services/local_turn_alerts.dart';
import '../services/settings_service.dart';
import '../services/sfx_service.dart';
import '../services/turn_notice.dart';

class MatchViewState {
  const MatchViewState({
    required this.snapshot,
    this.showConfetti = false,
    this.busyBot = false,
    this.unlockBanner,

    /// When true, pot-win celebration is playing; sticky strip waits.
    this.holdHandoffStrip = false,

    /// In-app "{name}'s turn" banner. Local notification is separate.
    this.turnNotice,
  });

  final MatchSnapshot snapshot;
  final bool showConfetti;
  final bool busyBot;
  final String? unlockBanner;
  final bool holdHandoffStrip;
  final String? turnNotice;

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
    String? turnNotice,
    bool clearTurnNotice = false,
  }) => MatchViewState(
    snapshot: snapshot ?? this.snapshot,
    showConfetti: showConfetti ?? this.showConfetti,
    busyBot: busyBot ?? this.busyBot,
    unlockBanner: clearUnlockBanner
        ? null
        : (unlockBanner ?? this.unlockBanner),
    holdHandoffStrip: holdHandoffStrip ?? this.holdHandoffStrip,
    turnNotice: clearTurnNotice ? null : (turnNotice ?? this.turnNotice),
  );
}

class MatchNotifier extends Notifier<MatchViewState?> {
  MatchController? _controller;
  final SfxService _sfx = SfxService();
  final LocalTurnAlerts _alerts = LocalTurnAlerts();
  Timer? _botTimer;
  String? _lastNoticeSeatId;
  String? _savedId;
  bool _releasedTable = false;

  /// Seat index of the local (device) player — always 0.
  static const int localSeat = 0;

  @override
  MatchViewState? build() {
    ref.onDispose(() => _botTimer?.cancel());
    return null;
  }

  void start({
    int botCount = 3,
    int otherHumanCount = 0,
    int onlinePlayerCount = 0,
    List<String> friendNames = const [],
    String? playerName,
  }) {
    _botTimer?.cancel();
    _lastNoticeSeatId = null;
    final chosen = [
      for (final name in friendNames)
        if (name.trim().isNotEmpty) name.trim(),
    ];
    final plan = MatchConfig.clampLobbyCounts(
      botCount,
      otherHumanCount,
      onlinePlayerCount,
      chosen.length,
    );
    botCount = plan.bots;
    otherHumanCount = plan.others;
    onlinePlayerCount = plan.online;
    final seatedFriends = chosen.take(plan.friends).toList();
    // Waiting chairs are not opponents. Do not invent a bot to fill them.
    // Only the old bots/humans-only path gets a lone-bot fallback.
    if (botCount + otherHumanCount < 1) {
      if (onlinePlayerCount == 0 && seatedFriends.isEmpty) {
        botCount = 1;
      } else {
        return;
      }
    }

    _persistActive();

    final localName = playerName ?? 'You';
    final names = <String>[
      localName,
      for (var i = 0; i < otherHumanCount; i++) 'Player ${i + 2}',
    ];
    final ledger = ref.read(coinLedgerProvider.notifier);
    final live = ledger.prepare();
    final available = live.availableHumanGems(localName);
    final sit = PlayerCoinLedger.sitDownGems(available);
    if (sit > 0) {
      ledger.drawAvailable(localName, sit);
    }
    final book = TableGemBook();
    book.seed(PlayerCoinLedger.localIdentity(localName), bot: false, gems: sit);
    for (var i = 1; i < names.length; i++) {
      book.seed(
        names[i],
        bot: false,
        gems: live.openingCents(names[i], bot: false, fallback: 100),
      );
    }
    for (var i = 0; i < botCount; i++) {
      final name = BotRoster.nameAt(i);
      book.seed(
        name,
        bot: true,
        gems: live.openingCents(name, bot: true, fallback: 100),
      );
    }
    _savedId = SavedGame.newId();
    _releasedTable = false;
    _controller = MatchController(
      config: MatchConfig(
        botCount: botCount,
        otherHumanCount: otherHumanCount,
        onlinePlayerCount: onlinePlayerCount,
        friendNames: seatedFriends,
        localPlayerName: localName,
        humanNames: names,
      ),
      rng: Random(),
      coins: book,
    );
    _controller!.startMatch();
    ref.read(cosmeticsProvider.notifier).beginMatch();
    _syncSettings();
    state = MatchViewState(snapshot: _controller!.snapshot);
    _announceTurn();
    _persistActive();
    _scheduleBots();
  }

  void rematch() {
    final cfg = _controller?.config;
    final name = ref.read(settingsProvider).playerName;
    start(
      botCount: cfg?.botCount ?? 3,
      otherHumanCount: cfg?.otherHumanCount ?? 0,
      onlinePlayerCount: cfg?.onlinePlayerCount ?? 0,
      friendNames: cfg?.friendNames ?? const [],
      playerName: name,
    );
  }

  int? moveFromMainBank(int gems) {
    final c = _controller;
    if (c == null || gems <= 0) return null;
    if (c.snapshot.phase == MatchPhase.matchEnd) return null;
    final name = c.config.localPlayerName;
    final ledger = ref.read(coinLedgerProvider.notifier);
    if (ledger.drawAvailable(name, gems) == null) return null;
    final next = c.grantLocalPlayCoins(gems);
    if (next == null) {
      ledger.grantHumanPlayCoins(name, cents: gems);
      return null;
    }
    _publish();
    return next;
  }

  bool resume(String id) {
    final store = ref.read(savedGamesProvider.notifier).store;
    final game = store.byId(id);
    if (game == null) return false;
    if (_savedId != null && _savedId != id) {
      _persistActive();
    }
    _botTimer?.cancel();
    _lastNoticeSeatId = null;
    _savedId = id;
    _releasedTable = false;
    final book = TableGemBook();
    for (final player in game.table.players) {
      if (!player.profile.participates) continue;
      book.seed(
        player.profile.name,
        bot: player.profile.isBot,
        gems: player.bankCents,
      );
    }
    _controller = MatchController(
      config: game.table.config,
      rng: Random(),
      coins: book,
    );
    _controller!.restore(game.table);
    _syncSettings();
    state = MatchViewState(snapshot: _controller!.snapshot);
    _announceTurn();
    _scheduleBots();
    return true;
  }

  Future<void> leaveUnfinished() async {
    _botTimer?.cancel();
    final c = _controller;
    if (c == null) {
      state = null;
      return;
    }
    if (c.snapshot.phase == MatchPhase.matchEnd) {
      _releaseFinishedTable();
    } else {
      _persistActive();
      await ref.read(savedGamesProvider.notifier).flush();
    }
    _controller = null;
    _savedId = null;
    state = null;
  }

  void persistUnfinished() {
    _persistActive();
    unawaited(ref.read(savedGamesProvider.notifier).flush());
  }

  void dropSaved(String id) {
    final store = ref.read(savedGamesProvider.notifier).store;
    final game = store.byId(id);
    if (game == null) return;
    final local = game.table.localPlayer;
    if (local != null && local.bankCents > 0) {
      final ledger = ref.read(coinLedgerProvider.notifier);
      SavedGameStore.returnLocalGems(
        ledger: ledger.book,
        localName: local.profile.name,
        tableGems: local.bankCents,
      );
      ledger.publish();
    }
    ref.read(savedGamesProvider.notifier).remove(id);
    if (_savedId == id) {
      _botTimer?.cancel();
      _controller = null;
      _savedId = null;
      state = null;
    }
  }

  bool coverShortfall() {
    final c = _controller;
    final pending = c?.snapshot.pendingShortfall;
    if (c == null || pending == null) return false;
    final payer = c.snapshot.players[pending.payerSeatIndex];
    final need = pending.dueGems - payer.bankCents;
    final name = c.config.localPlayerName;
    final ledger = ref.read(coinLedgerProvider.notifier);
    if (need > 0) {
      if (ledger.drawAvailable(name, need) == null) return false;
      if (c.addTableGems(pending.payerSeatIndex, need) == null) {
        ledger.grantHumanPlayCoins(name, cents: need);
        return false;
      }
    }
    final ok = c.coverShortfall();
    _publish();
    if (ok) _scheduleBots();
    return ok;
  }

  void quitShortfall() {
    final c = _controller;
    if (c == null) return;
    c.quitShortfall();
    _publish();
    _scheduleBots();
  }

  void _persistActive() {
    final c = _controller;
    final id = _savedId;
    if (c == null || id == null) return;
    if (c.snapshot.phase == MatchPhase.matchEnd ||
        c.snapshot.phase == MatchPhase.setup) {
      _releaseFinishedTable();
      return;
    }
    ref
        .read(savedGamesProvider.notifier)
        .upsert(
          SavedGame(
            id: id,
            savedAt: DateTime.now().toUtc(),
            table: c.capture(),
          ),
        );
  }

  void _releaseFinishedTable() {
    if (_releasedTable) return;
    final c = _controller;
    if (c == null) {
      _releasedTable = true;
      return;
    }
    PlayerState? local;
    for (final p in c.snapshot.players) {
      if (p.profile.id == 'human_0') {
        local = p;
        break;
      }
    }
    if (local != null && local.bankCents > 0) {
      final ledger = ref.read(coinLedgerProvider.notifier);
      SavedGameStore.returnLocalGems(
        ledger: ledger.book,
        localName: c.config.localPlayerName,
        tableGems: local.bankCents,
      );
      ledger.publish();
    }
    final id = _savedId;
    if (id != null) {
      ref.read(savedGamesProvider.notifier).remove(id);
    }
    _releasedTable = true;
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
      turnNotice: state?.turnNotice,
    );
    _announceTurn();
    _persistActive();
  }

  /// Local "{name}'s turn" for You or a friend in the group. Bots never notify.
  void _announceTurn() {
    final c = _controller;
    final current = state;
    if (c == null || current == null) return;
    if (c.snapshot.phase != MatchPhase.playing) return;
    final seat = c.snapshot.currentPlayer;
    if (!seat.profile.isHuman) {
      if (current.turnNotice != null) {
        state = current.copyWith(clearTurnNotice: true);
      }
      return;
    }
    if (seat.profile.id == _lastNoticeSeatId) return;
    final friends = ref.read(friendsProvider).names;
    final localName = ref.read(settingsProvider).playerName;
    final msg = TurnNotice.forSeat(
      seatName: seat.profile.name,
      kind: seat.profile.kind,
      localName: localName,
      friendNames: friends,
    );
    if (msg == null) return;
    _lastNoticeSeatId = seat.profile.id;
    state = current.copyWith(turnNotice: msg);
    unawaited(_alerts.show(msg));
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
    if (c.snapshot.phase == MatchPhase.awaitingHandoff ||
        c.snapshot.phase == MatchPhase.awaitingShortfall)
      return;
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
    if (payout?.kind == ScoreKind.tripleOnesPotWin) {
      await _sfx.potWin();
      await _applyLocalCosmetics(seat, payout);
      // Winner keeps the seat on a fresh set. Confetti only — no handoff.
      _publish(confetti: true);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (state != null) {
          state = state!.copyWith(showConfetti: false);
        }
      });
      return;
    }
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
    // Bust can auto-resolve on the 3rd roll.
    if (payout != null &&
        payout.kind == ScoreKind.none &&
        c.snapshot.phase == MatchPhase.awaitingHandoff) {
      await _sfx.bust();
      await _applyLocalCosmetics(seat, payout);
    }
    if (c.snapshot.phase == MatchPhase.awaitingHandoff ||
        c.snapshot.phase == MatchPhase.awaitingShortfall) {
      // Gate: human must tap Continue / Next player.
      return;
    }
    _scheduleBots();
  }

  Future<void> bank() async {
    final c = _controller;
    if (c == null) return;
    if (c.snapshot.phase == MatchPhase.awaitingHandoff ||
        c.snapshot.phase == MatchPhase.awaitingShortfall)
      return;
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
    if (c.snapshot.phase == MatchPhase.awaitingHandoff ||
        c.snapshot.phase == MatchPhase.awaitingShortfall) {
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
    if (c.snapshot.phase == MatchPhase.awaitingHandoff ||
        c.snapshot.phase == MatchPhase.awaitingShortfall) {
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
      if (_controller!.snapshot.phase == MatchPhase.awaitingHandoff ||
          _controller!.snapshot.phase == MatchPhase.awaitingShortfall) {
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
      if (_controller!.snapshot.phase == MatchPhase.awaitingHandoff ||
          _controller!.snapshot.phase == MatchPhase.awaitingShortfall) {
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
