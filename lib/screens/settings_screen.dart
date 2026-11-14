import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../services/ads_service.dart';
import '../services/crash_service.dart';
import '../services/locale_service.dart';
import '../services/settings_service.dart';
import '../services/vpn_channel.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'help_screen.dart';
import 'language_screen.dart';
import 'split_tunnel_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String playUrl =
      'https://play.google.com/store/apps/details?id=com.ali_babar.pathguard_vpn';

  final SettingsService _settings = SettingsService();
  bool _autoConnect = false;
  bool _autoReconnect = true;
  bool _smartFallback = true;
  bool _preferUdp = true;
  String _dns = 'off';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _autoConnect = await _settings.getAutoConnect();
    _autoReconnect = await _settings.getAutoReconnect();
    _smartFallback = await _settings.getSmartFallback();
    _preferUdp = await _settings.getPreferUdp();
    _dns = await _settings.getDnsFilter();
    if (mounted) setState(() {});
  }

  String _dnsLabel(String v) => context.tr('dns_$v');

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                color: AppTheme.accentStart,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );

  Future<void> _pickDns() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in SettingsService.dnsFilterValues)
              RadioListTile<String>(
                value: v,
                groupValue: _dns,
                title: Text(ctx.tr('dns_$v')),
                onChanged: (x) => Navigator.pop(ctx, x),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _settings.setDnsFilter(picked);
    if (!mounted) return;
    setState(() => _dns = picked);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.tr('reconnect_note'))));
  }

  @override
  Widget build(BuildContext context) {
    final langCode = LocaleService.instance.locale.value?.languageCode;
    final langName =
        langCode == null ? context.tr('language_system') : (L10n.nativeNames[langCode] ?? langCode);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(context.tr('settings')), backgroundColor: AppTheme.surface),
      body: ListView(
        children: [
          _section(context.tr('set_section_connection')),
          SwitchListTile(
            title: Text(context.tr('auto_connect')),
            value: _autoConnect,
            onChanged: (v) async {
              await _settings.setAutoConnect(v);
              setState(() => _autoConnect = v);
            },
          ),
          SwitchListTile(
            title: Text(context.tr('auto_reconnect')),
            value: _autoReconnect,
            onChanged: (v) async {
              await _settings.setAutoReconnect(v);
              setState(() => _autoReconnect = v);
            },
          ),
          SwitchListTile(
            title: Text(context.tr('smart_fallback')),
            value: _smartFallback,
            onChanged: (v) async {
              await _settings.setSmartFallback(v);
              setState(() => _smartFallback = v);
            },
          ),
          SwitchListTile(
            title: Text(context.tr('prefer_udp')),
            value: _preferUdp,
            onChanged: (v) async {
              await _settings.setPreferUdp(v);
              setState(() => _preferUdp = v);
            },
          ),
          _section(context.tr('set_section_privacy')),
          ListTile(
            leading: const Icon(Icons.shield_rounded),
            title: Text(context.tr('safe_dns')),
            subtitle: Text('${_dnsLabel(_dns)} • ${context.tr('safe_dns_sub')}',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickDns,
          ),
          ListTile(
            leading: const Icon(Icons.power_settings_new_rounded),
            title: Text(context.tr('kill_switch')),
            subtitle: Text(context.tr('kill_switch_sub'),
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => VpnChannel().openVpnSettings(),
          ),
          ListTile(
            leading: const Icon(Icons.call_split_rounded),
            title: Text(context.tr('exclude_apps')),
            subtitle: Text(context.tr('exclude_apps_sub'),
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SplitTunnelScreen()),
            ),
          ),
          _section(context.tr('set_section_app')),
          ListTile(
            leading: const Icon(Icons.palette_rounded),
            title: Text(context.tr('appearance')),
            subtitle: Text(context.tr('appearance_sub'),
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppearanceScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: Text(context.tr('language')),
            subtitle: Text(langName,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LanguageScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.star_rate_rounded),
            title: Text(context.tr('rate_app')),
            onTap: () {
              AdsService.instance.suppressAppOpen();
              InAppReview.instance.openStoreListing();
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_rounded),
            title: Text(context.tr('share_app')),
            onTap: () {
              AdsService.instance.suppressAppOpen();
              Share.share(context.tr('share_text', {'url': playUrl}));
            },
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(context.tr('diagnostics')),
            onTap: () async {
              final log = await CrashService.instance.readLog();
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(ctx.tr('diagnostics')),
                  content: SingleChildScrollView(
                      child: Text(log.isEmpty ? ctx.tr('no_log') : log)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('close'))),
                  ],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: Text(context.tr('help')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(context.tr('about')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
