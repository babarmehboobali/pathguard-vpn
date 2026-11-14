import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Short troubleshooting FAQ (reduces 1-star "doesn't connect" reviews).
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const int _count = 5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(context.tr('help')), backgroundColor: AppTheme.surface),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _count,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final n = i + 1;
          return Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(Icons.help_outline_rounded, color: AppTheme.accentStart),
                title: Text(context.tr('faq_q$n'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('faq_a$n'),
                      style: TextStyle(color: AppTheme.textSecondary, height: 1.45)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
