import 'package:shared_preferences/shared_preferences.dart';

class PremiumService {
  static const String _expiryKey = 'premium_expiry';

  Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = prefs.getInt(_expiryKey) ?? 0;
    return DateTime.now().millisecondsSinceEpoch < expiry;
  }

  Future<Duration> remaining() async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = prefs.getInt(_expiryKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= expiry) return Duration.zero;
    return Duration(milliseconds: expiry - now);
  }

  Future<void> grantPremium(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = DateTime.now().add(duration).millisecondsSinceEpoch;
    await prefs.setInt(_expiryKey, expiry);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_expiryKey);
  }
}
