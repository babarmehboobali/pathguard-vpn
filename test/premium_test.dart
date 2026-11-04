import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pathguard_vpn/services/premium_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('premium grant and check', () async {
    final service = PremiumService();
    await service.grantPremium(const Duration(minutes: 60));
    expect(await service.isPremium(), true);
    await service.clear();
    expect(await service.isPremium(), false);
  });
}
