import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';
import '../services/vpn_channel.dart';

class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  final SettingsService _settings = SettingsService();
  final VpnChannel _channel = VpnChannel();
  List<Map<String, String>> _apps = [];
  List<String> _excluded = [];
  List<Map<String, String>> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _excluded = await _settings.getSplitExclude();
    _apps = await _channel.listInstalledApps();
    _filtered = _apps;
    if (mounted) setState(() => _loading = false);
  }

  void _filter(String q) {
    setState(() {
      _filtered = _apps
          .where((a) =>
              (a['label'] ?? '').toLowerCase().contains(q.toLowerCase()) ||
              (a['package'] ?? '').toLowerCase().contains(q.toLowerCase()))
          .toList();
    });
  }

  Future<void> _toggle(String pkg) async {
    if (_excluded.contains(pkg)) {
      _excluded.remove(pkg);
    } else {
      _excluded.add(pkg);
    }
    await _settings.setSplitExclude(_excluded);
    await _channel.setSplitTunnel(_excluded);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Exclude apps'), backgroundColor: AppTheme.surface),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Exclude banking apps so they use your normal connection',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search apps',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
              ),
              onChanged: _filter,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final app = _filtered[i];
                      final pkg = app['package'] ?? '';
                      return CheckboxListTile(
                        title: Text(app['label'] ?? pkg),
                        subtitle: Text(pkg, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        value: _excluded.contains(pkg),
                        onChanged: (_) => _toggle(pkg),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
