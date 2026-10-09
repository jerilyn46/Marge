import 'package:flutter/material.dart';

/// Warm evening table — soft felt, wood edge, gentle lamp light.
/// Not casino neon. Gems read as playful chips, never cash.
class MargeColors {
  static const velvet = Color(0xFF1C1510); // warm night (legacy name)
  static const night = velvet;
  static const felt = Color(0xFF1F4D3A);
  static const feltLight = Color(0xFF2E6B50);
  static const wood = Color(0xFF6B4423);
  static const woodEdge = Color(0xFF8B5E3C);
  static const lamp = Color(0xFFFFE2B8);
  static const gold = Color(0xFFE8C17A); // soft amber chip
  static const coral = Color(0xFFE07A6A);
  static const sky = Color(0xFF7EB8C9);
  static const lilac = Color(0xFF9B6B8A);
  static const cream = Color(0xFFFFF4E6);
  static const chipRed = Color(0xFFC75B5B);
  static const chipBlue = Color(0xFF5A7E92);
}

ThemeData buildMargeTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MargeColors.felt,
      brightness: Brightness.dark,
      primary: MargeColors.gold,
      secondary: MargeColors.woodEdge,
      surface: MargeColors.velvet,
    ),
  );

  // Nunito is not bundled. GoogleFonts.nunitoTextTheme() schedules a network
  // fetch that can throw before the first frame on some devices (Flip 7 cold
  // start). Use the Material text theme as a synchronous fallback. Runtime
  // fetching is also disabled in main() so a later GoogleFonts call cannot
  // hit the network.
  final textTheme = base.textTheme.apply(
    bodyColor: MargeColors.cream,
    displayColor: MargeColors.cream,
  );

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: MargeColors.velvet,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MargeColors.gold,
        foregroundColor: MargeColors.velvet,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MargeColors.coral,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    cardTheme: CardThemeData(
      color: MargeColors.felt.withValues(alpha: 0.88),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: MargeColors.woodEdge.withValues(alpha: 0.35)),
      ),
      elevation: 3,
    ),
  );
}
