import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/coin_ledger.dart';
import 'package:marge/services/daily_gems_reminder.dart';
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

    test('reminder fires 9:00 Denver on the unlock day, not at midnight', () {
      expect(
        DailyGemsReminder.reminderAtUtc(DateTime.utc(2026, 10, 9, 6)),
        DateTime.utc(2026, 10, 9, 15),
      );
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
