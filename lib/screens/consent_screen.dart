import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/consent_service.dart';
import '../l10n/l10n.dart';
import 'language_screen.dart';

class ConsentScreen extends StatelessWidget {
  final VoidCallback onAccepted;
  final VoidCallback onDeclined;

  const ConsentScreen({super.key, required this.onAccepted, required this.onDeclined});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('consent_title'),
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('language'),
                    icon: Icon(Icons.translate_rounded, color: AppTheme.textPrimary),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LanguageScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    context.tr('consent_body'),
                    style: TextStyle(fontSize: 16, color: AppTheme.textSecondary, height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDeclined,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: const BorderSide(color: AppTheme.danger),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text(context.tr('decline')),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await ConsentService().acceptVpnConsent();
                        onAccepted();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentStart,
                        foregroundColor: AppTheme.onAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text(context.tr('agree')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
