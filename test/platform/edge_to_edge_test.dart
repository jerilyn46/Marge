import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/ui/system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('applyEdgeToEdge requests SystemUiMode.edgeToEdge', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await applyEdgeToEdge();
    await Future<void>.delayed(Duration.zero);
    final mode = calls.where(
      (c) => c.method == 'SystemChrome.setEnabledSystemUIMode',
    );
    expect(mode, hasLength(1));
    expect(mode.single.arguments, 'SystemUiMode.edgeToEdge');
  });

  test('applyEdgeToEdge never throws when the platform fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          throw PlatformException(code: 'boom');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await expectLater(applyEdgeToEdge(), completes);
  });

  test('system bars are transparent with light icons', () {
    const s = kMargeSystemUiStyle;
    expect(s.statusBarColor, Colors.transparent);
    expect(s.systemNavigationBarColor, Colors.transparent);
    expect(s.systemNavigationBarDividerColor, Colors.transparent);
    expect(s.systemNavigationBarContrastEnforced, isFalse);
    expect(s.statusBarIconBrightness, Brightness.light);
    expect(s.systemNavigationBarIconBrightness, Brightness.light);
  });

  test('main.dart applies edge-to-edge only after runApp', () {
    final src = File('lib/main.dart').readAsStringSync();
    final run = src.indexOf('runApp(');
    final edge = src.indexOf('applyEdgeToEdge()');
    expect(run, greaterThan(0));
    expect(edge, greaterThan(run));
    expect(
      src.contains('SystemChrome.setEnabledSystemUIMode'),
      isFalse,
      reason: 'edge-to-edge goes through applyEdgeToEdge() only',
    );
  });

  for (final screen in [
    'friends',
    'more',
    'rules',
    'settings',
    'shop',
    'terms',
  ]) {
    test('$screen screen wraps its body in SafeArea(top: false)', () {
      final src = File('lib/ui/screens/${screen}_screen.dart')
          .readAsStringSync();
      expect(
        RegExp(r'SafeArea\(\s*top:\s*false').hasMatch(src),
        isTrue,
        reason: 'AppBar owns the top inset; SafeArea keeps sides/bottom',
      );
      expect(src.contains('appBar:'), isTrue);
    });
  }
}
