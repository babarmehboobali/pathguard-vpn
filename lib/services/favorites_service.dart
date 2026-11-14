import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';

/// Favorite and recently used Free servers (stored with their config so they
/// still work when the live list is refreshed).
class FavoritesService {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  static const String _favKey = 'fav_servers_v1';
  static const String _recentKey = 'recent_servers_v1';
  static const int maxRecent = 5;
  static const int maxFavorites = 30;

  static String keyOf(Server s) => '${s.ip}|${s.hostName}';

  Future<List<Server>> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(key) ?? const <String>[];
    final out = <Server>[];
    for (final r in raw) {
      try {
        out.add(Server.fromJson(Map<String, dynamic>.from(jsonDecode(r) as Map)));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _write(String key, List<Server> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, list.map((s) => jsonEncode(s.toJson())).toList());
  }

  Future<List<Server>> favorites() => _read(_favKey);
  Future<List<Server>> recents() => _read(_recentKey);

  Future<Set<String>> favoriteKeys() async => (await favorites()).map(keyOf).toSet();

  /// Toggles a favorite; returns true if it is now a favorite.
  Future<bool> toggleFavorite(Server s) async {
    final list = await favorites();
    final k = keyOf(s);
    final idx = list.indexWhere((e) => keyOf(e) == k);
    if (idx >= 0) {
      list.removeAt(idx);
      await _write(_favKey, list);
      return false;
    }
    list.insert(0, s);
    if (list.length > maxFavorites) list.removeRange(maxFavorites, list.length);
    await _write(_favKey, list);
    return true;
  }

  Future<void> addRecent(Server s) async {
    if (s.openVpnConfigBase64.isEmpty) return;
    final list = await recents();
    list.removeWhere((e) => keyOf(e) == keyOf(s));
    list.insert(0, s);
    if (list.length > maxRecent) list.removeRange(maxRecent, list.length);
    await _write(_recentKey, list);
  }
}
