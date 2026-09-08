import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/player.dart';
import '../engine/seat_coin_book.dart';
import 'denver_time.dart';

/// One planned lobby chair and the coins to show (null = waiting, no bank).
class LobbyCoinSeat {
  const LobbyCoinSeat({
    required this.name,
    required this.emoji,
    required this.waiting,
    required this.bot,
    this.coins,
  });

  final String name;
  final String emoji;
  final bool waiting;
  final bool bot;
  final int? coins;
}

/// Persistent per-player coin banks.
///
/// Keys are player identity, not seat index:
/// * local user display name (`You`, or whatever they typed)
/// * hotseat `Player 2`, `Player 3`, …
/// * each bot name (`Spike`, `Mira`, …)
///
/// Human balances persist forever. Bot balances reset to 100¢ once each
/// Monday 00:00 America/Denver. Waiting online chairs are never stored.
class PlayerCoinLedger implements SeatCoinBook {
  PlayerCoinLedger({
    Map<String, int>? balances,
    this.lastBotResetAt,
    this.loaded = false,
    SharedPreferences? prefs,
    this.onChanged,
  }) : balances = Map<String, int>.from(balances ?? {}),
       _prefs = prefs;

  static const startingCents = 100;
  static const prefsKey = 'player_coin_ledger_v1';
  static const _kBalances = 'balances';
  static const _kLastBotResetAt = 'lastBotResetAt';

  /// Storage key for a playing identity. Humans and bots never share a key.
  static String storageKey(String name, {required bool bot}) {
    final trimmed = name.trim();
    return bot ? 'bot:$trimmed' : 'human:$trimmed';
  }

  final Map<String, int> balances;

  /// UTC instant of the Monday 00:00 Denver boundary last applied.
  DateTime? lastBotResetAt;

  final bool loaded;

  SharedPreferences? _prefs;
  Future<void> _saveChain = Future<void>.value();

  /// Fired after a memory write so the lobby can rebuild. Persistence is separate.
  void Function()? onChanged;

  /// Cold-start ledger captured before [runApp] so the lobby does not flash 100¢.
  static PlayerCoinLedger? bootstrap;

  bool get hasHistory => balances.isNotEmpty;

  int? savedCents(String name, {required bool bot}) {
    final key = storageKey(name, bot: bot);
    if (!balances.containsKey(key)) return null;
    return balances[key];
  }

  @override
  int openingCents(String name, {required bool bot, required int fallback}) {
    if (_isWaitingName(name)) return 0;
    return savedCents(name, bot: bot) ?? fallback;
  }

  /// Write the seat's current bank and persist immediately when prefs are attached.
  @override
  void write(String name, {required bool bot, required int cents}) {
    if (_isWaitingName(name)) return;
    balances[storageKey(name, bot: bot)] = cents;
    _persistNow();
    onChanged?.call();
  }

  /// Drop every bot bank back to 100¢ if this Denver week has not been reset.
  ///
  /// Humans are never touched. Returns true when a reset was applied (and
  /// stored) so callers can refresh UI. Calling again the same week is a no-op.
  bool applyWeeklyBotReset(DateTime utcNow) {
    final boundary = DenverTime.weekStartUtc(utcNow.toUtc());
    final last = lastBotResetAt;
    if (last != null && !last.isBefore(boundary)) return false;

    for (final key in balances.keys.toList()) {
      if (key.startsWith('bot:')) {
        balances[key] = startingCents;
      }
    }
    lastBotResetAt = boundary;
    _persistNow();
    onChanged?.call();
    return true;
  }

  /// Copy for Riverpod equality so the lobby rebuilds after a write.
  PlayerCoinLedger snapshot() => PlayerCoinLedger(
    balances: balances,
    lastBotResetAt: lastBotResetAt,
    loaded: loaded,
    prefs: _prefs,
  );

  void publish() => onChanged?.call();

  String encode() => jsonEncode({
    _kBalances: balances,
    if (lastBotResetAt != null)
      _kLastBotResetAt: lastBotResetAt!.toUtc().toIso8601String(),
  });

  static PlayerCoinLedger decode(
    String? raw, {
    SharedPreferences? prefs,
    bool loaded = true,
  }) {
    if (raw == null || raw.isEmpty) {
      return PlayerCoinLedger(loaded: loaded, prefs: prefs);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return PlayerCoinLedger(loaded: loaded, prefs: prefs);
      }
      final rawBalances = decoded[_kBalances];
      final balances = <String, int>{};
      if (rawBalances is Map) {
        for (final entry in rawBalances.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key is! String) continue;
          if (value is int) {
            balances[key] = value;
          } else if (value is num) {
            balances[key] = value.toInt();
          }
        }
      }
      DateTime? last;
      final stamp = decoded[_kLastBotResetAt];
      if (stamp is String && stamp.isNotEmpty) {
        last = DateTime.tryParse(stamp)?.toUtc();
      }
      return PlayerCoinLedger(
        balances: balances,
        lastBotResetAt: last,
        loaded: loaded,
        prefs: prefs,
      );
    } catch (_) {
      return PlayerCoinLedger(loaded: loaded, prefs: prefs);
    }
  }

  Future<void> persist() async {
    _persistNow();
    await flush();
  }

  Future<void> flush() => _saveChain;

  void _persistNow() {
    final prefs = _prefs;
    if (prefs == null) return;
    final payload = encode();
    _saveChain = _saveChain.then((_) => prefs.setString(prefsKey, payload));
  }

  static bool _isWaitingName(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty || trimmed == WaitingSeat.name;
  }

  /// Load from disk, apply a due Monday bot reset, and persist that stamp.
  static Future<PlayerCoinLedger> load({
    SharedPreferences? prefs,
    DateTime? utcNow,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final ledger = decode(store.getString(prefsKey), prefs: store, loaded: true);
    ledger.applyWeeklyBotReset(utcNow ?? DateTime.now().toUtc());
    if (ledger.lastBotResetAt != null) {
      await ledger.flush();
    }
    return ledger;
  }

  /// Lobby chairs in the same order a match will seat them.
  static List<LobbyCoinSeat> lobbySeats({
    required String localName,
    required int otherHumans,
    required int online,
    required int bots,
    required PlayerCoinLedger ledger,
    List<String> friendNames = const [],
    int fallback = startingCents,
  }) {
    final seats = <LobbyCoinSeat>[];
    final you = localName.trim().isEmpty ? 'You' : localName.trim();
    seats.add(
      LobbyCoinSeat(
        name: you,
        emoji: '😎',
        waiting: false,
        bot: false,
        coins: ledger.openingCents(you, bot: false, fallback: fallback),
      ),
    );
    for (var i = 0; i < otherHumans; i++) {
      final name = 'Player ${i + 2}';
      seats.add(
        LobbyCoinSeat(
          name: name,
          emoji: '🎲',
          waiting: false,
          bot: false,
          coins: ledger.openingCents(name, bot: false, fallback: fallback),
        ),
      );
    }
    for (final raw in friendNames) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      seats.add(
        LobbyCoinSeat(
          name: name,
          emoji: '👋',
          waiting: true,
          bot: false,
          coins: ledger.openingCents(name, bot: false, fallback: fallback),
        ),
      );
    }
    for (var i = 0; i < online; i++) {
      seats.add(
        const LobbyCoinSeat(
          name: WaitingSeat.name,
          emoji: WaitingSeat.emoji,
          waiting: true,
          bot: false,
        ),
      );
    }
    for (var i = 0; i < bots; i++) {
      final name = BotRoster.nameAt(i);
      seats.add(
        LobbyCoinSeat(
          name: name,
          emoji: BotRoster.emojiAt(i),
          waiting: false,
          bot: true,
          coins: ledger.openingCents(name, bot: true, fallback: fallback),
        ),
      );
    }
    return seats;
  }
}

class CoinLedgerNotifier extends Notifier<PlayerCoinLedger> {
  PlayerCoinLedger? _live;

  PlayerCoinLedger get book {
    final live = _live;
    if (live != null) return live;
    final seeded = PlayerCoinLedger.bootstrap;
    _live = seeded ?? state;
    return _live!;
  }

  @override
  PlayerCoinLedger build() {
    final seeded = PlayerCoinLedger.bootstrap;
    if (seeded != null) {
      seeded.onChanged = _onLiveChanged;
      _live = seeded;
      return seeded.snapshot();
    }
    final empty = PlayerCoinLedger();
    _live = empty;
    Future.microtask(() async {
      try {
        await reload();
      } catch (e, st) {
        debugPrint('CoinLedgerNotifier: prefs load failed: $e\n$st');
      }
    });
    return empty.snapshot();
  }

  /// Apply a due bot reset and expose the loaded book (lobby / match start).
  PlayerCoinLedger prepare({DateTime? utcNow}) {
    final live = book;
    live.onChanged = _onLiveChanged;
    if (live.applyWeeklyBotReset(utcNow ?? DateTime.now().toUtc())) {
      state = live.snapshot();
    }
    return live;
  }

  void _onLiveChanged() {
    final live = _live;
    if (live == null) return;
    state = live.snapshot();
  }

  void publish() => _onLiveChanged();

  Future<void> reload({DateTime? utcNow}) async {
    final loaded = await PlayerCoinLedger.load(utcNow: utcNow);
    loaded.onChanged = _onLiveChanged;
    _live = loaded;
    state = loaded.snapshot();
  }
}

final coinLedgerProvider = NotifierProvider<CoinLedgerNotifier, PlayerCoinLedger>(
  CoinLedgerNotifier.new,
);
