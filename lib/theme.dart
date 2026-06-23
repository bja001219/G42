import 'package:flutter/material.dart';

/// G42 공용 다크 테마.
ThemeData g42Theme() {
  const seed = Color(0xFF6C5CE7);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0E0F1A),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A1B2E),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1B2E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

/// 자주 쓰는 색상 모음.
abstract class G42Colors {
  static const bg = Color(0xFF0E0F1A);
  static const surface = Color(0xFF1A1B2E);
  static const surfaceHi = Color(0xFF24263F);
  static const accent = Color(0xFF6C5CE7);
  static const good = Color(0xFF26DE81);
  static const bad = Color(0xFFFF6B6B);
  static const warn = Color(0xFFFECA57);
}
