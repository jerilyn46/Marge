import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ui/screens/terms_screen.dart';

class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

String _visibleText(WidgetTester tester) {
  final buf = StringBuffer();
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    buf.writeln(w.text.toPlainText());
  }
  return buf.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const legalFile = '/workspace/marge-growth/terms-of-use.md';

  test('bundled asset is Legal\'s final file byte for byte', () {
    final asset = File(TermsScreen.assetPath).readAsBytesSync();
    final legal = File(legalFile);
    if (!legal.existsSync()) {
      markTestSkipped('Legal source not on this machine');
      return;
    }
    expect(asset, legal.readAsBytesSync());
    final text = String.fromCharCodes(asset);
    expect(text, contains(TermsScreen.effectiveDateToken));
  });

  test('render fills the date, or drops the line when no date (fail closed)',
      () {
    final raw = File(TermsScreen.assetPath).readAsStringSync();
    final filled = TermsScreen.render(raw, effectiveDate: 'October 12, 2026');
    expect(filled, contains('Effective date: October 12, 2026'));
    expect(filled, isNot(contains('{{')));

    final none = TermsScreen.render(raw, effectiveDate: '');
    expect(none, isNot(contains('{{')));
    expect(none, isNot(contains('Effective date')));
    expect(none, contains('Terms of Use'));
  });

  testWidgets('rendered Terms (date set) have no {{, [, or DRAFT', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TermsScreen(
          bundle: _FileBundle(),
          effectiveDate: 'October 12, 2026',
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 50),
        ));
    await tester.pumpAndSettle();
    final text = _visibleText(tester);
    expect(text, contains('Effective date: October 12, 2026'));
    expect(text, contains('Virtual gems only'));
    expect(text, isNot(contains('{{')));
    expect(text, isNot(contains('[')));
    expect(text, isNot(contains('DRAFT')));
    expect(text.toLowerCase(), isNot(contains('chips')));
  });
}
