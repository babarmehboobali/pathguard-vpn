import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _autoConnect = 'auto_connect';
  static const String _preferUdp = 'prefer_udp';
  static const String _lastMode = 'last_mode';
  static const String _splitExclude = 'split_exclude';

  Future<bool> getAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoConnect) ?? false;
  }

  Future<void> setAutoConnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoConnect, value);
  }

  Future<bool> getPreferUdp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_preferUdp) ?? true;
  }

  Future<void> setPreferUdp(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferUdp, value);
  }

  Future<String> getLastMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastMode) ?? 'free';
  }

  Future<void> setLastMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastMode, value);
  }

  Future<List<String>> getSplitExclude() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_splitExclude) ?? [];
  }

  Future<void> setSplitExclude(List<String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_splitExclude, value);
  }
}
