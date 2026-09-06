import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MargeColors {
  static const velvet = Color(0xFF1B0F3B);
  static const felt = Color(0xFF0D5C3D);
  static const feltLight = Color(0xFF14915A);
  static const gold = Color(0xFFFFC857);
  static const coral = Color(0xFFFF6B6B);
  static const sky = Color(0xFF4CC9F0);
  static const lilac = Color(0xFFB5179E);
  static const cream = Color(0xFFFFF6E8);
  static const chipRed = Color(0xFFE63946);
  static const chipBlue = Color(0xFF457B9D);
}

ThemeData buildMargeTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MargeColors.lilac,
      brightness: Brightness.dark,
      primary: MargeColors.gold,
      secondary: MargeColors.sky,
      surface: MargeColors.velvet,
    ),
  );

  TextTheme textTheme;
  try {
    textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: MargeColors.cream,
      displayColor: MargeColors.cream,
    );
  } catch (_) {
    textTheme = base.textTheme.apply(
      bodyColor: MargeColors.cream,
      displayColor: MargeColors.cream,
    );
  }

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
      color: MargeColors.felt.withValues(alpha: 0.85),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
    ),
  );
}
