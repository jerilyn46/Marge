/// Where play resumes after an Out of gems (zeroBank) choice.
enum ZeroBankThen {
  /// Roller keeps the seat (after a win paid by others).
  sameSeat,

  /// The roller zeroed themselves (bust): hand off to the next seat.
  handoff,

  /// A seat zeroed paying the ante: start the turn at [_seat].
  startTurn,
}

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
    this.zeroBankThen = ZeroBankThen.sameSeat,
  });

  /// What happens after a [zeroBank] stay-in (or a quit that leaves 2+).
  final ZeroBankThen zeroBankThen;

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
    if (zeroBankThen != ZeroBankThen.sameSeat)
      'zeroBankThen': zeroBankThen.name,
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
      zeroBankThen: ZeroBankThen.values.firstWhere(
        (v) => v.name == raw['zeroBankThen'],
        orElse: () => ZeroBankThen.sameSeat,
      ),
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
