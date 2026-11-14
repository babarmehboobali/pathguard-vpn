import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pathguard_vpn/services/premium_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PremiumService().clear();
  });

  test('premium +6h grant, stacking, and 24h cap', () async {
    final service = PremiumService();

    await service.grantPremium(const Duration(hours: 6));
    expect(await service.isPremium(), true);
    var rem = await service.remaining();
    expect(rem.inHours, greaterThanOrEqualTo(5));
    expect(rem.inHours, lessThanOrEqualTo(6));

    await service.grantPremium(const Duration(hours: 6));
    rem = await service.remaining();
    expect(rem.inHours, greaterThanOrEqualTo(11));
    expect(rem.inHours, lessThanOrEqualTo(12));

    await service.grantPremium(const Duration(hours: 6));
    rem = await service.remaining();
    expect(rem.inHours, greaterThanOrEqualTo(17));
    expect(rem.inHours, lessThanOrEqualTo(18));

    await service.grantPremium(const Duration(hours: 6));
    rem = await service.remaining();
    expect(rem.inHours, lessThanOrEqualTo(24));
    expect(rem.inHours, greaterThanOrEqualTo(23));

    await service.clear();
    expect(await service.isPremium(), false);
    expect((await service.remaining()).inSeconds, 0);
  });

  test('each reward adds 6h and stacks up to the 24h cap', () async {
    final service = PremiumService();
    expect(await service.addRewardTime(), true);
    final first = await service.remaining();
    expect(first.inMinutes, closeTo(6 * 60, 1));

    expect(await service.addRewardTime(), true); // 12h
    expect(await service.addRewardTime(), true); // 18h
    expect(await service.addRewardTime(), true); // 24h
    expect((await service.remaining()).inMinutes, closeTo(24 * 60, 1));
    expect(await service.isAtCap(), true);

    // Already at cap: no extra time granted
    expect(await service.addRewardTime(), false);
    expect((await service.remaining()).inMinutes, lessThanOrEqualTo(24 * 60));
  });

  test('banner notifier reflects ad-free state', () async {
    final service = PremiumService();
    expect(PremiumService.isAdFreeNow, false);
    await service.addRewardTime();
    expect(PremiumService.isAdFreeNow, true);
    await service.clear();
    expect(PremiumService.isAdFreeNow, false);
  });
}
