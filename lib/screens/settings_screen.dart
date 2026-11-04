import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';
import '../services/crash_service.dart';
import 'split_tunnel_screen.dart';
import 'about_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  bool _autoConnect = false;
  bool _preferUdp = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _autoConnect = await _settings.getAutoConnect();
    _preferUdp = await _settings.getPreferUdp();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Settings'), backgroundColor: AppTheme.surface),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Auto-connect'),
            value: _autoConnect,
            onChanged: (v) async {
              await _settings.setAutoConnect(v);
              setState(() => _autoConnect = v);
            },
          ),
          SwitchListTile(
            title: const Text('Prefer UDP'),
            value: _preferUdp,
            onChanged: (v) async {
              await _settings.setPreferUdp(v);
              setState(() => _preferUdp = v);
            },
          ),
          ListTile(
            title: const Text('Exclude apps'),
            subtitle: const Text('Exclude banking apps so they use your normal connection'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SplitTunnelScreen()),
            ),
          ),
          ListTile(
            title: const Text('Diagnostics log'),
            onTap: () async {
              final log = await CrashService.instance.readLog();
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Diagnostics'),
                  content: SingleChildScrollView(child: Text(log.isEmpty ? 'No log' : log)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                  ],
                ),
              );
            },
          ),
          ListTile(
            title: const Text('About'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
