import 'denver_time.dart';

/// Daily goals that pay free gems (inside the free-mint caps).
enum DailyGoal {
  /// Bank a scoring hand (any winning hand you bank yourself).
  bankScoringHand(id: 'bank_hand', title: 'Bank a scoring hand', gems: 15),

  /// Play a match through to the final results.
  finishMatch(id: 'finish_match', title: 'Finish a match', gems: 20);

  const DailyGoal({required this.id, required this.title, required this.gems});

  final String id;
  final String title;
  final int gems;

  static DailyGoal? byId(String id) {
    for (final g in values) {
      if (g.id == id) return g;
    }
    return null;
  }
}

/// Free-mint ledger: every free gem grant (daily drip, daily goals, streak
/// rewards) is clamped to [dailyCap] per America/Denver day and [weeklyCap]
/// per Denver week (Monday 00:00). Rewarded ads and IAP packs never pass
/// through here.
///
/// Also holds per-day goal progress/claims and the claimed-day streak.
/// Pure state; [PlayerCoinLedger] persists it inside its own JSON blob.
class FreeMintLedger {
  FreeMintLedger({
    this.dayKey,
    this.dayMinted = 0,
    this.weekKey,
    this.weekMinted = 0,
    Set<String>? goalsDone,
    Set<String>? goalsClaimed,
    this.goalsDay,
    this.lastStreakDay,
    this.streakLength = 0,
  }) : goalsDone = {...?goalsDone},
       goalsClaimed = {...?goalsClaimed};

  static const dailyCap = 85;
  static const weeklyCap = 280;
  static const maxGoalGemsPerDay = 35;

  /// Streak reward for day 1..7 of a run; day 8+ keeps paying the last step.
  static const streakLadder = <int>[10, 15, 20, 25, 30, 40, 50];

  String? dayKey;
  int dayMinted;
  String? weekKey;
  int weekMinted;

  String? goalsDay;
  final Set<String> goalsDone;
  final Set<String> goalsClaimed;

  /// Denver day of the last claimed streak day, and run length as of it.
  String? lastStreakDay;
  int streakLength;

  static String denverDay(DateTime utcNow) {
    final w = DenverTime.wallClock(utcNow.toUtc());
    return '${w.year}-${w.month.toString().padLeft(2, '0')}-'
        '${w.day.toString().padLeft(2, '0')}';
  }

  static String denverWeek(DateTime utcNow) =>
      DenverTime.weekStartUtc(utcNow.toUtc()).toIso8601String();

  static String _prevDay(String day) {
    final p = day.split('-').map(int.parse).toList();
    final d = DateTime.utc(p[0], p[1], p[2]).subtract(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  void _roll(DateTime utcNow) {
    final day = denverDay(utcNow);
    if (dayKey != day) {
      dayKey = day;
      dayMinted = 0;
    }
    final week = denverWeek(utcNow);
    if (weekKey != week) {
      weekKey = week;
      weekMinted = 0;
    }
    if (goalsDay != day) {
      goalsDay = day;
      goalsDone.clear();
      goalsClaimed.clear();
    }
  }

  /// Free gems that can still be minted right now.
  int remaining(DateTime utcNow) {
    _roll(utcNow);
    final d = dailyCap - dayMinted;
    final w = weeklyCap - weekMinted;
    final r = d < w ? d : w;
    return r < 0 ? 0 : r;
  }

  /// Reserve up to [gems] free gems; returns the clamped amount actually
  /// allowed (0 when the caps are spent). Caller credits the bank.
  int mint(int gems, DateTime utcNow) {
    if (gems <= 0) return 0;
    final room = remaining(utcNow);
    final take = gems < room ? gems : room;
    dayMinted += take;
    weekMinted += take;
    return take;
  }

  // ---- goals ----

  bool goalDone(DailyGoal g, DateTime utcNow) {
    _roll(utcNow);
    return goalsDone.contains(g.id);
  }

  bool goalClaimed(DailyGoal g, DateTime utcNow) {
    _roll(utcNow);
    return goalsClaimed.contains(g.id);
  }

  /// Mark a goal complete for today. Returns true if newly completed.
  bool completeGoal(DailyGoal g, DateTime utcNow) {
    _roll(utcNow);
    return goalsDone.add(g.id);
  }

  /// Claim a completed goal once per day. Returns gems (clamped) or null.
  int? claimGoal(DailyGoal g, DateTime utcNow) {
    _roll(utcNow);
    if (!goalsDone.contains(g.id) || goalsClaimed.contains(g.id)) return null;
    goalsClaimed.add(g.id);
    return mint(g.gems, utcNow);
  }

  // ---- streak ----

  /// Streak length the user would be on if they claimed today.
  int pendingStreakDay(DateTime utcNow) {
    final day = denverDay(utcNow);
    if (lastStreakDay == day) return streakLength;
    if (lastStreakDay != null && lastStreakDay == _prevDay(day)) {
      return streakLength + 1;
    }
    return 1;
  }

  /// Current run as displayed (0 once a day was missed).
  int currentStreak(DateTime utcNow) {
    final day = denverDay(utcNow);
    if (lastStreakDay == day || lastStreakDay == _prevDay(day)) {
      return streakLength;
    }
    return 0;
  }

  bool streakClaimedToday(DateTime utcNow) =>
      lastStreakDay == denverDay(utcNow);

  static int ladderGems(int streakDay) {
    if (streakDay <= 0) return 0;
    final i = streakDay > streakLadder.length ? streakLadder.length : streakDay;
    return streakLadder[i - 1];
  }

  /// Claim today's streak day (once per Denver day). Missing a day resets
  /// the run to day 1. Returns gems minted (clamped) or null if already
  /// claimed today.
  int? claimStreakDay(DateTime utcNow) {
    _roll(utcNow);
    if (streakClaimedToday(utcNow)) return null;
    final next = pendingStreakDay(utcNow);
    streakLength = next;
    lastStreakDay = denverDay(utcNow);
    return mint(ladderGems(next), utcNow);
  }

  // ---- persistence ----

  Map<String, Object?> toJson() => {
    'dayKey': dayKey,
    'dayMinted': dayMinted,
    'weekKey': weekKey,
    'weekMinted': weekMinted,
    'goalsDay': goalsDay,
    'goalsDone': goalsDone.toList(),
    'goalsClaimed': goalsClaimed.toList(),
    'lastStreakDay': lastStreakDay,
    'streakLength': streakLength,
  };

  static FreeMintLedger fromJson(Object? raw) {
    if (raw is! Map) return FreeMintLedger();
    String? s(String k) => raw[k] is String ? raw[k] as String : null;
    int n(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
    Set<String> set(String k) =>
        raw[k] is List ? (raw[k] as List).whereType<String>().toSet() : {};
    return FreeMintLedger(
      dayKey: s('dayKey'),
      dayMinted: n('dayMinted'),
      weekKey: s('weekKey'),
      weekMinted: n('weekMinted'),
      goalsDay: s('goalsDay'),
      goalsDone: set('goalsDone'),
      goalsClaimed: set('goalsClaimed'),
      lastStreakDay: s('lastStreakDay'),
      streakLength: n('streakLength'),
    );
  }

  FreeMintLedger copy() => fromJson(toJson());
}
