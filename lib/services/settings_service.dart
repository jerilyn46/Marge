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
  }) =>
      GameSettings(
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
    Future.microtask(_load);
    return const GameSettings();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    state = GameSettings(
      sfxEnabled: _prefs!.getBool(_kSfx) ?? true,
      hapticsEnabled: _prefs!.getBool(_kHaptics) ?? true,
      seenRules: _prefs!.getBool(_kRules) ?? false,
      playerName: _prefs!.getString(_kName) ?? 'You',
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

final settingsProvider =
    NotifierProvider<SettingsNotifier, GameSettings>(SettingsNotifier.new);
