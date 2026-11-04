import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/server.dart';

class VpnGateService {
  // Primary VPN Gate API + open mirrors + public open-source CSV mirrors (10s timeout each)
  static const List<String> vpnGateCsvUrls = <String>[
    'https://www.vpngate.net/api/iphone/',
    'http://www.vpngate.net/api/iphone/',
    'https://raw.githubusercontent.com/Xmister/vpngate-mirror/master/vpngate.csv',
    'https://raw.githubusercontent.com/aleskxyz/vpngate-scraper/master/vpngate.csv',
    'https://api.allorigins.win/raw?url=http%3A%2F%2Fwww.vpngate.net%2Fapi%2Fiphone%2F',
    'https://corsproxy.io/?http%3A%2F%2Fwww.vpngate.net%2Fapi%2Fiphone%2F',
  ];

  // Additional open-source JSON / raw .ovpn config repositories (MIT/GPL licensed)
  static const List<String> extraJsonListUrls = <String>[
    'https://raw.githubusercontent.com/hookzof/socks5_list/master/tg/vpngate.json',
  ];

  /// 30+ countries available for Tor & Stealth exit-node selection (`ExitNodes {cc}` + `StrictNodes 1`)
  static const List<({String code, String name})> torExitCountries = <({String code, String name})>[
    (code: 'auto', name: 'Fastest / Any Country'),
    (code: 'US', name: 'United States'),
    (code: 'GB', name: 'United Kingdom'),
    (code: 'DE', name: 'Germany'),
    (code: 'FR', name: 'France'),
    (code: 'NL', name: 'Netherlands'),
    (code: 'SE', name: 'Sweden'),
    (code: 'CH', name: 'Switzerland'),
    (code: 'CA', name: 'Canada'),
    (code: 'JP', name: 'Japan'),
    (code: 'SG', name: 'Singapore'),
    (code: 'AU', name: 'Australia'),
    (code: 'IT', name: 'Italy'),
    (code: 'ES', name: 'Spain'),
    (code: 'PL', name: 'Poland'),
    (code: 'RO', name: 'Romania'),
    (code: 'FI', name: 'Finland'),
    (code: 'NO', name: 'Norway'),
    (code: 'AT', name: 'Austria'),
    (code: 'CZ', name: 'Czechia'),
    (code: 'IE', name: 'Ireland'),
    (code: 'BE', name: 'Belgium'),
    (code: 'DK', name: 'Denmark'),
    (code: 'HK', name: 'Hong Kong'),
    (code: 'IN', name: 'India'),
    (code: 'BR', name: 'Brazil'),
    (code: 'IS', name: 'Iceland'),
    (code: 'LU', name: 'Luxembourg'),
    (code: 'PT', name: 'Portugal'),
    (code: 'BG', name: 'Bulgaria'),
    (code: 'HU', name: 'Hungary'),
    (code: 'KR', name: 'South Korea'),
  ];

  /// Shared in-memory server list so CountriesScreen opens instantaneously without re-fetching.
  static List<Server> cachedMemoryServers = <Server>[];

  Future<({List<Server> servers, String source})> fetchServers({bool forceRefresh = false}) async {
    if (!forceRefresh && cachedMemoryServers.isNotEmpty) {
      return (servers: cachedMemoryServers, source: 'memory');
    }

    final bundledServers = await _loadBundledServers();
    if (cachedMemoryServers.isEmpty && bundledServers.isNotEmpty) {
      cachedMemoryServers = bundledServers;
    }

    File? cache;
    try {
      final dir = await getApplicationDocumentsDirectory();
      cache = File('${dir.path}/vpngate_cache_v3.json');

      if (!forceRefresh && await cache.exists()) {
        final age = DateTime.now().difference(await cache.lastModified());
        if (age.inHours < 4) {
          final json = await cache.readAsString();
          final list = (jsonDecode(json) as List<dynamic>)
              .map((e) => Server.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          if (list.length >= 12) {
            final merged = _mergeUnique(list, bundledServers);
            cachedMemoryServers = merged;
            return (servers: merged, source: 'cache');
          }
        }
      }
    } catch (_) {}

    // Fetch from multiple sources in parallel batches (10s timeout per source) and merge all results
    final collected = <Server>[];
    var anyLiveSuccess = false;

    final fetchFutures = vpnGateCsvUrls.map((url) async {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: const <String, String>{
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14) PathGuardVPN/1.0',
            'Accept': '*/*',
          },
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 && response.body.length > 500) {
          return await compute(_parseCsv, response.body);
        }
      } catch (e) {
        debugPrint('VPN source failed ($url): $e');
      }
      return <Server>[];
    });

    final results = await Future.wait(fetchFutures);
    for (final list in results) {
      if (list.isNotEmpty) {
        anyLiveSuccess = true;
        collected.addAll(list);
      }
    }

    // Also try extra JSON open-source lists
    for (final jsonUrl in extraJsonListUrls) {
      try {
        final resp = await http
            .get(Uri.parse(jsonUrl))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200 && resp.body.length > 200) {
          final extra = await compute(_parseExtraJson, resp.body);
          if (extra.isNotEmpty) {
            anyLiveSuccess = true;
            collected.addAll(extra);
          }
        }
      } catch (_) {}
    }

    if (anyLiveSuccess && collected.isNotEmpty) {
      final merged = _mergeUnique(collected, bundledServers);
      cachedMemoryServers = merged;
      try {
        await cache?.writeAsString(jsonEncode(merged.map((s) => s.toJson()).toList()));
      } catch (_) {}
      return (servers: merged, source: 'live');
    }

    if (cache != null && await cache.exists()) {
      try {
        final json = await cache.readAsString();
        final list = (jsonDecode(json) as List<dynamic>)
            .map((e) => Server.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (list.isNotEmpty) {
          final merged = _mergeUnique(list, bundledServers);
          cachedMemoryServers = merged;
          return (servers: merged, source: 'stale');
        }
      } catch (_) {}
    }

    if (bundledServers.isNotEmpty) {
      cachedMemoryServers = bundledServers;
      return (servers: bundledServers, source: 'bundled');
    }

    return (servers: cachedMemoryServers, source: 'none');
  }

  Future<List<Server>> _loadBundledServers() async {
    try {
      final body = await rootBundle.loadString('assets/vpngate_snapshot.csv');
      return _parseCsv(body);
    } catch (e) {
      debugPrint('Bundled snapshot failed: $e');
      return <Server>[];
    }
  }

  List<Server> _mergeUnique(List<Server> primary, List<Server> secondary) {
    final byIp = <String, Server>{};
    for (final s in primary) {
      if (s.ip.isNotEmpty && s.openVpnConfigBase64.isNotEmpty) {
        byIp[s.ip] = s;
      }
    }
    for (final s in secondary) {
      if (s.ip.isNotEmpty && s.openVpnConfigBase64.isNotEmpty) {
        byIp.putIfAbsent(s.ip, () => s);
      }
    }
    final list = byIp.values.toList();
    list.sort(_compareServersByQuality);
    return list;
  }

  static List<Server> _parseExtraJson(String body) {
    final servers = <Server>[];
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final ip = (map['ip'] ?? map['IP'] ?? '').toString().trim();
            final cc = (map['countryShort'] ?? map['country_code'] ?? '').toString().trim().toUpperCase();
            final cname = (map['countryLong'] ?? map['country'] ?? cc).toString().trim();
            final b64 = (map['openVpnConfigBase64'] ?? map['config_base64'] ?? '').toString().replaceAll(RegExp(r'\s+'), '');
            if (ip.isNotEmpty && cc.length == 2 && b64.length >= 64) {
              servers.add(Server(
                hostName: (map['hostName'] ?? 'vpn-$ip').toString(),
                ip: ip,
                score: int.tryParse((map['score'] ?? '500000').toString()) ?? 500000,
                ping: int.tryParse((map['ping'] ?? '50').toString()) ?? 50,
                speed: int.tryParse((map['speed'] ?? '25000000').toString()) ?? 25000000,
                countryLong: cname,
                countryShort: cc,
                numVpnSessions: 1,
                uptime: 10000,
                totalUsers: 100,
                totalTraffic: 0,
                logType: '2weeks',
                operator: 'Community',
                message: '',
                openVpnConfigBase64: b64,
              ));
            }
          }
        }
      }
    } catch (_) {}
    return servers;
  }

  @visibleForTesting
  static List<Server> parseCsvForTest(String body) => _parseCsv(body);

  static List<Server> _parseCsv(String body) {
    final lines = const LineSplitter().convert(body);
    final servers = <Server>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('*') || line.startsWith('#')) continue;
      final parts = line.split(',');
      if (parts.length < 15) continue;

      final ip = parts[1].trim();
      final countryLong = parts[5].trim();
      final countryShort = parts[6].trim();
      final b64 = parts.sublist(14).join(',').replaceAll(RegExp(r'\s+'), '');
      if (ip.isEmpty || countryShort.length != 2 || b64.length < 64) continue;

      try {
        servers.add(Server(
          hostName: parts[0].trim(),
          ip: ip,
          score: int.tryParse(parts[2].trim()) ?? 0,
          ping: int.tryParse(parts[3].trim()) ?? 0,
          speed: int.tryParse(parts[4].trim()) ?? 0,
          countryLong: countryLong.isNotEmpty ? countryLong : countryShort.toUpperCase(),
          countryShort: countryShort.toUpperCase(),
          numVpnSessions: int.tryParse(parts[7].trim()) ?? 0,
          uptime: int.tryParse(parts[8].trim()) ?? 0,
          totalUsers: int.tryParse(parts[9].trim()) ?? 0,
          totalTraffic: int.tryParse(parts[10].trim()) ?? 0,
          logType: parts[11].trim(),
          operator: parts[12].trim(),
          message: parts[13].trim(),
          openVpnConfigBase64: b64,
        ));
      } catch (_) {}
    }

    servers.sort((a, b) => b.score.compareTo(a.score));
    return servers;
  }

  /// Returns true if the server's OpenVPN config uses TCP 443 or TCP protocol suitable for Stealth fallback.
  bool isTcp443Capable(Server s) {
    final cfg = s.decodedConfig;
    final hasPort443 = RegExp(r'remote\s+\S+\s+443\b', caseSensitive: false).hasMatch(cfg);
    final isTcp = RegExp(r'proto\s+tcp', caseSensitive: false).hasMatch(cfg);
    return (hasPort443 && isTcp) || hasPort443 || isTcp;
  }

  /// Picks the best TCP 443 / TCP OpenVPN server for Stealth mode fallback, preferring `countryCode` if set.
  Server? pickBestStealthTcp443Server(List<Server> servers, {String? countryCode}) {
    if (servers.isEmpty) return null;
    final cleanCc = countryCode?.trim().toUpperCase();
    final pool = (cleanCc != null && cleanCc.length == 2 && cleanCc != 'UN')
        ? servers.where((s) => s.countryShort.toUpperCase() == cleanCc).toList()
        : servers;
    final searchList = pool.isNotEmpty ? pool : servers;

    // 1. Prefer explicit TCP 443 servers
    for (final s in searchList) {
      final cfg = s.decodedConfig;
      if (RegExp(r'remote\s+\S+\s+443\b', caseSensitive: false).hasMatch(cfg) &&
          RegExp(r'proto\s+tcp', caseSensitive: false).hasMatch(cfg)) {
        return s;
      }
    }
    // 2. Any TCP server
    for (final s in searchList) {
      if (RegExp(r'proto\s+tcp', caseSensitive: false).hasMatch(s.decodedConfig)) {
        return s;
      }
    }
    return searchList.first;
  }

  Future<List<Server>> pingAndScore(
    List<Server> servers, {
    int maxParallel = 25,
    int timeoutMs = 800,
  }) async {
    if (servers.isEmpty) return <Server>[];

    final toProbeIps = <String>{};
    final seenCountries = <String>{};
    for (final s in servers) {
      if (seenCountries.add(s.countryShort)) {
        toProbeIps.add(s.ip);
      }
    }
    for (final s in servers) {
      if (toProbeIps.length >= 45) break;
      toProbeIps.add(s.ip);
    }

    final toProbe = servers.where((s) => toProbeIps.contains(s.ip)).toList();
    final probedByIp = <String, Server>{};

    for (var i = 0; i < toProbe.length; i += maxParallel) {
      final batch = toProbe.skip(i).take(maxParallel);
      final futures = batch.map((s) async {
        final port = _extractPort(s.decodedConfig) ?? 443;
        final start = DateTime.now();
        try {
          final socket = await Socket.connect(
            s.ip,
            port,
            timeout: Duration(milliseconds: timeoutMs),
          );
          await socket.close();
          final ms = DateTime.now().difference(start).inMilliseconds;
          return s.copyWith(ping: ms, measuredPing: ms);
        } catch (_) {
          return s.copyWith(
            ping: s.ping > 0 ? s.ping : 250,
            measuredPing: 0,
          );
        }
      });
      for (final res in await Future.wait(futures)) {
        probedByIp[res.ip] = res;
      }
    }

    final merged = servers.map((s) => probedByIp[s.ip] ?? s).toList();
    merged.sort(_compareServersByQuality);
    cachedMemoryServers = merged;
    return merged;
  }

  static int _compareServersByQuality(Server a, Server b) {
    final aLive = a.measuredPing > 0 && a.measuredPing < 5000;
    final bLive = b.measuredPing > 0 && b.measuredPing < 5000;
    if (aLive != bLive) return aLive ? -1 : 1;
    if (aLive && bLive) {
      final cmp = a.measuredPing.compareTo(b.measuredPing);
      if (cmp != 0) return cmp;
    }
    final aPing = a.ping > 0 ? a.ping : 500;
    final bPing = b.ping > 0 ? b.ping : 500;
    final pingCmp = aPing.compareTo(bPing);
    if (pingCmp != 0) return pingCmp;
    return b.speed.compareTo(a.speed);
  }

  int? _extractPort(String config) {
    final match = RegExp(r'remote\s+\S+\s+(\d+)', caseSensitive: false).firstMatch(config);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  List<Server> bestPerCountry(List<Server> servers) {
    final map = <String, Server>{};
    for (final s in servers) {
      final code = s.countryShort.toUpperCase();
      final existing = map[code];
      if (existing == null || _compareServersByQuality(s, existing) < 0) {
        map[code] = s;
      }
    }
    final result = map.values.toList();
    result.sort(_compareServersByQuality);
    return result;
  }
}

