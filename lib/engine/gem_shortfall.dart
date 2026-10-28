/// A seated player cannot cover a first-roll trips payment (2s–6s).
///
/// They must add virtual gems and pay the full amount, or pay what
/// they have at this table and quit this game. Nothing is taken until
/// they choose. Bots never reach this — they pay what they have and quit.
class GemShortfall {
  const GemShortfall({
    required this.payerSeatIndex,
    required this.rollerSeatIndex,
    required this.dueGems,
    required this.face,
    this.queuedSeatIndexes = const [],
    this.toPot = false,
    this.zeroBank = false,
  });

  /// A human a payout left at 0 gems: nothing is owed. They add gems
  /// ([dueGems] = enough to keep playing) or quit; if they quit and only
  /// the roller is left, the roller takes the pot.
  final bool zeroBank;

  /// Owed to the pot (missed triple ones), not to [rollerSeatIndex].
  final bool toPot;

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
    if (toPot) 'toPot': true,
    if (zeroBank) 'zeroBank': true,
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
      toPot: raw['toPot'] == true,
      zeroBank: raw['zeroBank'] == true,
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
