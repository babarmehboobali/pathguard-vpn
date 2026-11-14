import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/server.dart';
import '../services/favorites_service.dart';
import '../services/vpngate_service.dart';
import '../theme/app_theme.dart';
import '../utils/flag.dart';
import '../widgets/banner_ad_widget.dart';

/// Pops with:
///  * a [Server]  → connect to that Free server
///  * `'auto'`    → Free "Auto (fastest)"
///  * a Map       → Tor / Stealth exit country {countryCode, countryLong, mode}
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
  final FavoritesService _favs = FavoritesService.instance;

  List<Server> _allServers = <Server>[];
  Map<String, List<Server>> _groupedByCountry = <String, List<Server>>{};
  List<Server> _favorites = <Server>[];
  List<Server> _recents = <Server>[];
  Set<String> _favKeys = <String>{};
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
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final f = await _favs.favorites();
    final r = await _favs.recents();
    if (!mounted) return;
    setState(() {
      _favorites = f;
      _recents = r;
      _favKeys = f.map(FavoritesService.keyOf).toSet();
    });
  }

  Future<void> _toggleFav(Server s) async {
    await _favs.toggleFavorite(s);
    await _loadFavorites();
  }

  void _applyServers(List<Server> all) {
    // Hide servers that failed the reachability test (they would not connect).
    final list = all.where((s) => !s.isDead).toList();
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
        final scored =
            await _vpngate.pingAndScore(res.servers, maxParallel: 25, timeoutMs: 800);
        if (mounted && scored.isNotEmpty) _applyServers(scored);
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatSpeed(int bps) {
    if (bps <= 0) return context.tr('fast');
    final mbps = bps / (1000 * 1000);
    if (mbps >= 10) return '${mbps.toStringAsFixed(0)} Mbps';
    return '${mbps.toStringAsFixed(1)} Mbps';
  }

  String _formatPing(Server s) {
    final p = s.measuredPing > 0 ? s.measuredPing : s.ping;
    if (p <= 0 || p >= 9000) return '— ms';
    return '$p ms';
  }

  bool _isLive(Server s) => _allServers.any((e) => e.ip == s.ip && !e.isDead);

  Widget _starButton(Server s) {
    final fav = _favKeys.contains(FavoritesService.keyOf(s));
    return IconButton(
      tooltip: context.tr('favorites'),
      icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded,
          color: fav ? Colors.amber : AppTheme.textSecondary),
      onPressed: () => _toggleFav(s),
    );
  }

  Widget _box({required Widget child, bool highlight = false}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: highlight
              ? Border.all(color: AppTheme.accentStart.withValues(alpha: 0.7), width: 1.4)
              : null,
        ),
        child: child,
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                color: AppTheme.accentStart,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );

  Widget _savedServerTile(Server s) {
    final live = _isLive(s);
    return _box(
      child: Material(type: MaterialType.transparency, child: ListTile(
        leading: Text(flagEmoji(s.countryShort), style: const TextStyle(fontSize: 26)),
        title: Text(s.countryLong, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${s.ip} • ${live ? context.tr('online_now') : context.tr('may_be_offline')}',
          style: TextStyle(
              color: live ? AppTheme.connected : AppTheme.textSecondary, fontSize: 12),
        ),
        trailing: _starButton(s),
        onTap: () => Navigator.pop(context, s),
      )),
    );
  }

  /// Pinned Free country (SA / PK): listed only while it has working servers.
  /// Pops a Map with mode 'free' → Home connects to the best server in that country.
  Widget _pinnedCountryTile(String code, String name) {
    final servers = _allServers
        .where((s) => s.countryShort.toUpperCase() == code && s.openVpnConfigBase64.isNotEmpty)
        .toList();
    // Only listed when it has at least one working server.
    if (servers.isEmpty) return const SizedBox.shrink();
    final subtitle =
        '${context.tr('n_servers', {'n': servers.length})} • ${_formatPing(servers.first)} • '
        '${_formatSpeed(servers.first.speed)}';
    return _box(
      child: ListTile(
        leading: Text(flagEmoji(code), style: const TextStyle(fontSize: 28)),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
        onTap: () => Navigator.pop(context, <String, String>{
          'countryCode': code,
          'countryLong': name,
          'mode': 'free',
        }),
      ),
    );
  }

  // ------------------------------------------------------------- Tor / Stealth

  Widget _buildTorCountryPicker(BuildContext context) {
    final countries = VpnGateService.torExitCountries.where((c) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return c.name.toLowerCase().contains(q) ||
          c.code.toLowerCase().contains(q) ||
          VpnGateService.matchesAlias(c.code, q);
    }).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: countries.length,
      itemBuilder: (context, index) {
        final item = countries[index];
        final isAuto = item.code == 'auto';
        final isSelected =
            (widget.selectedCountryCode ?? 'auto').toUpperCase() == item.code.toUpperCase();
        final sparse = VpnGateService.torSparseExits.contains(item.code);

        final matchingFreeCount = isAuto
            ? _allServers.length
            : _allServers
                .where((s) => s.countryShort.toUpperCase() == item.code.toUpperCase())
                .length;

        String subtitle;
        if (isAuto) {
          subtitle = context.tr('tor_auto_sub');
        } else if (widget.currentMode == 'stealth' && matchingFreeCount > 0) {
          subtitle = context.tr('stealth_exit_sub', {'code': item.code, 'n': matchingFreeCount});
        } else {
          subtitle = context.tr('tor_exit_sub', {'code': item.code});
        }
        if (sparse) subtitle = '$subtitle\n${context.tr('fewer_relays')}';

        return _box(
          highlight: isSelected,
          child: ListTile(
            leading: Text(isAuto ? '🌐' : flagEmoji(item.code),
                style: const TextStyle(fontSize: 28)),
            title: Text(isAuto ? context.tr('tor_any_country') : item.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle,
                style: TextStyle(
                    color: sparse ? Colors.amber.shade200 : AppTheme.textSecondary,
                    fontSize: 12)),
            isThreeLine: sparse,
            trailing: isSelected
                ? Icon(Icons.check_circle_rounded, color: AppTheme.connected)
                : Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            onTap: () {
              Navigator.pop(context, <String, String>{
                'countryCode': item.code,
                'countryLong': isAuto ? '' : item.name,
                'mode': widget.currentMode,
              });
            },
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------- Free

  List<Widget> _buildFreeList(List<MapEntry<String, List<Server>>> filteredCountries) {
    final out = <Widget>[];
    final searching = _searchQuery.trim().isNotEmpty;

    if (!searching) {
      out.add(_box(
        child: ListTile(
          leading: const Text('⚡', style: TextStyle(fontSize: 26)),
          title: Text(context.tr('server_auto_fastest'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(context.tr('auto_sub'),
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          trailing: Icon(Icons.bolt_rounded, color: AppTheme.accentStart),
          onTap: () => Navigator.pop(context, 'auto'),
        ),
      ));
      out.add(_pinnedCountryTile('SA', 'Saudi Arabia'));
      out.add(_pinnedCountryTile('PK', 'Pakistan'));
      if (_favorites.isNotEmpty) {
        out.add(_sectionTitle(context.tr('favorites')));
        out.addAll(_favorites.map(_savedServerTile));
      }
      final recentsNotFav =
          _recents.where((r) => !_favKeys.contains(FavoritesService.keyOf(r))).toList();
      if (recentsNotFav.isNotEmpty) {
        out.add(_sectionTitle(context.tr('recent')));
        out.addAll(recentsNotFav.map(_savedServerTile));
      }
      out.add(_sectionTitle(context.tr('all_locations')));
    }

    for (final entry in filteredCountries) {
      final countryName = entry.key;
      final servers = entry.value;
      if (servers.isEmpty) continue;
      final best = servers.first;
      final flag = flagEmoji(best.countryShort);

      if (servers.length == 1) {
        out.add(_box(
          child: ListTile(
            leading: Text(flag, style: const TextStyle(fontSize: 28)),
            title: Text(countryName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${context.tr('one_server')} • ${_formatPing(best)} • ${_formatSpeed(best.speed)}',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            trailing: _starButton(best),
            onTap: () => Navigator.pop(context, best),
          ),
        ));
        continue;
      }

      out.add(_box(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Text(flag, style: const TextStyle(fontSize: 28)),
            title: Text(countryName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${context.tr('n_servers', {'n': servers.length})} • '
              '${context.tr('best', {'ping': _formatPing(best)})} • ${_formatSpeed(best.speed)}',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, best),
                  child: Text(context.tr('fastest')),
                ),
                Icon(Icons.expand_more, color: AppTheme.textSecondary),
              ],
            ),
            children: servers.map((s) {
              return ListTile(
                contentPadding: const EdgeInsetsDirectional.only(start: 24, end: 8),
                title: Text(s.ip,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text('${_formatPing(s)} • ${_formatSpeed(s.speed)} • ${s.hostName}',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                trailing: _starButton(s),
                onTap: () => Navigator.pop(context, s),
              );
            }).toList(),
          ),
        ),
      ));
    }
    if (filteredCountries.isEmpty && !searching) {
      out.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(context.tr('no_free_now'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary)),
            TextButton(
              onPressed: () => _loadServers(force: true),
              child: Text(context.tr('retry')),
            ),
          ],
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final filteredCountries = _groupedByCountry.entries.where((entry) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      if (entry.value.isEmpty) return false;
      final short = entry.value.first.countryShort;
      return entry.key.toLowerCase().contains(q) ||
          short.toLowerCase().contains(q) ||
          VpnGateService.matchesAlias(short, q) ||
          entry.value.any((s) => s.ip.contains(q) || s.hostName.toLowerCase().contains(q));
    }).toList();

    final titleText = _isTorCountryPicker
        ? context.tr('countries_title_exit', {'n': VpnGateService.torExitCountries.length - 1})
        : context.tr('countries_title_servers',
            {'n': _allServers.length, 'c': _groupedByCountry.length});

    return Scaffold(
      backgroundColor: AppTheme.background,
      bottomNavigationBar: const BannerAdWidget(),
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text(titleText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        actions: [
          if (!_isTorCountryPicker)
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: context.tr('refresh'),
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
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: context.tr('search_hint'),
                hintStyle: TextStyle(color: AppTheme.textSecondary),
                prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
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
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(strokeWidth: 2),
                    const SizedBox(height: 12),
                    Text(context.tr('loading_servers'),
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            )
          else if (filteredCountries.isEmpty && _searchQuery.trim().isNotEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.tr('no_servers'),
                        style: TextStyle(color: AppTheme.textSecondary)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _loadServers(force: true),
                      child: Text(context.tr('retry')),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: _buildFreeList(filteredCountries),
              ),
            ),
        ],
      ),
    );
  }
}
