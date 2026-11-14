import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lightweight JSON-based localization (assets/l10n/<code>.json).
///
/// Usage: `context.tr('connect')` or `context.tr('stage_trying', {'country': 'Japan', 'i': 1, 'n': 5})`.
/// Missing keys fall back to English, then to the key itself, so a missing
/// translation can never crash the UI.
class L10n {
  L10n._(this.locale, this._strings, this._fallback);

  final Locale locale;
  final Map<String, String> _strings;
  final Map<String, String> _fallback;

  /// 20 languages, ordered by how they appear in the language picker.
  static const List<String> codes = <String>[
    'en', 'ar', 'ur', 'fa', 'tr', 'ru', 'id', 'hi', 'bn', 'es',
    'pt', 'fr', 'de', 'zh', 'vi', 'th', 'ko', 'ja', 'ms', 'it',
  ];

  /// Native names shown in the language picker.
  static const Map<String, String> nativeNames = <String, String>{
    'en': 'English',
    'ar': 'العربية',
    'ur': 'اردو',
    'fa': 'فارسی',
    'tr': 'Türkçe',
    'ru': 'Русский',
    'id': 'Bahasa Indonesia',
    'hi': 'हिन्दी',
    'bn': 'বাংলা',
    'es': 'Español',
    'pt': 'Português',
    'fr': 'Français',
    'de': 'Deutsch',
    'zh': '简体中文',
    'vi': 'Tiếng Việt',
    'th': 'ไทย',
    'ko': '한국어',
    'ja': '日本語',
    'ms': 'Bahasa Melayu',
    'it': 'Italiano',
  };

  static const Set<String> rtlCodes = <String>{'ar', 'ur', 'fa'};

  static List<Locale> get supportedLocales =>
      codes.map((c) => Locale(c)).toList(growable: false);

  static final L10n _empty = L10n._(const Locale('en'), const {}, const {});

  static L10n of(BuildContext context) =>
      Localizations.of<L10n>(context, L10n) ?? _empty;

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  bool get isRtl => rtlCodes.contains(locale.languageCode);

  String t(String key, [Map<String, Object?>? args]) {
    var value = _strings[key] ?? _fallback[key] ?? key;
    if (args != null && args.isNotEmpty) {
      args.forEach((name, v) {
        value = value.replaceAll('{$name}', '${v ?? ''}');
      });
    }
    return value;
  }

  /// Picks the best supported locale for the device.
  static Locale resolve(Locale? device) {
    if (device == null) return const Locale('en');
    if (codes.contains(device.languageCode)) return Locale(device.languageCode);
    // Common aliases
    switch (device.languageCode) {
      case 'in':
        return const Locale('id');
      case 'iw':
        return const Locale('en');
    }
    return const Locale('en');
  }
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  static final Map<String, Map<String, String>> _cache = <String, Map<String, String>>{};

  @override
  bool isSupported(Locale locale) => L10n.codes.contains(locale.languageCode);

  static Future<Map<String, String>> _loadCode(String code) async {
    final cached = _cache[code];
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString('assets/l10n/$code.json');
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final map = decoded.map((k, v) => MapEntry(k, '$v'));
      _cache[code] = map;
      return map;
    } catch (e) {
      debugPrint('L10n: failed to load $code: $e');
      return const <String, String>{};
    }
  }

  @override
  Future<L10n> load(Locale locale) async {
    final fallback = await _loadCode('en');
    final strings = locale.languageCode == 'en' ? fallback : await _loadCode(locale.languageCode);
    return L10n._(locale, strings, fallback);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<L10n> old) => false;
}

extension L10nContext on BuildContext {
  String tr(String key, [Map<String, Object?>? args]) => L10n.of(this).t(key, args);
}
