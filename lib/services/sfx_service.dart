import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sound cues named in the Designer spec. No audio assets have been
/// delivered yet, so every cue is a no-op hook ([SfxService.play]); wire a
/// player here once the files exist. Do not invent audio.
enum SfxCue {
  gemTink,
  tierSwell,
  bankChime,
  gemChimeCascade,
  cupRattle,
  dieClack,
}

/// Lightweight SFX / haptics. Sound hooks are gated by [sfxEnabled];
/// haptics are gated by [hapticsEnabled] on their own.
/// Calls are safe no-ops when audio/haptics are unavailable (CI, linux).
class SfxService {
  SfxService({this.sfxEnabled = true, this.hapticsEnabled = true});

  bool sfxEnabled;
  bool hapticsEnabled;

  /// Optional observer for tests (cue name each time a hook would play).
  @visibleForTesting
  void Function(SfxCue cue)? debugOnCue;

  /// Sound hook: no-op until assets exist.
  void play(SfxCue cue) {
    if (!sfxEnabled) return;
    debugOnCue?.call(cue);
  }

  Future<void> roll() async {
    if (sfxEnabled) debugPrint('[sfx] roll');
    await _haptic(HapticFeedback.lightImpact);
  }

  Future<void> bank() async {
    if (sfxEnabled) debugPrint('[sfx] bank');
    await _haptic(HapticFeedback.mediumImpact);
  }

  Future<void> potWin() async {
    if (sfxEnabled) debugPrint('[sfx] pot-win stinger');
    await _haptic(HapticFeedback.heavyImpact);
  }

  Future<void> bust() async {
    if (sfxEnabled) debugPrint('[sfx] bust');
    await _haptic(HapticFeedback.selectionClick);
  }

  // --- Pot of gems ---------------------------------------------------------

  /// One gem landed in the bowl (sound only; the spec caps ~8 per drop).
  void gemLanded() => play(SfxCue.gemTink);

  /// A drop group started: one light tap for the whole group.
  void potDropStarted() => _hapticFire(HapticFeedback.lightImpact);

  /// The pot reached a new fill tier.
  void potTierUp() {
    play(SfxCue.tierSwell);
    _hapticFire(HapticFeedback.mediumImpact);
  }

  // --- Bank button ---------------------------------------------------------

  /// Bank button entered: light tap + short bright chime.
  void bankEntered() {
    play(SfxCue.bankChime);
    _hapticFire(HapticFeedback.lightImpact);
  }

  /// Bank tapped: medium tap + glassy chime cascade with the particles.
  void bankTapped() {
    play(SfxCue.gemChimeCascade);
    _hapticFire(HapticFeedback.mediumImpact);
  }

  // --- 3D dice -------------------------------------------------------------

  /// Throw start: soft cup rattle hook. The throw's lightImpact comes from
  /// [roll] (fired by the match when the roll is made), so no second tap.
  void diceThrown() => play(SfxCue.cupRattle);

  /// One die landed: felt clack hook + selectionClick (max 3 per roll).
  void dieLanded() {
    play(SfxCue.dieClack);
    _hapticFire(HapticFeedback.selectionClick);
  }

  /// Fire-and-forget haptic for animation beats (never blocks a frame).
  void _hapticFire(Future<void> Function() fn) {
    if (!hapticsEnabled) return;
    _haptic(fn);
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
