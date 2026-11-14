import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';

/// Theme mode, accent style, home layout and haptics. Changes apply instantly.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeService.instance.revision,
      builder: (context, _, __) {
        final ts = ThemeService.instance;
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(title: Text(context.tr('appearance')), backgroundColor: AppTheme.surface),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _title(context.tr('theme_mode')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in ThemeService.modes)
                      ChoiceChip(
                        label: Text(context.tr('theme_$m')),
                        avatar: Icon(_modeIcon(m), size: 18),
                        selected: ts.mode == m,
                        onSelected: (_) => ts.update(mode: m),
                      ),
                  ],
                ),
              ),
              _title(context.tr('accent_color')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final a in ThemeService.accents) _swatch(context, a, ts.accent == a),
                  ],
                ),
              ),
              _title(context.tr('layout')),
              for (final l in ThemeService.layouts) _layoutTile(context, l, ts.layout == l),
              _title(context.tr('set_section_app')),
              SwitchListTile(
                secondary: const Icon(Icons.vibration_rounded),
                title: Text(context.tr('haptics')),
                value: ts.haptics,
                onChanged: (v) => ts.update(haptics: v),
              ),
            ],
          ),
        );
      },
    );
  }

  static IconData _modeIcon(String m) => switch (m) {
        'light' => Icons.light_mode_rounded,
        'dark' => Icons.dark_mode_rounded,
        'amoled' => Icons.contrast_rounded,
        _ => Icons.brightness_auto_rounded,
      };

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                color: AppTheme.accentStart,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );

  Widget _swatch(BuildContext context, String accent, bool selected) {
    final (a, b) = AppTheme.accentStyles[accent]!;
    return GestureDetector(
      onTap: () => ThemeService.instance.update(accent: accent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [a, b]),
              border: Border.all(
                color: selected ? AppTheme.textPrimary : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected ? Icon(Icons.check_rounded, color: AppTheme.onAccent) : null,
          ),
          const SizedBox(height: 4),
          Text(context.tr('accent_$accent'),
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _layoutTile(BuildContext context, String layout, bool selected) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppTheme.accentStart : AppTheme.divider,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Material(type: MaterialType.transparency, child: ListTile(
        leading: _LayoutPreview(layout: layout),
        title: Text(context.tr('layout_$layout'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(context.tr('layout_${layout}_sub'),
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: AppTheme.accentStart)
            : Icon(Icons.circle_outlined, color: AppTheme.textSecondary),
        onTap: () => ThemeService.instance.update(layout: layout),
      )),
    );
  }
}

/// Tiny drawing of each home layout.
class _LayoutPreview extends StatelessWidget {
  final String layout;
  const _LayoutPreview({required this.layout});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, {double h = 4}) => Container(
          width: w,
          height: h,
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            color: AppTheme.textSecondary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        );
    Widget circle(double d) => Container(
          width: d,
          height: d,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [AppTheme.accentStart, AppTheme.accentEnd]),
          ),
        );
    final children = switch (layout) {
      'compact' => [bar(26), bar(26, h: 6), circle(12), bar(22, h: 5), bar(26)],
      'minimal' => [const SizedBox(height: 6), circle(20), bar(14)],
      _ => [bar(26), bar(26, h: 6), circle(16), bar(26)],
    };
    return Container(
      width: 40,
      height: 56,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: children),
    );
  }
}
