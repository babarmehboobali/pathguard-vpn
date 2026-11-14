import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local-only data usage counter (never leaves the device).
class UsageService {
  UsageService._();
  static final UsageService instance = UsageService._();

  static const String _key = 'usage_daily_v1';
  static const int _keepDays = 31;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, List<int>>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return <String, List<int>>{};
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return m.map((k, v) => MapEntry(k, List<int>.from(v as List)));
    } catch (_) {
      return <String, List<int>>{};
    }
  }

  /// Records one finished session. Value per day = [bytes, sessions].
  Future<void> addSession({required int bytesIn, required int bytesOut}) async {
    final total = bytesIn + bytesOut;
    if (total <= 0) return;
    final data = await _read();
    final today = _day(DateTime.now());
    final cur = data[today] ?? <int>[0, 0];
    data[today] = <int>[cur[0] + total, cur[1] + 1];
    final cutoff = _day(DateTime.now().subtract(const Duration(days: _keepDays)));
    data.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  /// Returns (bytes, sessions) for the last [days] days including today.
  Future<({int bytes, int sessions})> lastDays(int days) async {
    final data = await _read();
    final cutoff = _day(DateTime.now().subtract(Duration(days: days - 1)));
    var bytes = 0;
    var sessions = 0;
    data.forEach((k, v) {
      if (k.compareTo(cutoff) >= 0) {
        bytes += v[0];
        sessions += v.length > 1 ? v[1] : 0;
      }
    });
    return (bytes: bytes, sessions: sessions);
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
