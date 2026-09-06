import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lightweight SFX / haptics stubs — no asset pack required.
/// Calls are safe no-ops when audio is unavailable (CI / linux headless).
class SfxService {
  SfxService({this.sfxEnabled = true, this.hapticsEnabled = true});

  bool sfxEnabled;
  bool hapticsEnabled;

  Future<void> roll() async {
    if (!sfxEnabled) return;
    debugPrint('[sfx] roll');
    await _haptic(HapticFeedback.lightImpact);
  }

  Future<void> bank() async {
    if (!sfxEnabled) return;
    debugPrint('[sfx] bank');
    await _haptic(HapticFeedback.mediumImpact);
  }

  Future<void> potWin() async {
    if (!sfxEnabled) return;
    debugPrint('[sfx] pot-win stinger');
    await _haptic(HapticFeedback.heavyImpact);
  }

  Future<void> bust() async {
    if (!sfxEnabled) return;
    debugPrint('[sfx] bust');
    await _haptic(HapticFeedback.selectionClick);
  }

  Future<void> _haptic(Future<void> Function() fn) async {
    if (!hapticsEnabled) return;
    try {
      await fn();
    } catch (_) {
      // Haptics unsupported on linux/web — fine.
    }
  }
}
