import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/hand_evaluator.dart';
import 'package:marge/engine/match_controller.dart';
import 'package:marge/engine/player.dart';
import 'package:marge/engine/turn_state.dart';
import 'package:marge/ui/widgets/payout_banner.dart';

PlayerState seat(String name, SeatKind kind) => PlayerState(
  profile: PlayerProfile(id: name, name: name, kind: kind),
  bankCents: 40,
);

void main() {
  for (final (winner, seated, text) in [
    (
      seat('You', SeatKind.human),
      2,
      'Your opponent ran out of gems. You win the pot!',
    ),
    (
      seat('You', SeatKind.human),
      3,
      'Everyone else is out of gems. You win the pot!',
    ),
    (
      seat('Rusty', SeatKind.bot),
      4,
      'Rusty wins the pot. Everyone else is out of gems.',
    ),
  ]) {
    testWidgets('last-standing banner: $text', (tester) async {
      final event = PayoutEvent(
        message: MatchController.lastStandingMessage(winner, seated: seated),
        kind: ScoreKind.tripleOnesPotWin,
        amountCents: 30,
        celebratory: true,
        seatIndex: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PayoutBanner(event: event)),
        ),
      );
      expect(find.text(text), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'cash|money|\$', caseSensitive: false)),
        findsNothing,
      );
    });
  }
}
