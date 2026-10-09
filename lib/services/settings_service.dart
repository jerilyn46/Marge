import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GameSettings {
  const GameSettings({
    this.sfxEnabled = true,
    this.hapticsEnabled = true,
    this.seenRules = false,
    this.playerName = 'You',
    this.hasUsername = false,
    this.loaded = false,
  });

  final bool sfxEnabled;
  final bool hapticsEnabled;
  final bool seenRules;
  final String playerName;

  /// True once the player has confirmed a username (prefs key written).
  final bool hasUsername;
  final bool loaded;

  GameSettings copyWith({
    bool? sfxEnabled,
    bool? hapticsEnabled,
    bool? seenRules,
    String? playerName,
    bool? hasUsername,
    bool? loaded,
  }) => GameSettings(
    sfxEnabled: sfxEnabled ?? this.sfxEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    seenRules: seenRules ?? this.seenRules,
    playerName: playerName ?? this.playerName,
    hasUsername: hasUsername ?? this.hasUsername,
    loaded: loaded ?? this.loaded,
  );
}

class SettingsNotifier extends Notifier<GameSettings> {
  static const _kSfx = 'sfx';
  static const _kHaptics = 'haptics';
  static const _kRules = 'seen_rules';
  static const _kName = 'player_name';

  /// Cold-start settings captured before [runApp] so the username gate
  /// does not flash Home then jump.
  static GameSettings? bootstrap;

  SharedPreferences? _prefs;

  @override
  GameSettings build() {
    final seeded = bootstrap;
    if (seeded != null) {
      Future.microtask(() async {
        try {
          _prefs ??= await SharedPreferences.getInstance();
        } catch (e, st) {
          debugPrint('SettingsNotifier: prefs attach failed: $e\n$st');
        }
      });
      return seeded;
    }
    Future.microtask(() async {
      try {
        await _load();
      } catch (e, st) {
        debugPrint(
          'SettingsNotifier: prefs load failed (using defaults): $e\n$st',
        );
        state = state.copyWith(loaded: true);
      }
    });
    return const GameSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    state = fromPrefs(prefs);
  }

  static GameSettings fromPrefs(SharedPreferences prefs) {
    final hasName = prefs.containsKey(_kName);
    final raw = prefs.getString(_kName)?.trim();
    return GameSettings(
      sfxEnabled: prefs.getBool(_kSfx) ?? true,
      hapticsEnabled: prefs.getBool(_kHaptics) ?? true,
      seenRules: prefs.getBool(_kRules) ?? false,
      playerName: (raw != null && raw.isNotEmpty) ? raw : 'You',
      hasUsername: hasName && raw != null && raw.isNotEmpty,
      loaded: true,
    );
  }

  static Future<GameSettings> load({SharedPreferences? prefs}) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    return fromPrefs(store);
  }

  Future<void> setSfx(bool v) async {
    state = state.copyWith(sfxEnabled: v);
    await (_prefs ?? await SharedPreferences.getInstance()).setBool(_kSfx, v);
  }

  Future<void> setHaptics(bool v) async {
    state = state.copyWith(hapticsEnabled: v);
    await (_prefs ?? await SharedPreferences.getInstance()).setBool(
      _kHaptics,
      v,
    );
  }

  Future<void> setSeenRules(bool v) async {
    state = state.copyWith(seenRules: v);
    await (_prefs ?? await SharedPreferences.getInstance()).setBool(_kRules, v);
  }

  Future<void> setPlayerName(String v) async {
    final trimmed = v.trim();
    final name = trimmed.isEmpty ? 'You' : trimmed;
    state = state.copyWith(playerName: name, hasUsername: true, loaded: true);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(_kName, name);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, GameSettings>(
  SettingsNotifier.new,
);
