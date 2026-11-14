import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String version = '1.0.5';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(context.tr('about')), backgroundColor: AppTheme.surface),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PathGuard VPN – Free Proxy',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(context.tr('version', {'v': version})),
            const SizedBox(height: 16),
            Text(context.tr('about_desc')),
            const SizedBox(height: 16),
            Text(context.tr('about_license')),
          ],
        ),
      ),
    );
  }
}
