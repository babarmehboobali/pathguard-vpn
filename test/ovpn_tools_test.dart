import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pathguard_vpn/utils/ovpn_tools.dart';

void main() {
  const cfg = 'client\ndev tun\nproto udp\nremote 1.2.3.4 1194\ndhcp-option DNS 8.8.8.8\n<ca>\nABC\n</ca>\n';
  final b64 = base64Encode(utf8.encode(cfg));

  test('applyDns replaces DNS with the malware-filter preset', () {
    final out = utf8.decode(base64Decode(OvpnTools.applyDns(b64, 'malware')));
    expect(out.contains('dhcp-option DNS 8.8.8.8'), false);
    expect(out.contains('dhcp-option DNS 1.1.1.2'), true);
    expect(out.contains('<ca>'), true);
  });

  test('applyDns off / unknown (incl. removed ads preset) leaves config unchanged', () {
    expect(OvpnTools.applyDns(b64, 'off'), b64);
    expect(OvpnTools.applyDns(b64, 'ads'), b64);
  });

  test('looksValid / firstRemote', () {
    expect(OvpnTools.looksValid(cfg), true);
    expect(OvpnTools.looksValid('hello'), false);
    final r = OvpnTools.firstRemote(cfg)!;
    expect(r.host, '1.2.3.4');
    expect(r.port, 1194);
  });
}
