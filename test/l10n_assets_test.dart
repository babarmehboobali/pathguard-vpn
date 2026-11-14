import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pathguard_vpn/l10n/l10n.dart';

void main() {
  test('every language has every English key and the same placeholders', () {
    Map<String, dynamic> load(String c) =>
        jsonDecode(File('assets/l10n/$c.json').readAsStringSync()) as Map<String, dynamic>;
    final en = load('en');
    final ph = RegExp(r'\{[a-z]+\}');
    for (final code in L10n.codes) {
      final m = load(code);
      expect(m.keys.toSet(), en.keys.toSet(), reason: code);
      for (final k in en.keys) {
        final a = ph.allMatches('${en[k]}').map((e) => e.group(0)).toList()..sort();
        final b = ph.allMatches('${m[k]}').map((e) => e.group(0)).toList()..sort();
        expect(b, a, reason: '$code/$k');
      }
    }
  });
}
