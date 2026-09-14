/// A seated player cannot cover a first-roll trips payment (2s–6s).
///
/// They must add play-money gems and pay the full amount, or pay what
/// they have at this table and quit this game. Nothing is taken until
/// they choose. Bots never reach this — they pay what they have and quit.
class GemShortfall {
  const GemShortfall({
    required this.payerSeatIndex,
    required this.rollerSeatIndex,
    required this.dueGems,
    required this.face,
    this.queuedSeatIndexes = const [],
  });

  final int payerSeatIndex;
  final int rollerSeatIndex;
  final int dueGems;
  final int face;
  final List<int> queuedSeatIndexes;

  Map<String, Object?> toJson() => {
    'payerSeatIndex': payerSeatIndex,
    'rollerSeatIndex': rollerSeatIndex,
    'dueGems': dueGems,
    'face': face,
    'queuedSeatIndexes': queuedSeatIndexes,
  };

  static GemShortfall? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final payer = _asInt(raw['payerSeatIndex']);
    final roller = _asInt(raw['rollerSeatIndex']);
    final due = _asInt(raw['dueGems']);
    final face = _asInt(raw['face']);
    if (payer == null || roller == null || due == null || face == null) {
      return null;
    }
    final queuedRaw = raw['queuedSeatIndexes'];
    return GemShortfall(
      payerSeatIndex: payer,
      rollerSeatIndex: roller,
      dueGems: due,
      face: face,
      queuedSeatIndexes: queuedRaw is List
          ? [
              for (final v in queuedRaw)
                if (_asInt(v) != null) _asInt(v)!,
            ]
          : const [],
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}
