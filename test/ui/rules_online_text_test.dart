import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/online/online_flags.dart';
import 'package:marge/ui/screens/rules_screen.dart';

void main() {
  testWidgets('Rules: no stale "online coming soon" sentence', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: RulesScreen())),
    );
    await tester.pump();
    final card = find.textContaining('pass the device');
    await tester.scrollUntilVisible(card, 200);
    expect(card, findsOneWidget);
    expect(
      find.textContaining('coming soon', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('share the room code'),
      kOnlineInviteEnabled ? findsOneWidget : findsNothing,
    );
  });
}
