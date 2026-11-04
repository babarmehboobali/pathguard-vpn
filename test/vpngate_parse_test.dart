import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathguard_vpn/services/vpngate_service.dart';

void main() {
  test('parses valid CSV row', () {
    final b64 = 'A' * 80;
    const header = '*vpn_servers\n#HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,NumVpnSessions,Uptime,TotalUsers,TotalTraffic,LogType,Operator,Message,OpenVPN_ConfigData_Base64\n';
    final body = '${header}vpn123,1.2.3.4,1000,50,500,Germany,DE,10,1000,100,15,none,operator,msg,$b64\n*\n';
    final list = VpnGateService.parseCsvForTest(body);
    expect(list.length, 1);
    expect(list.first.ip, '1.2.3.4');
    expect(list.first.countryShort, 'DE');
    expect(list.first.score, 1000);
  });

  test('live/snapshot parse counts', () {
    for (final path in ['/tmp/vpngate_live.csv', 'assets/vpngate_snapshot.csv']) {
      final f = File(path);
      if (!f.existsSync()) continue;
      final list = VpnGateService.parseCsvForTest(f.readAsStringSync());
      final countries = list.map((s) => s.countryShort).toSet();
      // ignore: avoid_print
      print('PARSE $path servers=${list.length} countries=${countries.length} ${countries.toList()..sort()}');
    }
  });
}
