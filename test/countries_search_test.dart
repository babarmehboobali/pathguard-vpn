import 'package:flutter_test/flutter_test.dart';
import 'package:pathguard_vpn/services/vpngate_service.dart';
import 'package:pathguard_vpn/models/server.dart';

Server _s({
  required String ip,
  required String countryShort,
  required String countryLong,
  required String openVpnConfigBase64,
  required String hostName,
}) {
  return Server(
    hostName: hostName,
    ip: ip,
    score: 1,
    ping: 50,
    speed: 1000000,
    countryLong: countryLong,
    countryShort: countryShort,
    numVpnSessions: 1,
    uptime: 1000,
    totalUsers: 1,
    totalTraffic: 0,
    logType: '2weeks',
    operator: 'test',
    message: '',
    openVpnConfigBase64: openVpnConfigBase64,
  );
}

void main() {
  test('pinned SA/PK exist even with zero matching servers', () {
    expect(VpnGateService.countryAliases.containsKey('SA'), true);
    expect(VpnGateService.countryAliases.containsKey('PK'), true);
  });

  test('alias search matches SA/PK', () {
    expect(VpnGateService.matchesAlias('SA', 'KSA'), true);
    expect(VpnGateService.matchesAlias('SA', 'Saudi'), true);
    expect(VpnGateService.matchesAlias('SA', 'SA'), true);
    expect(VpnGateService.matchesAlias('SA', 'السعودية'), true);
    expect(VpnGateService.matchesAlias('PK', 'Pak'), true);
    expect(VpnGateService.matchesAlias('PK', 'PK'), true);
    expect(VpnGateService.matchesAlias('PK', 'Pakistan'), true);
    expect(VpnGateService.matchesAlias('PK', 'پاکستان'), true);
    expect(VpnGateService.matchesAlias('SA', 'Japan'), false);
  });

  test('pickBestStealthTcp443Server returns null for empty SA pool', () {
    final svc = VpnGateService();
    final servers = [
      _s(
        ip: '1.1.1.1',
        countryShort: 'JP',
        countryLong: 'Japan',
        openVpnConfigBase64: 'dGVzdA==',
        hostName: 'jp.example',
      ),
    ];
    expect(svc.pickBestStealthTcp443Server(servers, countryCode: 'SA'), isNull);
    expect(svc.pickBestStealthTcp443Server(servers, countryCode: 'PK'), isNull);
    expect(svc.pickBestStealthTcp443Server(servers, countryCode: null), isNotNull);
  });
}
