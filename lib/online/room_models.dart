/// Client-side mirrors of the Firestore `rooms/{roomId}` schema.
/// See docs/multiplayer-invite-mvp.md. The server (Cloud Functions) is the
/// only writer of room state; clients read and call functions.
library;

enum RoomStatus { lobby, playing, finished, abandoned }

enum SeatKind { host, human, bot, open }

RoomStatus _status(String? s) => RoomStatus.values.firstWhere(
  (e) => e.name == s,
  orElse: () => RoomStatus.lobby,
);

SeatKind _kind(String? s) =>
    SeatKind.values.firstWhere((e) => e.name == s, orElse: () => SeatKind.open);

class Seat {
  const Seat({
    required this.index,
    required this.kind,
    this.uid,
    this.displayName,
    this.connected = false,
  });

  final int index;
  final SeatKind kind;
  final String? uid;
  final String? displayName;
  final bool connected;

  bool get isOpen => kind == SeatKind.open;

  factory Seat.fromMap(Map<String, dynamic> m) => Seat(
    index: (m['index'] as num?)?.toInt() ?? 0,
    kind: _kind(m['kind'] as String?),
    uid: m['uid'] as String?,
    displayName: m['displayName'] as String?,
    connected: m['connected'] as bool? ?? false,
  );
}

class Room {
  const Room({
    required this.id,
    required this.code,
    required this.hostUid,
    required this.status,
    required this.ante,
    required this.seats,
    this.pot = 0,
    this.turnSeat,
    this.version = 0,
    this.match,
  });

  /// Server match state (null in lobby).
  final MatchView? match;

  final String id;
  final String code;
  final String hostUid;
  final RoomStatus status;
  final int ante;
  final int pot;
  final int? turnSeat;
  final int version;
  final List<Seat> seats;

  int get openSeats => seats.where((s) => s.isOpen).length;

  factory Room.fromMap(String id, Map<String, dynamic> m) => Room(
    id: id,
    code: m['code'] as String? ?? '',
    hostUid: m['hostUid'] as String? ?? '',
    status: _status(m['status'] as String?),
    ante: (m['ante'] as num?)?.toInt() ?? 0,
    pot: (m['pot'] as num?)?.toInt() ?? 0,
    turnSeat: (m['turnSeat'] as num?)?.toInt(),
    version: (m['version'] as num?)?.toInt() ?? 0,
    match: m['match'] is Map
        ? MatchView.fromMap(Map<String, dynamic>.from(m['match'] as Map))
        : null,
    seats: ((m['seats'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Seat.fromMap(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

int _i(Object? v, [int d = 0]) => (v as num?)?.toInt() ?? d;
List<int> _ints(Object? v) =>
    ((v as List?) ?? const []).map((e) => _i(e)).toList();

class MatchSeat {
  const MatchSeat({
    required this.index,
    required this.kind,
    this.uid,
    this.displayName,
    required this.bank,
    required this.eliminated,
    this.left = false,
    this.leftWith,
  });
  final int index;
  final SeatKind kind;
  final String? uid;
  final String? displayName;
  final int bank;
  final bool eliminated;

  /// Left mid-match (leave / delete) rather than busting to 0 (QA 2048+).
  final bool left;

  /// Table bank the leaver carried out to their online gems (0 if forfeited).
  final int? leftWith;

  factory MatchSeat.fromMap(Map<String, dynamic> m) => MatchSeat(
    index: _i(m['index']),
    kind: _kind(m['kind'] as String?),
    uid: m['uid'] as String?,
    displayName: m['displayName'] as String?,
    bank: _i(m['bank']),
    eliminated: m['eliminated'] as bool? ?? false,
    left: m['left'] as bool? ?? false,
    leftWith: (m['leftWith'] as num?)?.toInt(),
  );
}

class OnlineTurn {
  const OnlineTurn({
    required this.seat,
    required this.rollNumber,
    required this.dice,
    required this.kept,
    this.scoreKind,
    this.setNumber = 1,
  });
  final int seat;
  final int rollNumber;
  final int setNumber;
  final List<int> dice;
  final List<bool> kept;
  final String? scoreKind;

  bool get hasRolled => rollNumber > 0;
  bool get canRoll => rollNumber < 3;
  bool get isScoring => scoreKind != null && scoreKind != 'none';
  int get rollsLeft => 3 - rollNumber;

  factory OnlineTurn.fromMap(Map<String, dynamic> m) => OnlineTurn(
    seat: _i(m['seat']),
    rollNumber: _i(m['rollNumber']),
    dice: _ints(m['dice']),
    kept: ((m['kept'] as List?) ?? const [false, false, false])
        .map((e) => e == true)
        .toList(),
    scoreKind: (m['score'] as Map?)?['kind'] as String?,
    setNumber: _i(m['setNumber'], 1),
  );
}

/// The server's most recent roll (any seat, incl. bots / timeout autoplay).
/// Kept after the turn resolves so the table can show and animate it.
class OnlineRoll {
  const OnlineRoll({
    required this.seq,
    required this.seat,
    required this.dice,
    required this.held,
    required this.rollNumber,
  });
  final int seq;
  final int seat;
  final List<int> dice;

  /// Dice held through this roll (they did not tumble).
  final List<bool> held;
  final int rollNumber;

  factory OnlineRoll.fromMap(Map<String, dynamic> m) => OnlineRoll(
    seq: _i(m['seq']),
    seat: _i(m['seat']),
    dice: _ints(m['dice']),
    held: ((m['held'] as List?) ?? const [false, false, false])
        .map((e) => e == true)
        .toList(),
    rollNumber: _i(m['rollNumber']),
  );
}

class MatchView {
  const MatchView({
    required this.seats,
    required this.pot,
    required this.round,
    required this.finished,
    this.turn,
    this.winnerSeat,
    this.lastPayoutMessage,
    this.startBanks,
    this.rollSeq,
    this.lastRoll,
    this.recentRolls = const [],
  });
  final List<MatchSeat> seats;

  /// The server's last few rolls, oldest first (QA 2048+); empty on older
  /// rooms. Lets the table animate rolls whose snapshots coalesced.
  final List<OnlineRoll> recentRolls;

  /// +1 per server roll (servers from QA 2046 on); null on older rooms.
  final int? rollSeq;
  final OnlineRoll? lastRoll;

  /// Table bank per seat when the match started (server >= autoplay change).
  final List<int>? startBanks;
  final int pot;
  final int round;
  final bool finished;
  final OnlineTurn? turn;
  final int? winnerSeat;
  final String? lastPayoutMessage;

  factory MatchView.fromMap(Map<String, dynamic> m) => MatchView(
    seats: ((m['seats'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MatchSeat.fromMap(Map<String, dynamic>.from(e)))
        .toList(),
    pot: _i(m['pot']),
    round: _i(m['round']),
    finished: m['status'] == 'finished',
    turn: m['turn'] is Map
        ? OnlineTurn.fromMap(Map<String, dynamic>.from(m['turn'] as Map))
        : null,
    winnerSeat: (m['winnerSeat'] as num?)?.toInt(),
    lastPayoutMessage: (m['lastPayout'] as Map?)?['message'] as String?,
    startBanks: m['startBanks'] is List ? _ints(m['startBanks']) : null,
    rollSeq: (m['rollSeq'] as num?)?.toInt(),
    lastRoll: m['lastRoll'] is Map
        ? OnlineRoll.fromMap(Map<String, dynamic>.from(m['lastRoll'] as Map))
        : null,
    recentRolls: ((m['recentRolls'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => OnlineRoll.fromMap(Map<String, dynamic>.from(e)))
        .toList(),
  );

  /// Per-seat result rows for the end-of-match screen (occupied seats only).
  /// [fallbackStart] is used when the server did not record startBanks
  /// (rooms started before that field existed), e.g. the first banks the
  /// client saw.
  List<SeatResult> results({List<int>? fallbackStart}) {
    final start = startBanks ?? fallbackStart;
    return [
      for (final s in seats)
        if (s.kind != SeatKind.open)
          SeatResult(
            seat: s.index,
            name: s.displayName ?? 'Seat ${s.index + 1}',
            uid: s.uid,
            start: start != null && s.index < start.length
                ? start[s.index]
                : null,
            // A leaver's bank is zeroed when it goes home: show what they
            // carried out. Older rooms (no `left`) keep the plain bank/out.
            end: s.left ? (s.leftWith ?? s.bank) : s.bank,
            winner: s.index == winnerSeat,
            out: s.eliminated && !s.left,
            left: s.left,
          ),
    ];
  }
}

class SeatResult {
  const SeatResult({
    required this.seat,
    required this.name,
    required this.end,
    this.uid,
    this.start,
    this.winner = false,
    this.out = false,
    this.left = false,
  });
  final int seat;
  final String name;
  final String? uid;
  final int? start;
  final int end;
  final bool winner;
  final bool out;

  /// Left the table mid-match (row reads "· left", not "· out").
  final bool left;

  /// " · left", " · out" or "".
  String get statusSuffix => left ? ' · left' : (out ? ' · out' : '');

  int? get change => start == null ? null : end - start!;

  /// "+32", "−10", "±0"; null when the start is unknown.
  String? get changeLabel {
    final c = change;
    if (c == null) return null;
    if (c > 0) return '+$c';
    if (c < 0) return '−${-c}';
    return '±0';
  }
}
