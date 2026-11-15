import 'room_models.dart';

/// Picks the room [uid] can rejoin: a running match where their seat is still
/// in, else a lobby where they hold a seat. Finished/abandoned rooms, and
/// matches they already left or busted out of, are ignored. Newest
/// (highest version) wins a tie.
Room? pickActiveRoom(Iterable<Room> rooms, String uid) {
  bool live(Room r) {
    if (r.status == RoomStatus.playing) {
      final m = r.match;
      if (m == null || m.finished) return false;
      return m.seats.any((s) => s.uid == uid && !s.eliminated);
    }
    if (r.status == RoomStatus.lobby) return r.seats.any((s) => s.uid == uid);
    return false;
  }

  final c = rooms.where(live).toList()
    ..sort((a, b) {
      final pa = a.status == RoomStatus.playing ? 1 : 0;
      final pb = b.status == RoomStatus.playing ? 1 : 0;
      return pb != pa ? pb - pa : b.version - a.version;
    });
  return c.isEmpty ? null : c.first;
}
