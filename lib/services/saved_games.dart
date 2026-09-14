import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/match_checkpoint.dart';
import 'coin_ledger.dart';

/// One unfinished table kept apart from every other table and the gem bank.
class SavedGame {
  const SavedGame({
    required this.id,
    required this.savedAt,
    required this.table,
  });

  final String id;
  final DateTime savedAt;
  final MatchCheckpoint table;

  String get resumeLine => table.resumeLine;
  String get seatSummary => table.seatSummary;

  Map<String, Object?> toJson() => {
    'id': id,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'table': table.toJson(),
  };

  static SavedGame? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final table = MatchCheckpoint.fromJson(raw['table']);
    if (id is! String || id.isEmpty || table == null || !table.isUnfinished) {
      return null;
    }
    final stamp = raw['savedAt'];
    final savedAt = stamp is String ? DateTime.tryParse(stamp)?.toUtc() : null;
    return SavedGame(
      id: id,
      savedAt: savedAt ?? DateTime.now().toUtc(),
      table: table,
    );
  }

  static String newId() {
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = Random().nextInt(1000).toString().padLeft(3, '0');
    return 'sg-$stamp-$salt';
  }
}

/// Unfinished games on disk. Completed games are not stored.
class SavedGameStore {
  SavedGameStore({
    List<SavedGame> games = const [],
    this.loaded = false,
    SharedPreferences? prefs,
  }) : games = List<SavedGame>.from(games),
       _prefs = prefs;

  static const prefsKey = 'saved_games_v1';

  /// Captured before [runApp] so the lobby can offer resume on first paint.
  static SavedGameStore? bootstrap;

  final List<SavedGame> games;
  final bool loaded;
  SharedPreferences? _prefs;
  Future<void> _saveChain = Future<void>.value();

  bool get hasPrefs => _prefs != null;

  SavedGame? byId(String id) {
    for (final game in games) {
      if (game.id == id) return game;
    }
    return null;
  }

  void upsert(SavedGame game) {
    if (!game.table.isUnfinished) {
      remove(game.id);
      return;
    }
    final next = [
      for (final existing in games)
        if (existing.id != game.id) existing,
      game,
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    games
      ..clear()
      ..addAll(next);
    _persistNow();
  }

  void remove(String id) {
    games.removeWhere((g) => g.id == id);
    _persistNow();
  }

  String encode() => jsonEncode({
    'games': [for (final game in games) game.toJson()],
  });

  static SavedGameStore decode(
    String? raw, {
    SharedPreferences? prefs,
    bool loaded = true,
  }) {
    if (raw == null || raw.isEmpty) {
      return SavedGameStore(loaded: loaded, prefs: prefs);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return SavedGameStore(loaded: loaded, prefs: prefs);
      }
      final list = decoded['games'];
      final games = <SavedGame>[
        if (list is List)
          for (final item in list)
            if (SavedGame.fromJson(item) case final game?) game,
      ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return SavedGameStore(games: games, loaded: loaded, prefs: prefs);
    } catch (_) {
      return SavedGameStore(loaded: loaded, prefs: prefs);
    }
  }

  Future<void> flush() => _saveChain;

  /// Attach prefs (and optionally seed from disk) without wiping memory.
  Future<void> attachPrefs([SharedPreferences? prefs]) async {
    _prefs ??= prefs ?? await SharedPreferences.getInstance();
  }

  void _persistNow() {
    final prefs = _prefs;
    if (prefs == null) {
      debugPrint('SavedGameStore: skip persist — prefs not attached yet');
      return;
    }
    final payload = encode();
    _saveChain = _saveChain
        .catchError((Object e, StackTrace st) {
          debugPrint('SavedGameStore: prior save error cleared: $e\n$st');
        })
        .then((_) => prefs.setString(prefsKey, payload))
        .then((_) {})
        .catchError((Object e, StackTrace st) {
          debugPrint('SavedGameStore: persist failed: $e\n$st');
        });
  }

  static Future<SavedGameStore> load({SharedPreferences? prefs}) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    return decode(store.getString(prefsKey), prefs: store, loaded: true);
  }

  /// Put a finished or dropped table's local gems back in the main bank.
  /// Other tables are not touched. Uses the explicit bank, not an implicit 100.
  static int returnLocalGems({
    required PlayerCoinLedger ledger,
    required String localName,
    required int tableGems,
  }) {
    if (tableGems <= 0) return ledger.availableHumanGems(localName);
    final name = PlayerCoinLedger.localIdentity(localName);
    final current = ledger.savedCents(name, bot: false) ?? 0;
    final next = current + tableGems;
    ledger.write(name, bot: false, cents: next);
    return next;
  }
}

class SavedGamesNotifier extends Notifier<List<SavedGame>> {
  SavedGameStore? _live;
  Future<void>? _prefsReady;

  SavedGameStore get store {
    final live = _live;
    if (live != null) return live;
    final seeded = SavedGameStore.bootstrap;
    _live = seeded ?? SavedGameStore();
    return _live!;
  }

  @override
  List<SavedGame> build() {
    final seeded = SavedGameStore.bootstrap;
    if (seeded != null) {
      _live = seeded;
      _prefsReady = _ensurePrefs();
      return List<SavedGame>.from(seeded.games);
    }
    _live = SavedGameStore();
    _prefsReady = _ensurePrefs().then((_) => reload());
    return const [];
  }

  Future<void> _ensurePrefs() async {
    try {
      await store.attachPrefs();
    } catch (e, st) {
      debugPrint('SavedGamesNotifier: prefs attach failed: $e\n$st');
    }
  }

  Future<void> ensureReady() async {
    await (_prefsReady ?? _ensurePrefs());
  }

  void _publish() {
    final live = _live;
    if (live == null) return;
    state = List<SavedGame>.from(live.games);
  }

  void upsert(SavedGame game) {
    // Kick prefs attach if somehow missing; persist no-ops until ready,
    // then [ensureReady]/flush] from leave/pause writes the queue.
    unawaited(_ensurePrefs());
    store.upsert(game);
    _publish();
  }

  void remove(String id) {
    unawaited(_ensurePrefs());
    store.remove(id);
    _publish();
  }

  Future<void> flush() async {
    await ensureReady();
    // Re-encode after prefs attach in case earlier upserts were skipped.
    if (store.hasPrefs && store.games.isNotEmpty) {
      store._persistNow();
    }
    await store.flush();
  }

  /// Load from disk and merge with in-memory games (memory wins on same id).
  /// Never drops an unfinished table that was upserted before prefs attached.
  Future<void> reload() async {
    try {
      final loaded = await SavedGameStore.load();
      final existing = _live;
      if (existing == null) {
        _live = loaded;
        state = List<SavedGame>.from(loaded.games);
        return;
      }
      await existing.attachPrefs(loaded._prefs);
      final byId = <String, SavedGame>{
        for (final g in loaded.games) g.id: g,
        for (final g in existing.games) g.id: g,
      };
      final merged = byId.values.toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      existing.games
        ..clear()
        ..addAll(merged);
      if (existing.hasPrefs) {
        existing._persistNow();
      }
      _live = existing;
      state = List<SavedGame>.from(existing.games);
    } catch (e, st) {
      debugPrint('SavedGamesNotifier: reload failed: $e\n$st');
    }
  }
}


final savedGamesProvider =
    NotifierProvider<SavedGamesNotifier, List<SavedGame>>(
      SavedGamesNotifier.new,
    );
