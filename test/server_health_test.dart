import 'package:flutter_test/flutter_test.dart';
import 'package:pathguard_vpn/models/server.dart';
import 'package:pathguard_vpn/services/vpngate_service.dart';

Server _s(String ip, int measured, {String proto = 'tcp'}) => Server(
      hostName: 'h$ip',
      ip: ip,
      score: 1,
      ping: 50,
      speed: 1000000,
      countryLong: 'Japan',
      countryShort: 'JP',
      numVpnSessions: 1,
      uptime: 1,
      totalUsers: 1,
      totalTraffic: 0,
      logType: '',
      operator: '',
      message: '',
      // "proto tcp\nremote 1.2.3.4 443"
      openVpnConfigBase64: 'cHJvdG8gdGNwCnJlbW90ZSAxLjIuMy40IDQ0Mw==',
      measuredPing: measured,
    );

void main() {
  test('dead / live flags', () {
    expect(_s('1', -1).isDead, true);
    expect(_s('1', 0).isDead, false);
    expect(_s('1', 80).isLive, true);
  });

  test('Stealth picker skips servers that failed the reachability test', () {
    final picked = VpnGateService()
        .pickBestStealthTcp443Server([_s('dead', -1), _s('ok', 120)], countryCode: 'JP');
    expect(picked?.ip, 'ok');
  });

  test('falls back to dead servers only when nothing else exists', () {
    final picked =
        VpnGateService().pickBestStealthTcp443Server([_s('dead', -1)], countryCode: 'JP');
    expect(picked?.ip, 'dead');
  });

  test('Tor list has no countries without reliable exits', () {
    final codes = VpnGateService.torExitCountries.map((c) => c.code).toSet();
    expect(codes.contains('SA'), false);
    expect(codes.contains('PK'), false);
    expect(codes.length - 1, 33);
  });
}
