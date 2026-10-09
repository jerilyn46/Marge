import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/startup_log.dart';

/// Tester 9: the startup log is capped (rotate at ~64 KB, keep 1 old file).
void main() {
  test('rotates at the cap and keeps exactly one previous file', () async {
    final dir = await Directory.systemTemp.createTemp('marge_log');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/${StartupLog.fileName}');
    const limit = 200;
    for (var i = 0; i < 100; i++) {
      await StartupLog.appendCapped(file, 'line $i ${'x' * 20}', limit: limit);
    }
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, {StartupLog.fileName, '${StartupLog.fileName}.1'});
    expect(await file.length(), lessThan(limit + 64));
    expect(
      await File('${file.path}.1').length(),
      lessThan(limit + 64),
    );
    expect(await file.readAsString(), contains('line 99'));
  });

  test('default cap is about 64 KB', () {
    expect(StartupLog.maxBytes, 64 * 1024);
  });
}
