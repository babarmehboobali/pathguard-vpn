import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF070B14);
  static const Color surface = Color(0xFF111827);
  static const Color surfaceGlass = Color(0xFF1A2332);
  static const Color accentStart = Color(0xFF00E5FF);
  static const Color accentEnd = Color(0xFF7C3AED);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accentStart,
          secondary: accentEnd,
          surface: surface,
          background: background,
          error: danger,
        ),
        cardTheme: CardThemeData(
          color: surfaceGlass,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
          bodyMedium: TextStyle(color: textPrimary),
          titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        ),
      );
}
