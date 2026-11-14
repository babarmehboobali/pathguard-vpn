import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SessionRecord {
  final DateTime start;
  final int seconds;
  final int bytesIn;
  final int bytesOut;
  final String mode;
  final String place; // country / server name shown to the user

  const SessionRecord({
    required this.start,
    required this.seconds,
    required this.bytesIn,
    required this.bytesOut,
    required this.mode,
    required this.place,
  });

  Map<String, dynamic> toJson() => {
        's': start.millisecondsSinceEpoch,
        'd': seconds,
        'i': bytesIn,
        'o': bytesOut,
        'm': mode,
        'p': place,
      };

  factory SessionRecord.fromJson(Map<String, dynamic> j) => SessionRecord(
        start: DateTime.fromMillisecondsSinceEpoch((j['s'] as num?)?.toInt() ?? 0),
        seconds: (j['d'] as num?)?.toInt() ?? 0,
        bytesIn: (j['i'] as num?)?.toInt() ?? 0,
        bytesOut: (j['o'] as num?)?.toInt() ?? 0,
        mode: '${j['m'] ?? ''}',
        place: '${j['p'] ?? ''}',
      );
}

/// Local-only list of the last connections (never leaves the phone).
class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  static const String _key = 'session_history_v1';
  static const int maxItems = 30;

  Future<List<SessionRecord>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final out = <SessionRecord>[];
    for (final r in raw) {
      try {
        out.add(SessionRecord.fromJson(Map<String, dynamic>.from(jsonDecode(r) as Map)));
      } catch (_) {}
    }
    return out;
  }

  Future<void> add(SessionRecord r) async {
    if (r.seconds < 5) return;
    final items = await list();
    items.insert(0, r);
    if (items.length > maxItems) items.removeRange(maxItems, items.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, items.map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
