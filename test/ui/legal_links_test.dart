import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/settings_service.dart';
import 'package:marge/ui/legal_links.dart';
import 'package:marge/ui/screens/settings_screen.dart';
import 'package:marge/ui/screens/terms_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('privacy URL and support contact match the published policy', () {
    expect(
      LegalLinks.privacyPolicyUrl,
      'https://jerilyn46.github.io/Marge/privacy-policy/',
    );
    expect(LegalLinks.supportMailUri.scheme, 'mailto');
    expect(LegalLinks.supportMailUri.path, LegalLinks.supportEmail);
  });

  test('bundled Terms asset is non-empty, gems-only, no cash framing', () {
    final text = File(TermsScreen.assetPath).readAsStringSync();
    expect(text, contains('Terms of Use'));
    expect(text, contains('no cash value'));
    expect(text.toLowerCase(), isNot(contains('chips')));
  });

  testWidgets('Settings lists Privacy policy, Terms, and Contact support', (
    tester,
  ) async {
    SettingsNotifier.bootstrap = const GameSettings(
      playerName: 'You',
      hasUsername: true,
      loaded: true,
    );
    addTearDown(() => SettingsNotifier.bootstrap = null);
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text(LegalLinks.supportEmail), findsOneWidget);
    expect(find.textContaining('chips'), findsNothing);
  });
}
