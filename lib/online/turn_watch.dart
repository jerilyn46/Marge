import 'room_models.dart';

/// Fires once each time the turn passes TO [uid] in an online match.
///
/// The first snapshot only primes it (opening or rejoining a match that is
/// already on your turn does not buzz), and repeated snapshots of the same
/// turn (reconnect / resubscribe) never re-fire. A fresh set on your own seat
/// after the turn lapped the bots counts only if it wasn't already yours.
class YourTurnDetector {
  bool _primed = false;
  bool _wasMine = false;

  /// Returns true when this snapshot is a transition to the local player.
  bool observe(MatchView? m, String uid) {
    final mine = isMyTurn(m, uid);
    final fire = _primed && mine && !_wasMine;
    _primed = true;
    _wasMine = mine;
    return fire;
  }

  static bool isMyTurn(MatchView? m, String uid) {
    final t = m?.turn;
    if (m == null || m.finished || t == null) return false;
    if (t.seat < 0 || t.seat >= m.seats.length) return false;
    final s = m.seats[t.seat];
    return s.uid == uid && !s.eliminated;
  }
}

/// Turns server room snapshots into a local roll serial for [DiceTray]:
/// +1 exactly once per server-confirmed roll (yours, the opponent's, a bot's,
/// or a timeout auto-play). The first snapshot only primes it, so an initial
/// load, a rejoin or a reconnect never replays a roll.
///
/// Uses the server's `rollSeq` when present; older rooms fall back to the
/// visible turn (round/seat/set/roll), which misses rolls resolved inside the
/// same commit but never double-fires.
class OnlineRollTracker {
  bool _primed = false;
  String? _lastKey;
  int _serial = 0;

  int get serial => _serial;

  static String? rollKey(MatchView? m) {
    if (m == null) return null;
    if (m.rollSeq != null) return 's${m.rollSeq}';
    final t = m.turn;
    if (t == null || !t.hasRolled) return null;
    return 't${m.round}:${t.seat}:${t.setNumber}:${t.rollNumber}';
  }

  /// Returns true when [m] carries a roll this tracker has not seen yet.
  bool observe(MatchView? m) {
    final key = rollKey(m);
    final fire = _primed && key != null && key != _lastKey;
    _primed = true;
    _lastKey = key ?? _lastKey;
    if (fire) _serial++;
    return fire;
  }
}
