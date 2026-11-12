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
  });
  final int index;
  final SeatKind kind;
  final String? uid;
  final String? displayName;
  final int bank;
  final bool eliminated;

  factory MatchSeat.fromMap(Map<String, dynamic> m) => MatchSeat(
    index: _i(m['index']),
    kind: _kind(m['kind'] as String?),
    uid: m['uid'] as String?,
    displayName: m['displayName'] as String?,
    bank: _i(m['bank']),
    eliminated: m['eliminated'] as bool? ?? false,
  );
}

class OnlineTurn {
  const OnlineTurn({
    required this.seat,
    required this.rollNumber,
    required this.dice,
    required this.kept,
    this.scoreKind,
  });
  final int seat;
  final int rollNumber;
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
  });
  final List<MatchSeat> seats;
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
  );
}
