import 'package:flutter/material.dart';
import '../models/server.dart';
import '../services/vpngate_service.dart';
import '../theme/app_theme.dart';
import '../utils/flag.dart';

class CountriesScreen extends StatefulWidget {
  final List<Server>? initialServers;
  final String currentMode;
  final String? selectedCountryCode;

  const CountriesScreen({
    super.key,
    this.initialServers,
    this.currentMode = 'free',
    this.selectedCountryCode,
  });

  @override
  State<CountriesScreen> createState() => _CountriesScreenState();
}

class _CountriesScreenState extends State<CountriesScreen> {
  final VpnGateService _vpngate = VpnGateService();
  List<Server> _allServers = <Server>[];
  Map<String, List<Server>> _groupedByCountry = <String, List<Server>>{};
  bool _loading = false;
  String _searchQuery = '';
  late bool _isTorCountryPicker;

  @override
  void initState() {
    super.initState();
    _isTorCountryPicker = widget.currentMode == 'tor' || widget.currentMode == 'stealth';

    final seed = (widget.initialServers != null && widget.initialServers!.isNotEmpty)
        ? widget.initialServers!
        : VpnGateService.cachedMemoryServers;
    if (seed.isNotEmpty) {
      _applyServers(seed);
    } else if (!_isTorCountryPicker) {
      _loadServers(force: false);
    }
  }

  void _applyServers(List<Server> list) {
    final grouped = <String, List<Server>>{};
    for (final s in list) {
      final key = s.countryLong.isNotEmpty ? s.countryLong : s.countryShort;
      grouped.putIfAbsent(key, () => <Server>[]).add(s);
    }
    setState(() {
      _allServers = list;
      _groupedByCountry = grouped;
      _loading = false;
    });
  }

  Future<void> _loadServers({bool force = false}) async {
    setState(() => _loading = true);
    try {
      final res = await _vpngate.fetchServers(forceRefresh: force);
      if (!mounted) return;
      if (res.servers.isNotEmpty) {
        _applyServers(res.servers);
        final scored = await _vpngate.pingAndScore(res.servers, maxParallel: 25, timeoutMs: 800);
        if (mounted && scored.isNotEmpty) {
          _applyServers(scored);
        }
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatSpeed(int bps) {
    if (bps <= 0) return 'Fast';
    final mbps = bps / (1000 * 1000);
    if (mbps >= 10) return '${mbps.toStringAsFixed(0)} Mbps';
    return '${mbps.toStringAsFixed(1)} Mbps';
  }

  String _formatPing(Server s) {
    final p = s.measuredPing > 0 ? s.measuredPing : s.ping;
    if (p <= 0 || p >= 9000) return '— ms';
    return '$p ms';
  }

  Widget _buildTorCountryPicker(BuildContext context) {
    final countries = VpnGateService.torExitCountries.where((c) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return c.name.toLowerCase().contains(q) || c.code.toLowerCase().contains(q);
    }).toList();

    final modeTitle = widget.currentMode == 'stealth' ? 'Stealth' : 'Tor';

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: countries.length,
      itemBuilder: (context, index) {
        final item = countries[index];
        final isAuto = item.code == 'auto';
        final flag = isAuto ? '🌐' : flagEmoji(item.code);
        final isSelected = (widget.selectedCountryCode ?? 'auto').toUpperCase() ==
            item.code.toUpperCase();

        // Also show how many OpenVPN TCP-443 servers exist in this country if in Stealth mode
        final matchingFreeCount = isAuto
            ? _allServers.length
            : _allServers
                .where((s) => s.countryShort.toUpperCase() == item.code.toUpperCase())
                .length;

        final subtitle = isAuto
            ? 'Automatic fastest multi-hop relay (Recommended)'
            : widget.currentMode == 'stealth' && matchingFreeCount > 0
                ? 'Tor Exit {${item.code.toLowerCase()}} + $matchingFreeCount Stealth TCP-443 relays'
                : '$modeTitle Exit Node {${item.code.toLowerCase()}} • StrictNodes 1';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(color: AppTheme.accentStart.withOpacity(0.7), width: 1.4)
                : null,
          ),
          child: ListTile(
            leading: Text(flag, style: const TextStyle(fontSize: 28)),
            title: Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            trailing: isSelected
                ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676))
                : const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            onTap: () {
              Navigator.pop(context, <String, String>{
                'countryCode': item.code,
                'countryLong': item.name,
                'mode': widget.currentMode,
              });
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredCountries = _groupedByCountry.entries.where((entry) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return entry.key.toLowerCase().contains(q) ||
          entry.value.first.countryShort.toLowerCase().contains(q) ||
          entry.value.any((s) => s.ip.contains(q));
    }).toList();

    final titleText = _isTorCountryPicker
        ? 'Select Exit Country (${VpnGateService.torExitCountries.length - 1} countries)'
        : 'Select Location (${_allServers.length} servers)';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text(
          titleText,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (!_isTorCountryPicker)
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh servers',
                onPressed: () => _loadServers(force: true),
              ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search country or IP…',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                filled: true,
                fillColor: AppTheme.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_isTorCountryPicker)
            Expanded(child: _buildTorCountryPicker(context))
          else if (_loading && _allServers.isEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 12),
                    Text(
                      'Loading worldwide servers…',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredCountries.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No servers found',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _loadServers(force: true),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: filteredCountries.length,
                itemBuilder: (context, index) {
                  final entry = filteredCountries[index];
                  final countryName = entry.key;
                  final servers = entry.value;
                  final best = servers.first;
                  final flag = flagEmoji(best.countryShort);

                  if (servers.length == 1) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: Text(flag, style: const TextStyle(fontSize: 28)),
                        title: Text(
                          countryName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '1 server • ${best.ip} •${_formatSpeed(best.speed)}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                        trailing: Text(
                          _formatPing(best),
                          style: TextStyle(
                            color: best.measuredPing > 0
                                ? const Color(0xFF00E676)
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        onTap: () => Navigator.pop(context, best),
                      ),
                    );
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: Text(flag, style: const TextStyle(fontSize: 28)),
                        title: Text(
                          countryName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${servers.length} servers • Best: ${_formatPing(best)} •${_formatSpeed(best.speed)}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, best),
                              child: const Text('Fastest'),
                            ),
                            const Icon(Icons.expand_more, color: AppTheme.textSecondary),
                          ],
                        ),
                        children: servers.map((s) {
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                            title: Text(
                              s.ip,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              '${_formatSpeed(s.speed)} •${s.hostName}',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                            trailing: Text(
                              _formatPing(s),
                              style: TextStyle(
                                color: s.measuredPing > 0
                                    ? const Color(0xFF00E676)
                                    : AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () => Navigator.pop(context, s),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

