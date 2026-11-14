import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

/// Holds the user's chosen app language. `null` = follow the phone's language.
class LocaleService {
  LocaleService._();
  static final LocaleService instance = LocaleService._();

  static const String _key = 'app_locale';

  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_key);
      if (code != null && L10n.codes.contains(code)) {
        locale.value = Locale(code);
      }
    } catch (_) {}
  }

  Future<void> set(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code == null || !L10n.codes.contains(code)) {
      await prefs.remove(_key);
      locale.value = null;
    } else {
      await prefs.setString(_key, code);
      locale.value = Locale(code);
    }
  }
}
