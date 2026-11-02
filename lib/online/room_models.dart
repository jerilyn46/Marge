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
  });

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
    seats: ((m['seats'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Seat.fromMap(Map<String, dynamic>.from(e)))
        .toList(),
  );
}
