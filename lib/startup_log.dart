import 'dart:io';

import 'package:flutter/foundation.dart';

/// Tiny cold-start trail written to the app files dir (and debugPrint).
///
/// If Flip 7 still dies before Dart `main`, this file will be missing —
/// evidence the crash is native (before Flutter), not lobby widgets.
/// Does not throw; never required for UI.
class StartupLog {
  StartupLog._();

  static const fileName = 'marge_startup.log';

  /// Rotate once the log reaches this size; one previous file is kept
  /// (`marge_startup.log.1`). Bounded at roughly 2 × [maxBytes] on disk.
  static const maxBytes = 64 * 1024;

  static Future<void> mark(String stage) async {
    final line = '${DateTime.now().toUtc().toIso8601String()} $stage';
    debugPrint('marge-startup: $line');
    if (kIsWeb) return;
    try {
      final dir = await _filesDir();
      if (dir == null) return;
      await appendCapped(File('${dir.path}/$fileName'), line);
    } catch (e) {
      debugPrint('marge-startup: write failed: $e');
    }
  }

  /// Append [line], rotating first if [file] is at or over [limit] bytes.
  @visibleForTesting
  static Future<void> appendCapped(
    File file,
    String line, {
    int limit = maxBytes,
  }) async {
    if (await file.exists() && await file.length() >= limit) {
      final old = File('${file.path}.1');
      if (await old.exists()) await old.delete();
      await file.rename(old.path);
    }
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  static Future<Directory?> _filesDir() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    const pkg = 'com.jerilynroberts.marge';
    final candidates = <String>[
      '/data/user/0/$pkg/files',
      '/data/data/$pkg/files',
    ];
    for (final path in candidates) {
      final dir = Directory(path);
      try {
        if (await dir.exists()) return dir;
      } catch (_) {}
    }
    for (final path in candidates) {
      try {
        final dir = Directory(path);
        await dir.create(recursive: true);
        return dir;
      } catch (_) {}
    }
    return null;
  }
}
