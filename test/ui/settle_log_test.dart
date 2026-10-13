import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/debug/settle_log.dart';
import 'package:marge/ui/screens/settings_screen.dart';

void main() {
  test('kAppVersion matches pubspec', () {
    final v = RegExp(
      r'^version: (\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(kAppVersion, v);
  });

  test('ring buffer keeps the last ${SettleLog.capacity}, ids only', () {
    SettleLog.clear();
    for (var i = 0; i < SettleLog.capacity + 5; i++) {
      SettleLog.add('lock-set', serial: i, roll: 1, reason: 'x');
    }
    expect(SettleLog.entries.length, SettleLog.capacity);
    expect(SettleLog.entries.first.serial, 5);
    expect(
      SettleLog.entries.last.toString(),
      contains('lock-set throw=84 roll=1'),
    );
  });

  testWidgets('dialog lists breadcrumbs newest first', (tester) async {
    SettleLog.clear();
    SettleLog.add('lock-set', serial: 7, roll: 1, reason: 'a');
    SettleLog.add('watchdog-fired', serial: 7, roll: 1, reason: 'b');
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettleLogDialog())),
    );
    final texts = tester
        .widgetList<Text>(find.textContaining('throw=7'))
        .map((t) => t.data!)
        .toList();
    expect(texts.first, contains('watchdog-fired'));
    expect(texts.last, contains('lock-set'));
  });
}
