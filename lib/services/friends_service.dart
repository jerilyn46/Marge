import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/player.dart';

/// Someone the local player knows and may invite to a chair.
///
/// There is no live session. A seated friend is a named waiting chair
/// unless they are actually on this device (they are not, in this build).
class FriendEntry {
  const FriendEntry({required this.name, this.seated = true});

  final String name;
  final bool seated;

  FriendEntry copyWith({String? name, bool? seated}) => FriendEntry(
    name: name ?? this.name,
    seated: seated ?? this.seated,
  );

  Map<String, Object> toJson() => {'name': name, 'seated': seated};

  static FriendEntry? fromJson(Object? raw) {
    if (raw is String) {
      final name = raw.trim();
      if (name.isEmpty) return null;
      return FriendEntry(name: name);
    }
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return FriendEntry(
      name: name.trim(),
      seated: raw['seated'] != false,
    );
  }
}

class FriendsState {
  const FriendsState({this.friends = const [], this.loaded = false});

  final List<FriendEntry> friends;
  final bool loaded;

  List<String> get names => friends.map((f) => f.name).toList();

  List<String> get seatedNames =>
      friends.where((f) => f.seated).map((f) => f.name).toList();

  FriendsState copyWith({List<FriendEntry>? friends, bool? loaded}) =>
      FriendsState(
        friends: friends ?? this.friends,
        loaded: loaded ?? this.loaded,
      );
}

/// Pure add/remove rules (unit-testable without prefs).
class FriendsLogic {
  FriendsLogic._();

  static const maxFriends = 7;

  static String? normalize(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return null;
    if (name == WaitingSeat.name) return null;
    return name;
  }

  static bool sameName(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  static ({List<FriendEntry> friends, String? error}) add(
    List<FriendEntry> friends,
    String raw,
  ) {
    final name = normalize(raw);
    if (name == null) {
      return (friends: friends, error: 'Enter a name');
    }
    if (friends.any((f) => sameName(f.name, name))) {
      return (friends: friends, error: 'Already on the list');
    }
    if (friends.length >= maxFriends) {
      return (friends: friends, error: 'The group is full (7 friends)');
    }
    return (
      friends: [...friends, FriendEntry(name: name)],
      error: null,
    );
  }

  static List<FriendEntry> remove(List<FriendEntry> friends, String name) =>
      friends.where((f) => !sameName(f.name, name)).toList();
}

class FriendsNotifier extends Notifier<FriendsState> {
  static const prefsKey = 'friends_list_v1';

  /// Loaded in main before the lobby so the list is not empty on first paint.
  static FriendsState? bootstrap;

  SharedPreferences? _prefs;

  @override
  FriendsState build() {
    final seeded = bootstrap;
    if (seeded != null) {
      Future.microtask(() async {
        try {
          _prefs = await SharedPreferences.getInstance();
        } catch (e, st) {
          debugPrint('FriendsNotifier: prefs attach failed: $e\n$st');
        }
      });
      return seeded;
    }
    Future.microtask(() async {
      try {
        await reload();
      } catch (e, st) {
        debugPrint('FriendsNotifier: prefs load failed: $e\n$st');
      }
    });
    return const FriendsState();
  }

  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    state = decode(prefs.getString(prefsKey)).copyWith(loaded: true);
  }

  /// Returns an error message, or null on success.
  Future<String?> add(String raw) async {
    final result = FriendsLogic.add(state.friends, raw);
    if (result.error != null) return result.error;
    state = state.copyWith(friends: result.friends, loaded: true);
    await _persist();
    return null;
  }

  Future<void> remove(String name) async {
    state = state.copyWith(
      friends: FriendsLogic.remove(state.friends, name),
      loaded: true,
    );
    await _persist();
  }

  Future<void> setSeated(String name, bool seated) async {
    state = state.copyWith(
      friends: [
        for (final f in state.friends)
          FriendsLogic.sameName(f.name, name) ? f.copyWith(seated: seated) : f,
      ],
    );
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(prefsKey, encode(state));
  }

  static String encode(FriendsState state) => jsonEncode(
    state.friends.map((f) => f.toJson()).toList(),
  );

  static FriendsState decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const FriendsState(loaded: true);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const FriendsState(loaded: true);
      final friends = <FriendEntry>[];
      for (final item in decoded) {
        final entry = FriendEntry.fromJson(item);
        if (entry == null) continue;
        if (friends.any((f) => FriendsLogic.sameName(f.name, entry.name))) {
          continue;
        }
        friends.add(entry);
      }
      return FriendsState(friends: friends, loaded: true);
    } catch (_) {
      return const FriendsState(loaded: true);
    }
  }

  static Future<FriendsState> load({SharedPreferences? prefs}) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    return decode(store.getString(prefsKey));
  }
}

final friendsProvider = NotifierProvider<FriendsNotifier, FriendsState>(
  FriendsNotifier.new,
);
