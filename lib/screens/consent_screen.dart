import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/consent_service.dart';

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
              const Text(
                'PathGuard VPN Disclosure',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    'This app uses Android VpnService to create an encrypted tunnel for all device traffic. This is its core function.\n\n'
                    'Traffic is routed through third-party volunteer servers (VPN Gate, University of Tsukuba) or the Tor network, or Cloudflare WARP if Fast mode is enabled. Those operators may log connection metadata. Use HTTPS for sensitive data.\n\n'
                    'PathGuard does not collect, log, or sell browsing data, DNS queries, or traffic contents.\n\n'
                    'Ads are shown by Google AdMob. Ad requests are not modified or redirected for monetization.',
                    style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary, height: 1.5),
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
                      child: const Text('Decline'),
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
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text('I Agree'),
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
