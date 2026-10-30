import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release R8 is intentionally off (Flip 7); keep rules stay for re-enable.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final rules = File('android/app/proguard-rules.pro').readAsStringSync();

  // R8 is off for release: it broke Flip 7 cold start (591adf1 / PR #26).
  test('release build has R8 minify and resource shrink off', () {
    expect(gradle, contains('isMinifyEnabled = false'));
    expect(gradle, contains('isShrinkResources = false'));
    expect(gradle, isNot(contains('isMinifyEnabled = true')));
    expect(gradle, isNot(contains('isShrinkResources = true')));
  });

  test('kotlinx.coroutines ServiceLoader classes keep their names', () {
    // META-INF/services entries name these; renaming breaks Dispatchers.Main.
    expect(
      rules,
      contains(
        '-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory',
      ),
    );
    expect(
      rules,
      contains('-keepnames class kotlinx.coroutines.CoroutineExceptionHandler'),
    );
    expect(
      rules,
      contains('implements kotlinx.coroutines.internal.MainDispatcherFactory'),
    );
    expect(
      rules,
      contains('kotlinx.coroutines.android.AndroidDispatcherFactory'),
    );
  });

  test('plugins reached by reflection are kept', () {
    for (final pkg in [
      'io.flutter.**',
      'com.google.android.gms.ads.**',
      'com.google.android.ump.**',
      'com.android.billingclient.**',
      'com.dexterous.**',
      'xyz.luan.audioplayers.**',
      'com.jerilynroberts.marge.**',
    ]) {
      expect(rules, contains('-keep class $pkg'), reason: pkg);
    }
  });
}
