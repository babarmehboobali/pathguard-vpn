import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class IpInfo {
  final String ip;
  final String country;
  final String countryCode;
  final String city;
  final String isp;

  const IpInfo({
    required this.ip,
    this.country = '',
    this.countryCode = '',
    this.city = '',
    this.isp = '',
  });
}

class SpeedResult {
  final double? pingMs;
  final double? downMbps;
  final double? upMbps;
  const SpeedResult({this.pingMs, this.downMbps, this.upMbps});
}

/// "My IP" check and a simple speed test (Cloudflare public speed endpoints).
class NetToolsService {
  NetToolsService._();
  static final NetToolsService instance = NetToolsService._();

  static const String _speedHost = 'https://speed.cloudflare.com';

  Future<IpInfo?> checkIp() async {
    try {
      final r = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
        if (j['success'] != false && j['ip'] != null) {
          final conn = j['connection'] is Map ? Map<String, dynamic>.from(j['connection'] as Map) : null;
          return IpInfo(
            ip: '${j['ip']}',
            country: '${j['country'] ?? ''}',
            countryCode: '${j['country_code'] ?? ''}',
            city: '${j['city'] ?? ''}',
            isp: '${conn?['isp'] ?? conn?['org'] ?? ''}',
          );
        }
      }
    } catch (_) {}
    try {
      final r = await http
          .get(Uri.parse('https://api.ipify.org?format=json'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
        return IpInfo(ip: '${j['ip']}');
      }
    } catch (_) {}
    return null;
  }

  Future<double?> latency() async {
    double? best;
    for (var i = 0; i < 4; i++) {
      try {
        final sw = Stopwatch()..start();
        final r = await http
            .get(Uri.parse('$_speedHost/__down?bytes=0'))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        if (r.statusCode == 200) {
          final ms = sw.elapsedMicroseconds / 1000.0;
          if (best == null || ms < best) best = ms;
        }
      } catch (_) {}
    }
    return best;
  }

  /// Downloads for up to [maxTime] and returns Mbps.
  Future<double?> download({Duration maxTime = const Duration(seconds: 8)}) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse('$_speedHost/__down?bytes=50000000'));
      final sw = Stopwatch()..start();
      final resp = await client.send(req).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      var bytes = 0;
      final done = Completer<void>();
      late StreamSubscription<List<int>> sub;
      sub = resp.stream.listen(
        (chunk) {
          bytes += chunk.length;
          if (sw.elapsed >= maxTime && !done.isCompleted) {
            sub.cancel();
            done.complete();
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (_) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future.timeout(maxTime + const Duration(seconds: 3), onTimeout: () => sub.cancel());
      sw.stop();
      final secs = sw.elapsedMicroseconds / 1e6;
      if (bytes <= 0 || secs <= 0) return null;
      return bytes * 8 / secs / 1e6;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Uploads a 4 MB random payload and returns Mbps.
  Future<double?> upload() async {
    try {
      final rnd = Random();
      final payload = Uint8List(4 * 1024 * 1024);
      for (var i = 0; i < payload.length; i += 4096) {
        payload[i] = rnd.nextInt(256);
      }
      final sw = Stopwatch()..start();
      final r = await http
          .post(Uri.parse('$_speedHost/__up'), body: payload)
          .timeout(const Duration(seconds: 25));
      sw.stop();
      if (r.statusCode != 200) return null;
      final secs = sw.elapsedMicroseconds / 1e6;
      return payload.length * 8 / secs / 1e6;
    } catch (_) {
      return null;
    }
  }
}
