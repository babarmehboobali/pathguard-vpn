import 'dart:convert';
class Server {
  final String hostName;
  final String ip;
  final int score;
  final int ping;
  final int speed;
  final String countryLong;
  final String countryShort;
  final int numVpnSessions;
  final int uptime;
  final int totalUsers;
  final int totalTraffic;
  final String logType;
  final String operator;
  final String message;
  final String openVpnConfigBase64;
  final int measuredPing;

  Server({
    required this.hostName,
    required this.ip,
    required this.score,
    required this.ping,
    required this.speed,
    required this.countryLong,
    required this.countryShort,
    required this.numVpnSessions,
    required this.uptime,
    required this.totalUsers,
    required this.totalTraffic,
    required this.logType,
    required this.operator,
    required this.message,
    required this.openVpnConfigBase64,
    this.measuredPing = 0,
  });

  String get decodedConfig {
    try {
      return String.fromCharCodes(base64Decode(openVpnConfigBase64));
    } catch (_) {
      return '';
    }
  }

  Server copyWith({int? ping, int? measuredPing}) => Server(
        hostName: hostName,
        ip: ip,
        score: score,
        ping: ping ?? this.ping,
        speed: speed,
        countryLong: countryLong,
        countryShort: countryShort,
        numVpnSessions: numVpnSessions,
        uptime: uptime,
        totalUsers: totalUsers,
        totalTraffic: totalTraffic,
        logType: logType,
        operator: operator,
        message: message,
        openVpnConfigBase64: openVpnConfigBase64,
        measuredPing: measuredPing ?? this.measuredPing,
      );

  Map<String, dynamic> toJson() => {
        'hostName': hostName,
        'ip': ip,
        'score': score,
        'ping': ping,
        'speed': speed,
        'countryLong': countryLong,
        'countryShort': countryShort,
        'numVpnSessions': numVpnSessions,
        'uptime': uptime,
        'totalUsers': totalUsers,
        'totalTraffic': totalTraffic,
        'logType': logType,
        'operator': operator,
        'message': message,
        'openVpnConfigBase64': openVpnConfigBase64,
        'measuredPing': measuredPing,
      };

  factory Server.fromJson(Map<String, dynamic> j) => Server(
        hostName: j['hostName'] ?? '',
        ip: j['ip'] ?? '',
        score: j['score'] ?? 0,
        ping: j['ping'] ?? 0,
        speed: j['speed'] ?? 0,
        countryLong: j['countryLong'] ?? '',
        countryShort: j['countryShort'] ?? '',
        numVpnSessions: j['numVpnSessions'] ?? 0,
        uptime: j['uptime'] ?? 0,
        totalUsers: j['totalUsers'] ?? 0,
        totalTraffic: j['totalTraffic'] ?? 0,
        logType: j['logType'] ?? '',
        operator: j['operator'] ?? '',
        message: j['message'] ?? '',
        openVpnConfigBase64: j['openVpnConfigBase64'] ?? '',
        measuredPing: j['measuredPing'] ?? 0,
      );
}
