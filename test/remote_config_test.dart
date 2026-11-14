import 'package:flutter_test/flutter_test.dart';
import 'package:pathguard_vpn/services/remote_config_service.dart';

void main() {
  final cfg = RemoteConfigService.instance;

  test('remote values are clamped to policy-safe minimums', () {
    expect(
        cfg.applyJson('{"interstitial_every_actions": 0, "interstitial_min_gap_sec": 1,'
            '"app_open_min_gap_sec": 5, "app_open_min_background_sec": 0}'),
        true);
    expect(cfg.interstitialEveryActions, 2);
    expect(cfg.interstitialMinGapSec, 45);
    expect(cfg.appOpenMinGapSec, 120);
    expect(cfg.appOpenMinBackgroundSec, 10);
  });

  test('bad JSON is ignored and announcement falls back to English', () {
    expect(cfg.applyJson('not json'), false);
    cfg.applyJson('{"announcement": {"en": "Hello", "ar": "مرحبا"}}');
    expect(cfg.announcementFor('ar'), 'مرحبا');
    expect(cfg.announcementFor('ja'), 'Hello');
  });
}
