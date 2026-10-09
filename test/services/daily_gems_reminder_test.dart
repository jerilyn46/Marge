import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/widgets/daily_gems_ready_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UAT #5: free-gems-ready alert on the existing daily-drip clock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('next drip time uses the existing Denver-day clock', () {
    test('null while the drip can be claimed', () {
      final ledger = PlayerCoinLedger();
      expect(
        ledger.nextDailyDripUtc(utcNow: DateTime.utc(2026, 10, 8, 18)),
        isNull,
      );
    });

    test('after a claim: next Denver midnight (MDT = 06:00 UTC)', () {
      final ledger = PlayerCoinLedger();
      final now = DateTime.utc(2026, 10, 8, 18); // 12:00 MDT Oct 8
      ledger.claimDailyDrip('You', utcNow: now);
      expect(ledger.nextDailyDripUtc(utcNow: now), DateTime.utc(2026, 10, 9, 6));
    });

    test('across the November DST change (MST = 07:00 UTC)', () {
      final ledger = PlayerCoinLedger();
      final now = DateTime.utc(2026, 11, 10, 18);
      ledger.claimDailyDrip('You', utcNow: now);
      expect(
        ledger.nextDailyDripUtc(utcNow: now),
        DateTime.utc(2026, 11, 11, 7),
      );
    });

    test('reminder fires exactly 24 h after the claim', () {
      final ledger = PlayerCoinLedger();
      final claim = DateTime.utc(2026, 10, 8, 18, 7); // 12:07 MDT
      ledger.claimDailyDrip('You', utcNow: claim);
      expect(
        ledger.dailyGemsReminderUtc(utcNow: claim),
        claim.add(const Duration(hours: 24)),
      );
      // Never before the drip unlocks (Denver midnight).
      expect(
        ledger
            .dailyGemsReminderUtc(utcNow: claim)!
            .isBefore(ledger.nextDailyDripUtc(utcNow: claim)!),
        isFalse,
      );
    });

    test('late-night claim: 24 h later is after unlock, also across DST', () {
      final ledger = PlayerCoinLedger();
      // 23:50 MDT Oct 31 → fall back Nov 1; 24 h later is still Nov 1/2 wall.
      final claim = DateTime.utc(2026, 11, 1, 5, 50);
      ledger.claimDailyDrip('You', utcNow: claim);
      final fire = ledger.dailyGemsReminderUtc(utcNow: claim)!;
      expect(fire, claim.add(const Duration(hours: 24)));
      expect(ledger.canClaimDailyDrip(utcNow: fire), isTrue);
    });

    test('no reminder while claimable, or when the claim time is unknown', () {
      final ledger = PlayerCoinLedger();
      final now = DateTime.utc(2026, 10, 8, 18);
      expect(ledger.dailyGemsReminderUtc(utcNow: now), isNull);
      // Legacy data: day stamp only, no instant → do not guess.
      final legacy = PlayerCoinLedger(
        lastDailyDripDay: PlayerCoinLedger.denverDayKey(now),
      );
      expect(legacy.dailyGemsReminderUtc(utcNow: now), isNull);
    });

    test('claim instant survives encode/decode', () {
      final ledger = PlayerCoinLedger();
      final claim = DateTime.utc(2026, 10, 8, 18, 7);
      ledger.claimDailyDrip('You', utcNow: claim);
      final back = PlayerCoinLedger.decode(ledger.encode());
      expect(back.lastDailyDripAtUtc, claim);
    });
  });

  testWidgets('Home prompt shows once per day when gems are ready', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    PlayerCoinLedger.bootstrap = PlayerCoinLedger(
      balances: {'human:You': 10},
      loaded: true,
      prefs: prefs,
    );
    SettingsNotifier.bootstrap = const GameSettings(
      playerName: 'You',
      hasUsername: true,
      loaded: true,
    );
    DailyGemsReadyPrompt.promptedDay = null;
    addTearDown(() {
      PlayerCoinLedger.bootstrap = null;
      SettingsNotifier.bootstrap = null;
      DailyGemsReadyPrompt.promptedDay = null;
    });

    Widget app() => const ProviderScope(
      child: MaterialApp(
        home: DailyGemsReadyPrompt(child: Scaffold(body: Text('home'))),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.textContaining('free daily gems are ready'), findsOneWidget);

    // Rebuilding Home the same day does not nag again.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.textContaining('free daily gems are ready'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
