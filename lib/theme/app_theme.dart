import 'package:flutter/material.dart';

class _Palette {
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceGlass;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color buttonCore;
  final Color connected;
  final Color connectedCore;

  const _Palette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceGlass,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.buttonCore,
    required this.connected,
    required this.connectedCore,
  });
}

/// App colours. Values change at runtime with the user's theme choice
/// (Dark / Light / AMOLED + accent style), so read them in build methods.
class AppTheme {
  AppTheme._();

  static const _Palette _dark = _Palette(
    brightness: Brightness.dark,
    background: Color(0xFF070B14),
    surface: Color(0xFF111827),
    surfaceGlass: Color(0xFF1A2332),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF94A3B8),
    divider: Color(0x14FFFFFF),
    buttonCore: Color(0xFF1E2433),
    connected: Color(0xFF00E676),
    connectedCore: Color(0xFF0E2A22),
  );

  static const _Palette _amoled = _Palette(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF0B0B0F),
    surfaceGlass: Color(0xFF141419),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF9CA3AF),
    divider: Color(0x14FFFFFF),
    buttonCore: Color(0xFF15151B),
    connected: Color(0xFF00E676),
    connectedCore: Color(0xFF07201A),
  );

  static const _Palette _light = _Palette(
    brightness: Brightness.light,
    background: Color(0xFFF4F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceGlass: Color(0xFFE9EEF6),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    divider: Color(0x1A0F172A),
    buttonCore: Color(0xFFFFFFFF),
    connected: Color(0xFF059669),
    connectedCore: Color(0xFFD9F7EC),
  );

  /// Accent styles: (start, end) of the gradient.
  static const Map<String, (Color, Color)> accentStyles = <String, (Color, Color)>{
    'aurora': (Color(0xFF00E5FF), Color(0xFF7C3AED)),
    'emerald': (Color(0xFF10B981), Color(0xFF06B6D4)),
    'ocean': (Color(0xFF3B82F6), Color(0xFF6366F1)),
    'sunset': (Color(0xFFF97316), Color(0xFFEC4899)),
    'rose': (Color(0xFFF43F5E), Color(0xFFA855F7)),
    'gold': (Color(0xFFF59E0B), Color(0xFFEF4444)),
  };

  static _Palette _p = _dark;
  static (Color, Color) _accent = accentStyles['aurora']!;

  /// Applies a theme. [mode]: dark | light | amoled (system is resolved by the app).
  static void apply({required String mode, required String accent}) {
    _p = switch (mode) {
      'light' => _light,
      'amoled' => _amoled,
      _ => _dark,
    };
    _accent = accentStyles[accent] ?? accentStyles['aurora']!;
  }

  static Brightness get brightness => _p.brightness;
  static bool get isLight => _p.brightness == Brightness.light;

  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceGlass => _p.surfaceGlass;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get divider => _p.divider;
  static Color get buttonCore => _p.buttonCore;
  static Color get connected => _p.connected;
  static Color get connectedCore => _p.connectedCore;
  static Color get accentStart => _accent.$1;
  static Color get accentEnd => _accent.$2;
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);

  /// Text/icon colour to put on top of the accent gradient.
  static Color get onAccent => Colors.black;

  static ThemeData get current {
    final scheme = ColorScheme.fromSeed(
      seedColor: accentStart,
      brightness: brightness,
    ).copyWith(
      primary: accentStart,
      secondary: accentEnd,
      surface: surface,
      error: danger,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      dividerColor: divider,
      cardTheme: CardThemeData(
        color: surfaceGlass,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
        bodyMedium: TextStyle(color: textPrimary),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// Kept for older call sites.
  static ThemeData get dark => current;
}
