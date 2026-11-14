import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathguard_vpn/theme/app_theme.dart';

void main() {
  test('palettes switch at runtime', () {
    AppTheme.apply(mode: 'light', accent: 'ocean');
    expect(AppTheme.isLight, true);
    expect(AppTheme.current.brightness, Brightness.light);
    expect(AppTheme.accentStart, AppTheme.accentStyles['ocean']!.$1);

    AppTheme.apply(mode: 'amoled', accent: 'gold');
    expect(AppTheme.background, const Color(0xFF000000));
    expect(AppTheme.isLight, false);

    AppTheme.apply(mode: 'dark', accent: 'unknown');
    expect(AppTheme.accentStart, AppTheme.accentStyles['aurora']!.$1);
  });
}
