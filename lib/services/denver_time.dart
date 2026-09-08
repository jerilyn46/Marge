/// America/Denver civil time without a timezone package.
///
/// US DST (since 2007): second Sunday in March 02:00 MST → MDT (UTC−6),
/// first Sunday in November 02:00 MDT → MST (UTC−7). Monday 00:00 is never
/// a transition, so the weekly bot-reset boundary is unambiguous.
class DenverTime {
  DenverTime._();

  static const mst = Duration(hours: -7);
  static const mdt = Duration(hours: -6);

  /// UTC instant when Denver springs forward in [year].
  static DateTime dstStartUtc(int year) {
    final sunday = _nthWeekdayOfMonth(year, DateTime.march, DateTime.sunday, 2);
    // 02:00 MST = 09:00 UTC.
    return DateTime.utc(sunday.year, sunday.month, sunday.day, 9);
  }

  /// UTC instant when Denver falls back in [year].
  static DateTime dstEndUtc(int year) {
    final sunday = _nthWeekdayOfMonth(
      year,
      DateTime.november,
      DateTime.sunday,
      1,
    );
    // 02:00 MDT = 08:00 UTC.
    return DateTime.utc(sunday.year, sunday.month, sunday.day, 8);
  }

  static Duration offsetAt(DateTime utc) {
    final u = utc.toUtc();
    final start = dstStartUtc(u.year);
    final end = dstEndUtc(u.year);
    if (!u.isBefore(start) && u.isBefore(end)) return mdt;
    return mst;
  }

  /// Denver wall clock stored in a UTC [DateTime] (fields are local, not UTC).
  static DateTime wallClock(DateTime utc) => utc.toUtc().add(offsetAt(utc));

  /// Most recent Monday 00:00 America/Denver, as a UTC instant.
  static DateTime weekStartUtc(DateTime utcNow) {
    final wall = wallClock(utcNow);
    final daysSinceMonday = wall.weekday - DateTime.monday;
    final monday = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
    ).subtract(Duration(days: daysSinceMonday));
    return localToUtc(monday.year, monday.month, monday.day);
  }

  /// Convert a Denver local midnight (or any civil time) to UTC.
  static DateTime localToUtc(int year, int month, int day, [int hour = 0, int minute = 0]) {
    final naive = DateTime.utc(year, month, day, hour, minute);
    final asMst = naive.subtract(mst);
    if (offsetAt(asMst) == mst) return asMst;
    return naive.subtract(mdt);
  }

  static DateTime _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
    final first = DateTime.utc(year, month, 1);
    var delta = (weekday - first.weekday) % 7;
    if (delta < 0) delta += 7;
    final day = 1 + delta + (n - 1) * 7;
    return DateTime.utc(year, month, day);
  }
}
