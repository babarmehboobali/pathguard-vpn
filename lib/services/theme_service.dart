import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Look & feel chosen by the user: theme mode, accent style, home layout, haptics.
class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const List<String> modes = <String>['system', 'dark', 'light', 'amoled'];
  static const List<String> accents = <String>['aurora', 'emerald', 'ocean', 'sunset', 'rose', 'gold'];
  static const List<String> layouts = <String>['classic', 'compact', 'minimal'];

  String mode = 'dark';
  String accent = 'aurora';
  String layout = 'classic';
  bool haptics = true;

  /// Bumped on every change; the app rebuilds when it changes.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      mode = _pick(p.getString('ui_mode'), modes, 'dark');
      accent = _pick(p.getString('ui_accent'), accents, 'aurora');
      layout = _pick(p.getString('ui_layout'), layouts, 'classic');
      haptics = p.getBool('ui_haptics') ?? true;
    } catch (_) {}
  }

  static String _pick(String? v, List<String> allowed, String fallback) =>
      (v != null && allowed.contains(v)) ? v : fallback;

  Future<void> update({String? mode, String? accent, String? layout, bool? haptics}) async {
    final p = await SharedPreferences.getInstance();
    if (mode != null && modes.contains(mode)) {
      this.mode = mode;
      await p.setString('ui_mode', mode);
    }
    if (accent != null && accents.contains(accent)) {
      this.accent = accent;
      await p.setString('ui_accent', accent);
    }
    if (layout != null && layouts.contains(layout)) {
      this.layout = layout;
      await p.setString('ui_layout', layout);
    }
    if (haptics != null) {
      this.haptics = haptics;
      await p.setBool('ui_haptics', haptics);
    }
    revision.value++;
  }
}
