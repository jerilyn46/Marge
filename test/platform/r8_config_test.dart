import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Proves the release shrink config is intentional, not accidental.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final rules = File('android/app/proguard-rules.pro').readAsStringSync();

  test('release build minifies with our proguard-rules.pro', () {
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('"proguard-rules.pro"'));
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
