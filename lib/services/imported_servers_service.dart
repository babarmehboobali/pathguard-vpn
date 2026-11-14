import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../utils/ovpn_tools.dart';

/// User-imported .ovpn configs ("My servers"). Stored locally only.
class ImportedServersService {
  ImportedServersService._();
  static final ImportedServersService instance = ImportedServersService._();

  static const String _key = 'imported_ovpn_v1';
  static const String hostPrefix = 'imported:';

  Future<List<Server>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final out = <Server>[];
    for (final r in raw) {
      try {
        out.add(Server.fromJson(Map<String, dynamic>.from(jsonDecode(r) as Map)));
      } catch (_) {}
    }
    return out;
  }

  /// Returns the new server, or null if the text is not a usable config.
  Future<Server?> add(String fileName, String text) async {
    if (!OvpnTools.looksValid(text)) return null;
    final remote = OvpnTools.firstRemote(text);
    var name = fileName.replaceAll(RegExp(r'\.ovpn$', caseSensitive: false), '').trim();
    if (name.isEmpty) name = remote?.host ?? 'My server';
    final server = Server(
      hostName: '$hostPrefix$name',
      ip: remote?.host ?? '',
      score: 0,
      ping: 0,
      speed: 0,
      countryLong: name,
      countryShort: '',
      numVpnSessions: 0,
      uptime: 0,
      totalUsers: 0,
      totalTraffic: 0,
      logType: '',
      operator: '',
      message: '',
      openVpnConfigBase64: base64Encode(utf8.encode(text)),
    );
    final items = await list();
    items.removeWhere((s) => s.hostName == server.hostName);
    items.insert(0, server);
    await _save(items);
    return server;
  }

  Future<void> remove(Server s) async {
    final items = await list();
    items.removeWhere((e) => e.hostName == s.hostName);
    await _save(items);
  }

  Future<void> _save(List<Server> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, items.map((s) => jsonEncode(s.toJson())).toList());
  }

  static bool isImported(Server? s) => s != null && s.hostName.startsWith(hostPrefix);
}
