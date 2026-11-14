import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final current = LocaleService.instance.locale.value?.languageCode;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(context.tr('language')), backgroundColor: AppTheme.surface),
      body: ListView(
        children: [
          RadioListTile<String?>(
            value: null,
            groupValue: current,
            title: Text(context.tr('language_system')),
            onChanged: (_) async {
              await LocaleService.instance.set(null);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          Divider(height: 1, color: AppTheme.divider),
          for (final code in L10n.codes)
            RadioListTile<String?>(
              value: code,
              groupValue: current,
              title: Text(L10n.nativeNames[code] ?? code),
              subtitle: Text(code.toUpperCase(),
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              onChanged: (_) async {
                await LocaleService.instance.set(code);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}
