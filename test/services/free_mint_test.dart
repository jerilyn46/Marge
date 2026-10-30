import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/free_mint.dart';

void main() {
  // Wed 2026-09-16 12:00 MDT.
  final wed = DateTime.utc(2026, 9, 16, 18);
  DateTime day(int offset) => wed.add(Duration(days: offset));

  group('free-mint caps', () {
    test('clamps at 85/day', () {
      final m = FreeMintLedger();
      expect(m.mint(60, wed), 60);
      expect(m.mint(60, wed), 25);
      expect(m.mint(10, wed), 0);
      expect(m.mint(10, day(1)), 10);
    });

    test('clamps at 280/week and resets on Denver Monday', () {
      final m = FreeMintLedger();
      // Wed..Sat: 85*3 = 255, Sun gets 25 more.
      for (var i = 0; i < 3; i++) {
        expect(m.mint(85, day(i)), 85);
      }
      expect(m.mint(85, day(3)), 25);
      expect(m.mint(85, day(4)), 0); // Sunday, week spent
      // Monday 2026-09-21 00:30 MDT = 06:30 UTC.
      expect(m.mint(85, DateTime.utc(2026, 9, 21, 6, 30)), 85);
      // Sunday 23:30 MDT is still the old week.
      final m2 = FreeMintLedger(
        weekKey: FreeMintLedger.denverWeek(day(4)),
        weekMinted: 280,
      );
      expect(m2.mint(5, DateTime.utc(2026, 9, 21, 5, 30)), 0);
    });
  });

  group('drip', () {
    test('drip counts inside caps and clamps under them', () {
      final l = PlayerCoinLedger();
      l.freeMint.mint(70, wed);
      expect(l.claimDailyDrip('You', utcNow: wed), 15);
      expect(l.availableHumanGems('You'), 115);
      expect(l.freeMint.remaining(wed), 0);
    });

    test('drip under cap grants full 25', () {
      final l = PlayerCoinLedger();
      expect(l.claimDailyDrip('You', utcNow: wed), 25);
      expect(l.freeMint.dayMinted, 25);
    });
  });

  group('goals', () {
    test('claim once per day, only after completion; 35/day max', () {
      final l = PlayerCoinLedger();
      expect(l.claimGoal('You', DailyGoal.finishMatch, utcNow: wed), isNull);
      l.completeGoal(DailyGoal.finishMatch, utcNow: wed);
      l.completeGoal(DailyGoal.bankScoringHand, utcNow: wed);
      expect(l.claimGoal('You', DailyGoal.finishMatch, utcNow: wed), 20);
      expect(l.claimGoal('You', DailyGoal.finishMatch, utcNow: wed), isNull);
      expect(l.claimGoal('You', DailyGoal.bankScoringHand, utcNow: wed), 15);
      expect(l.availableHumanGems('You'), 135);
      // Next day: goals reset to not-done.
      expect(l.claimGoal('You', DailyGoal.finishMatch, utcNow: day(1)), isNull);
      l.completeGoal(DailyGoal.finishMatch, utcNow: day(1));
      expect(l.claimGoal('You', DailyGoal.finishMatch, utcNow: day(1)), 20);
    });
  });

  group('streak', () {
    test('ladder 10..50, once per day, holds at 50', () {
      final s = FreeMintLedger();
      final rewards = [for (var i = 0; i < 8; i++) s.claimStreakDay(day(i))];
      expect(rewards, [10, 15, 20, 25, 30, 40, 50, 50]);
      expect(s.claimStreakDay(day(7)), isNull);
    });

    test('missing a day resets to day 1', () {
      final m = FreeMintLedger();
      expect(m.claimStreakDay(day(0)), 10);
      expect(m.claimStreakDay(day(1)), 15);
      expect(m.currentStreak(day(3)), 0);
      expect(m.claimStreakDay(day(3)), 10);
      expect(m.streakLength, 1);
    });

    test('streak clamps under the daily cap and persists', () {
      final l = PlayerCoinLedger();
      l.freeMint.mint(80, wed);
      expect(l.claimStreakDay('You', utcNow: wed), 5);
      final back = PlayerCoinLedger.decode(l.encode());
      expect(back.freeMint.streakLength, 1);
      expect(back.freeMint.remaining(wed), 0);
    });
  });
}
