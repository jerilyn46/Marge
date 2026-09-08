import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GameSettings {
  const GameSettings({
    this.sfxEnabled = true,
    this.hapticsEnabled = true,
    this.seenRules = false,
    this.playerName = 'You',
  });

  final bool sfxEnabled;
  final bool hapticsEnabled;
  final bool seenRules;
  final String playerName;

  GameSettings copyWith({
    bool? sfxEnabled,
    bool? hapticsEnabled,
    bool? seenRules,
    String? playerName,
  }) => GameSettings(
    sfxEnabled: sfxEnabled ?? this.sfxEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    seenRules: seenRules ?? this.seenRules,
    playerName: playerName ?? this.playerName,
  );
}

class SettingsNotifier extends Notifier<GameSettings> {
  static const _kSfx = 'sfx';
  static const _kHaptics = 'haptics';
  static const _kRules = 'seen_rules';
  static const _kName = 'player_name';

  SharedPreferences? _prefs;

  @override
  GameSettings build() {
    // Defaults first — prefs must not throw before the lobby frame.
    Future.microtask(() async {
      try {
        await _load();
      } catch (e, st) {
        debugPrint(
          'SettingsNotifier: prefs load failed (using defaults): $e\n$st',
        );
      }
    });
    return const GameSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    state = GameSettings(
      sfxEnabled: prefs.getBool(_kSfx) ?? true,
      hapticsEnabled: prefs.getBool(_kHaptics) ?? true,
      seenRules: prefs.getBool(_kRules) ?? false,
      playerName: prefs.getString(_kName) ?? 'You',
    );
  }

  Future<void> setSfx(bool v) async {
    state = state.copyWith(sfxEnabled: v);
    await _prefs?.setBool(_kSfx, v);
  }

  Future<void> setHaptics(bool v) async {
    state = state.copyWith(hapticsEnabled: v);
    await _prefs?.setBool(_kHaptics, v);
  }

  Future<void> setSeenRules(bool v) async {
    state = state.copyWith(seenRules: v);
    await _prefs?.setBool(_kRules, v);
  }

  Future<void> setPlayerName(String v) async {
    state = state.copyWith(playerName: v);
    await _prefs?.setString(_kName, v);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, GameSettings>(
  SettingsNotifier.new,
);
