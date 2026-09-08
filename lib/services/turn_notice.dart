import '../engine/player.dart';

/// Local-only turn copy. No push server — only this device is told.
class TurnNotice {
  TurnNotice._();

  static String message(String name) => "$name's turn";

  /// Group = local user plus friends they added. Bots never notify.
  /// Waiting chairs (including friends not on this device) never take a turn.
  static String? forSeat({
    required String seatName,
    required SeatKind kind,
    required String localName,
    required Iterable<String> friendNames,
  }) {
    if (kind != SeatKind.human) return null;
    final name = seatName.trim();
    if (name.isEmpty || name == WaitingSeat.name) return null;
    final local = localName.trim();
    if (name == local) return message(name);
    for (final friend in friendNames) {
      if (friend.trim().toLowerCase() == name.toLowerCase()) {
        return message(name);
      }
    }
    return null;
  }
}
