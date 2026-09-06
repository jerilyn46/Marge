import 'package:flutter/material.dart';

/// Catalog id for a dice cosmetic skin.
enum DiceSkinId {
  classic,
  gold,
  neon,
  midnight,
  candy,
  luckyBones,
}

/// How a locked skin can be earned (shop purchase is always available too
/// except Classic which is free).
enum SkinUnlockRule {
  /// Always owned.
  free,

  /// Purchase only.
  shop,

  /// Unlock by winning the pot (triple ones first roll).
  potWin,

  /// Unlock by banking 3 scoring hands in one match.
  winThreeHands,

  /// Unlock by busting 3 times in one match.
  bustThreeTimes,
}

/// Visual pattern overlay on die faces.
enum DiceSkinPattern {
  none,
  stripes,
  sparkle,
  dots,
  bones,
}

/// Colors + pattern applied by [DieWidget].
@immutable
class DiceSkinTheme {
  const DiceSkinTheme({
    required this.face,
    required this.faceKept,
    required this.pip,
    required this.pipKept,
    required this.border,
    required this.borderKept,
    this.pattern = DiceSkinPattern.none,
    this.patternColor,
  });

  final Color face;
  final Color faceKept;
  final Color pip;
  final Color pipKept;
  final Color border;
  final Color borderKept;
  final DiceSkinPattern pattern;
  final Color? patternColor;
}

/// Static catalog entry for the shop / unlock UI.
@immutable
class DiceSkinDef {
  const DiceSkinDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.priceCents,
    required this.unlockRule,
    required this.unlockHint,
    required this.theme,
  });

  final DiceSkinId id;
  final String name;
  final String blurb;
  final int priceCents;
  final SkinUnlockRule unlockRule;
  final String unlockHint;
  final DiceSkinTheme theme;

  bool get isFree => unlockRule == SkinUnlockRule.free || priceCents <= 0;
}

/// Built-in skins (v1).
class DiceSkinCatalog {
  DiceSkinCatalog._();

  static const startingWalletCents = 200;
  static const potWinWalletBonus = 20;

  static const List<DiceSkinDef> all = [
    DiceSkinDef(
      id: DiceSkinId.classic,
      name: 'Classic',
      blurb: 'Cream faces with gold keep — the house default.',
      priceCents: 0,
      unlockRule: SkinUnlockRule.free,
      unlockHint: 'Owned from the start',
      theme: DiceSkinTheme(
        face: Color(0xFFFFF6E8),
        faceKept: Color(0xFFFFC857),
        pip: Color(0xFF222222),
        pipKept: Color(0xFF1B0F3B),
        border: Color(0x42000000),
        borderKept: Color(0xFFFF6B6B),
      ),
    ),
    DiceSkinDef(
      id: DiceSkinId.gold,
      name: 'Gold',
      blurb: 'Gilded faces for pot champions.',
      priceCents: 100,
      unlockRule: SkinUnlockRule.potWin,
      unlockHint: 'Win the pot (triple ones on first roll)',
      theme: DiceSkinTheme(
        face: Color(0xFFFFD700),
        faceKept: Color(0xFFFFF1A8),
        pip: Color(0xFF5C3B00),
        pipKept: Color(0xFF3D2400),
        border: Color(0xFFB8860B),
        borderKept: Color(0xFFFF8C00),
        pattern: DiceSkinPattern.sparkle,
        patternColor: Color(0x66FFFFFF),
      ),
    ),
    DiceSkinDef(
      id: DiceSkinId.neon,
      name: 'Neon',
      blurb: 'Electric cyan glow for hot streaks.',
      priceCents: 120,
      unlockRule: SkinUnlockRule.winThreeHands,
      unlockHint: 'Bank 3 scoring hands in one match',
      theme: DiceSkinTheme(
        face: Color(0xFF0A1628),
        faceKept: Color(0xFF1A0A2E),
        pip: Color(0xFF39FF14),
        pipKept: Color(0xFFFF00E5),
        border: Color(0xFF00F5FF),
        borderKept: Color(0xFFFF00E5),
        pattern: DiceSkinPattern.stripes,
        patternColor: Color(0x3300F5FF),
      ),
    ),
    DiceSkinDef(
      id: DiceSkinId.midnight,
      name: 'Midnight',
      blurb: 'Deep navy with silver pips.',
      priceCents: 50,
      unlockRule: SkinUnlockRule.shop,
      unlockHint: 'Buy in the Dice shop',
      theme: DiceSkinTheme(
        face: Color(0xFF1A2744),
        faceKept: Color(0xFF2C3E6B),
        pip: Color(0xFFE8EEF8),
        pipKept: Color(0xFFFFC857),
        border: Color(0xFF4A6FA5),
        borderKept: Color(0xFF7EB6FF),
        pattern: DiceSkinPattern.dots,
        patternColor: Color(0x22FFFFFF),
      ),
    ),
    DiceSkinDef(
      id: DiceSkinId.candy,
      name: 'Candy',
      blurb: 'Bubblegum pink with mint keep.',
      priceCents: 75,
      unlockRule: SkinUnlockRule.shop,
      unlockHint: 'Buy in the Dice shop',
      theme: DiceSkinTheme(
        face: Color(0xFFFFB7C5),
        faceKept: Color(0xFFB5F5D8),
        pip: Color(0xFFC2185B),
        pipKept: Color(0xFF00695C),
        border: Color(0xFFFF80AB),
        borderKept: Color(0xFF69F0AE),
        pattern: DiceSkinPattern.dots,
        patternColor: Color(0x33FFFFFF),
      ),
    ),
    DiceSkinDef(
      id: DiceSkinId.luckyBones,
      name: 'Lucky Bones',
      blurb: 'Bone-white dice for survivors of the bust.',
      priceCents: 150,
      unlockRule: SkinUnlockRule.bustThreeTimes,
      unlockHint: 'Bust 3 times in one match',
      theme: DiceSkinTheme(
        face: Color(0xFFF5F0E6),
        faceKept: Color(0xFFE8D5B7),
        pip: Color(0xFF2B2B2B),
        pipKept: Color(0xFF5D4037),
        border: Color(0xFF9E9E9E),
        borderKept: Color(0xFF795548),
        pattern: DiceSkinPattern.bones,
        patternColor: Color(0x332B2B2B),
      ),
    ),
  ];

  static DiceSkinDef byId(DiceSkinId id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.first);

  static DiceSkinDef? tryParse(String raw) {
    for (final s in all) {
      if (s.id.name == raw) return s;
    }
    return null;
  }
}
