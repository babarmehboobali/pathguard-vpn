import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/history_service.dart';
import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/banner_ad_widget.dart';

/// Last 30 connections, stored only on the phone.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SessionRecord> _items = <SessionRecord>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await HistoryService.instance.list();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  static String _dur(int s) {
    final d = Duration(seconds: s);
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  static String _when(BuildContext context, DateTime t) {
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatShortDate(t)} · ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(t))}';
  }

  static IconData _modeIcon(String m) => switch (m) {
        'tor' => Icons.hub_rounded,
        'stealth' => Icons.shield_moon_rounded,
        'warp' => Icons.bolt_rounded,
        _ => Icons.public_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('history')),
        backgroundColor: AppTheme.surface,
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: context.tr('clear'),
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () async {
                await HistoryService.instance.clear();
                await _load();
              },
            ),
        ],
      ),
      bottomNavigationBar: const BannerAdWidget(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(context.tr('history_empty'),
                      style: TextStyle(color: AppTheme.textSecondary)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = _items[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: Icon(_modeIcon(r.mode), color: AppTheme.accentStart),
                        title: Text(r.place.isEmpty ? r.mode.toUpperCase() : r.place,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(_when(context, r.start),
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_dur(r.seconds),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(UsageService.formatBytes(r.bytesIn + r.bytesOut),
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
