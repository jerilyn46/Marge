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

/// Turns server room snapshots into the list of server-confirmed rolls the
/// table has not shown yet, oldest first: yours, the opponent's, a bot's or
/// a timeout auto-play. The first snapshot only primes it, so opening,
/// rejoining or reconnecting into a match never replays old rolls.
///
/// With the server's `rollSeq` + `recentRolls` (QA 2048+), a snapshot that
/// coalesced several rolls (an auto-played set, a bot run, rapid rolls, a
/// resume) yields every roll it carries, in order. Servers with only
/// `lastRoll` yield the latest one; rooms without `rollSeq` fall back to the
/// visible turn (round/seat/set/roll), which never double-fires.
class OnlineRollTracker {
  bool _primed = false;
  String? _lastKey;
  int _lastSeq = 0;
  int _serial = 0;

  /// Number of rolls handed out so far.
  int get serial => _serial;

  static String? rollKey(MatchView? m) {
    if (m == null) return null;
    if (m.rollSeq != null) return 's${m.rollSeq}';
    final t = m.turn;
    if (t == null || !t.hasRolled) return null;
    return 't${m.round}:${t.seat}:${t.setNumber}:${t.rollNumber}';
  }

  /// Returns true when [m] carries at least one roll not seen yet.
  bool observe(MatchView? m) => take(m).isNotEmpty;

  /// The rolls in [m] this tracker has not handed out yet, oldest first.
  List<OnlineRoll> take(MatchView? m) {
    if (m == null) return const [];
    final seq = m.rollSeq;
    if (!_primed) {
      _primed = true;
      _lastKey = rollKey(m);
      _lastSeq = seq ?? 0;
      return const [];
    }
    if (seq != null) {
      _lastKey = rollKey(m);
      if (seq <= _lastSeq) return const [];
      final from = _lastSeq;
      _lastSeq = seq;
      final recent = [
        for (final r in m.recentRolls)
          if (r.seq > from && r.seq <= seq) r,
      ]..sort((a, b) => a.seq.compareTo(b.seq));
      final out = recent.isNotEmpty
          ? recent
          : [
              m.lastRoll ??
                  OnlineRoll(
                    seq: seq,
                    seat: m.turn?.seat ?? 0,
                    dice: m.turn?.dice ?? const [1, 1, 1],
                    held: m.turn?.kept ?? const [false, false, false],
                    rollNumber: m.turn?.rollNumber ?? 0,
                  ),
            ];
      _serial += out.length;
      return out;
    }
    final key = rollKey(m);
    final fire = key != null && key != _lastKey;
    _lastKey = key ?? _lastKey;
    if (!fire) return const [];
    final t = m.turn!;
    _serial++;
    return [
      OnlineRoll(
        seq: -_serial,
        seat: t.seat,
        dice: t.dice,
        held: t.kept,
        rollNumber: t.rollNumber,
      ),
    ];
  }
}

/// Plays server rolls on the table one at a time, in order. A roll that
/// arrives mid-throw, or while the previous result is still on show, waits
/// its turn instead of cutting the throw short. Each final face stays up
/// for [dwell] before the next throw. Pure state: the table owns the timers.
///
/// Cycle: [add] → [next] (throw) → [settled] → (dwell) → [rested] → …
class RollPlayback {
  static const dwell = Duration(milliseconds: 700);

  final List<OnlineRoll> _queue = [];
  OnlineRoll? _current;
  int _serial = 0;
  bool _busy = false;
  bool _resting = false;

  /// The roll on the tray (throwing, or its result on show); null before
  /// the first one.
  OnlineRoll? get current => _current;

  /// Bumped once per throw started: feed to [DiceTray.rollSerial].
  int get serial => _serial;

  /// True from a throw's start until it landed with nothing queued behind it
  /// (queued throws and the dwell between them count as busy).
  bool get busy => _busy;

  /// The last result is on show for [dwell]; a new roll waits for [rested].
  bool get resting => _resting;

  int get pending => _queue.length;

  /// Queues rolls; returns true when the caller should call [next] now.
  bool add(Iterable<OnlineRoll> rolls) {
    _queue.addAll(rolls);
    // Queued behind a result on show: lock input until it has played.
    if (_resting && _queue.isNotEmpty) _busy = true;
    return !_busy && !_resting && _queue.isNotEmpty;
  }

  /// Starts the next queued throw; false if nothing is queued.
  bool next() {
    if (_queue.isEmpty) return false;
    _current = _queue.removeAt(0);
    _serial++;
    _busy = true;
    _resting = false;
    return true;
  }

  /// Throw [serial] landed. The caller shows the result for [dwell], then
  /// calls [rested]. Returns false for a stale/duplicate report (ignore it).
  bool settled(int serial) {
    if (!_busy || serial != _serial) return false;
    _resting = true;
    if (_queue.isEmpty) _busy = false; // input unlocks right away
    return true;
  }

  /// The dwell after a landing is over: returns true when the caller should
  /// call [next] (another roll is queued).
  bool rested() {
    _resting = false;
    if (_queue.isEmpty) {
      _busy = false;
      return false;
    }
    return true;
  }
}
