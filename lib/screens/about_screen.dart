import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('About'), backgroundColor: AppTheme.surface),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PathGuard VPN – Free Proxy', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Version 1.0.0'),
            SizedBox(height: 16),
            Text('A free, open-source VPN client using VPN Gate, Tor, and optional WARP.'),
            SizedBox(height: 16),
            Text('Licensed under GPL-3.0. See NOTICE.md for component credits.'),
          ],
        ),
      ),
    );
  }
}
