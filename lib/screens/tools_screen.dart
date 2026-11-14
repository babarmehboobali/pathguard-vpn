import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/server.dart';
import '../services/ads_service.dart';
import '../services/imported_servers_service.dart';
import '../services/net_tools_service.dart';
import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../utils/flag.dart';
import '../widgets/banner_ad_widget.dart';
import 'history_screen.dart';

/// Tools: My IP & location, speed test, data usage, imported .ovpn servers.
/// Pops with a [Server] when the user taps Connect on an imported server.
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  final NetToolsService _net = NetToolsService.instance;

  bool _ipLoading = false;
  IpInfo? _ip;
  bool _ipFailed = false;

  bool _speedRunning = false;
  String _speedStage = '';
  SpeedResult? _speed;
  bool _speedFailed = false;

  ({int bytes, int sessions})? _today;
  ({int bytes, int sessions})? _week;
  ({int bytes, int sessions})? _month;

  List<Server> _imported = <Server>[];

  @override
  void initState() {
    super.initState();
    _checkIp();
    _loadUsage();
    _loadImported();
  }

  Future<void> _checkIp() async {
    setState(() {
      _ipLoading = true;
      _ipFailed = false;
    });
    final info = await _net.checkIp();
    if (!mounted) return;
    setState(() {
      _ipLoading = false;
      _ip = info;
      _ipFailed = info == null;
    });
  }

  Future<void> _loadUsage() async {
    final u = UsageService.instance;
    final t = await u.lastDays(1);
    final w = await u.lastDays(7);
    final m = await u.lastDays(30);
    if (!mounted) return;
    setState(() {
      _today = t;
      _week = w;
      _month = m;
    });
  }

  Future<void> _loadImported() async {
    final list = await ImportedServersService.instance.list();
    if (mounted) setState(() => _imported = list);
  }

  Future<void> _runSpeed() async {
    if (_speedRunning) return;
    setState(() {
      _speedRunning = true;
      _speedFailed = false;
      _speed = null;
      _speedStage = context.tr('latency');
    });
    final ping = await _net.latency();
    if (!mounted) return;
    setState(() => _speedStage = context.tr('download'));
    final down = await _net.download();
    if (!mounted) return;
    setState(() => _speedStage = context.tr('upload'));
    final up = await _net.upload();
    if (!mounted) return;
    setState(() {
      _speedRunning = false;
      _speed = SpeedResult(pingMs: ping, downMbps: down, upMbps: up);
      _speedFailed = ping == null && down == null && up == null;
    });
  }

  Future<void> _importOvpn() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    AdsService.instance.suppressAppOpen(const Duration(minutes: 5));
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      final file = res?.files.single;
      if (file == null || file.bytes == null) return;
      final text = utf8.decode(file.bytes!, allowMalformed: true);
      final server = await ImportedServersService.instance.add(file.name, text);
      if (server == null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.t('import_bad'))));
        return;
      }
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.t('import_ok', {'name': server.countryLong}))));
      await _loadImported();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.t('import_bad'))));
    }
  }

  Widget _card({required IconData icon, required String title, Widget? trailing, required Widget child}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.accentStart, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(k, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _metric(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
      );

  String _mbps(double? v) => v == null ? '—' : '${v.toStringAsFixed(v >= 10 ? 0 : 1)} Mbps';

  @override
  Widget build(BuildContext context) {
    final ip = _ip;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(context.tr('tools')), backgroundColor: AppTheme.surface),
      bottomNavigationBar: const BannerAdWidget(),
      body: RefreshIndicator(
        onRefresh: () async {
          await _checkIp();
          await _loadUsage();
        },
        child: ListView(
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          children: [
            _card(
              icon: Icons.public_rounded,
              title: context.tr('ip_check'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: _ipLoading ? null : _checkIp,
              ),
              child: _ipLoading
                  ? Text(context.tr('ip_checking'),
                      style: TextStyle(color: AppTheme.textSecondary))
                  : _ipFailed || ip == null
                      ? Text(context.tr('ip_failed'),
                          style: const TextStyle(color: AppTheme.danger))
                      : Column(
                          children: [
                            _kv(context.tr('ip_label'), ip.ip),
                            if (ip.country.isNotEmpty)
                              _kv(
                                context.tr('location'),
                                '${ip.countryCode.length == 2 ? '${flagEmoji(ip.countryCode)} ' : ''}'
                                    '${ip.city.isNotEmpty ? '${ip.city}, ' : ''}${ip.country}',
                              ),
                            if (ip.isp.isNotEmpty) _kv(context.tr('isp'), ip.isp),
                          ],
                        ),
            ),
            _card(
              icon: Icons.speed_rounded,
              title: context.tr('speed_test'),
              child: Column(
                children: [
                  Row(
                    children: [
                      _metric(context.tr('latency'),
                          _speed?.pingMs == null ? '—' : '${_speed!.pingMs!.round()} ms'),
                      _metric(context.tr('download'), _mbps(_speed?.downMbps)),
                      _metric(context.tr('upload'), _mbps(_speed?.upMbps)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_speedFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(context.tr('speed_failed'),
                          style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _speedRunning ? null : _runSpeed,
                      icon: _speedRunning
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(_speedRunning
                          ? '${context.tr('speed_running')} $_speedStage'
                          : context.tr('speed_start')),
                    ),
                  ),
                ],
              ),
            ),
            _card(
              icon: Icons.data_usage_rounded,
              title: context.tr('usage'),
              trailing: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: Text(context.tr('history')),
              ),
              child: Column(
                children: [
                  _kv(context.tr('usage_today'), _usageLine(_today)),
                  _kv(context.tr('usage_week'), _usageLine(_week)),
                  _kv(context.tr('usage_month'), _usageLine(_month)),
                ],
              ),
            ),
            _card(
              icon: Icons.dns_rounded,
              title: context.tr('my_servers'),
              trailing: TextButton.icon(
                onPressed: _importOvpn,
                icon: const Icon(Icons.file_open_rounded, size: 18),
                label: Text(context.tr('import_ovpn')),
              ),
              child: _imported.isEmpty
                  ? Text(context.tr('my_servers_empty'),
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))
                  : Column(
                      children: _imported
                          .map((s) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.vpn_key_rounded),
                                title: Text(s.countryLong,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(s.ip,
                                    style: TextStyle(
                                        color: AppTheme.textSecondary, fontSize: 12)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: context.tr('delete'),
                                      icon: const Icon(Icons.delete_outline_rounded),
                                      onPressed: () async {
                                        await ImportedServersService.instance.remove(s);
                                        await _loadImported();
                                      },
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(context, s),
                                      child: Text(context.tr('connect')),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _usageLine(({int bytes, int sessions})? u) {
    if (u == null) return '—';
    return '${UsageService.formatBytes(u.bytes)} • ${context.tr('usage_sessions')}: ${u.sessions}';
  }
}
