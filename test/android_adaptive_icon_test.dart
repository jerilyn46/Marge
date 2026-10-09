import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';

(int, int) _pngSize(String path) {
  final b = ByteData.sublistView(File(path).readAsBytesSync());
  return (b.getUint32(16), b.getUint32(20));
}

void main() {
  test('adaptive icon wired for API 26+, legacy icons kept', () {
    final xml = File('$_res/mipmap-anydpi-v26/ic_launcher.xml')
        .readAsStringSync();
    expect(xml, contains('<adaptive-icon'));
    expect(xml, contains('@mipmap/ic_launcher_background'));
    expect(xml, contains('@mipmap/ic_launcher_foreground'));
    // No monochrome layer was provided, so none is declared.
    expect(xml, isNot(contains('<monochrome')));
    const dens = {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };
    dens.forEach((d, px) {
      for (final layer in ['foreground', 'background']) {
        expect(_pngSize('$_res/mipmap-$d/ic_launcher_$layer.png'), (
          px,
          px,
        ), reason: '$d $layer');
      }
      expect(File('$_res/mipmap-$d/ic_launcher.png').existsSync(), isTrue);
    });
  });

  test('locked manifest/app id unchanged', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:allowBackup="false"'));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "com.jerilynroberts.marge"'));
  });
}
