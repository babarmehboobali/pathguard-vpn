import 'dart:convert';

/// Helpers for OpenVPN configs (VPN Gate and user-imported .ovpn files).
class OvpnTools {
  OvpnTools._();

  /// Free public filtering DNS used by the "Safe browsing DNS" setting.
  ///  * malware → Cloudflare 1.1.1.2 (blocks malware & phishing)
  ///  * family  → Cloudflare 1.1.1.3 (malware + adult content)
  /// Deliberately NO ad-blocking preset: Google Play's VpnService policy forbids
  /// VPN apps from manipulating ads, and it would also block PathGuard's own AdMob ads.
  static const Map<String, List<String>> dnsPresets = <String, List<String>>{
    'malware': <String>['1.1.1.2', '1.0.0.2'],
    'family': <String>['1.1.1.3', '1.0.0.3'],
  };

  static String? _decode(String base64Config) {
    try {
      return utf8.decode(base64Decode(base64Config.trim()), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// Returns a config that forces the filtering DNS of [preset].
  /// ics-openvpn's ConfigParser turns `dhcp-option DNS` into an override, so the
  /// server-pushed DNS is replaced. Unknown preset / bad input → unchanged.
  static String applyDns(String base64Config, String preset) {
    final servers = dnsPresets[preset];
    if (servers == null || base64Config.isEmpty) return base64Config;
    final text = _decode(base64Config);
    if (text == null) return base64Config;
    final cleaned = text
        .split('\n')
        .where((l) => !l.trimLeft().toLowerCase().startsWith('dhcp-option dns'))
        .join('\n');
    final buf = StringBuffer(cleaned);
    if (!cleaned.endsWith('\n')) buf.write('\n');
    for (final s in servers) {
      buf.writeln('dhcp-option DNS $s');
    }
    return base64Encode(utf8.encode(buf.toString()));
  }

  /// Minimal sanity check for an imported .ovpn file.
  static bool looksValid(String text) {
    final hasRemote = RegExp(r'^\s*remote\s+\S+', multiLine: true).hasMatch(text);
    final hasCa = text.contains('<ca>') || RegExp(r'^\s*ca\s+\S+', multiLine: true).hasMatch(text);
    return hasRemote && hasCa && text.length < 512 * 1024;
  }

  /// First `remote <host> [port]` line.
  static ({String host, int port})? firstRemote(String text) {
    final m = RegExp(r'^\s*remote\s+(\S+)(?:\s+(\d+))?', multiLine: true).firstMatch(text);
    if (m == null) return null;
    return (host: m.group(1)!, port: int.tryParse(m.group(2) ?? '') ?? 1194);
  }
}
