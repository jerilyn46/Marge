import 'package:flutter/foundation.dart';

/// App version shown in Settings (kept in step with pubspec by a test).
const kAppVersion = '0.1.42+42';

/// One breadcrumb for the dice "settling" input lock. Ids and counters only:
/// nothing personal (no names, gems or device ids).
class SettleEvent {
  SettleEvent(this.at, this.event, this.serial, this.roll, this.reason);
  final Duration at;
  final String event;
  final int? serial;
  final int? roll;
  final String reason;

  @override
  String toString() {
    final s = (at.inMilliseconds / 1000).toStringAsFixed(2);
    return '+${s}s $event throw=${serial ?? '-'} roll=${roll ?? '-'} $reason';
  }
}

/// Tiny in-memory ring buffer of settle-lock breadcrumbs. Readable from the
/// hidden Settings view (long-press the version) so a stuck table can be
/// screenshotted. Also mirrored to debugPrint.
class SettleLog {
  SettleLog._();
  static const capacity = 80;
  static final _clock = Stopwatch()..start();
  static final List<SettleEvent> _ring = [];

  static List<SettleEvent> get entries => List.unmodifiable(_ring);

  static void add(String event, {int? serial, int? roll, String reason = ''}) {
    final e = SettleEvent(_clock.elapsed, event, serial, roll, reason);
    if (_ring.length >= capacity) _ring.removeAt(0);
    _ring.add(e);
    if (kDebugMode) debugPrint('[settle] $e');
  }

  @visibleForTesting
  static void clear() => _ring.clear();
}
