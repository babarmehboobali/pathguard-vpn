import 'package:shared_preferences/shared_preferences.dart';

import 'remote_config_service.dart';

class SettingsService {
  static const String _autoConnect = 'auto_connect';
  static const String _autoReconnect = 'auto_reconnect';
  static const String _smartFallback = 'smart_fallback';
  static const String _preferUdp = 'prefer_udp';
  static const String _lastMode = 'last_mode';
  static const String _splitExclude = 'split_exclude';
  static const String _dnsFilter = 'dns_filter';
  static const String _connectCount = 'connect_count';
  static const String _reviewAsked = 'review_asked';

  /// DNS filter presets: off | malware | family  (no ad blocking — Play VpnService policy)
  static const List<String> dnsFilterValues = <String>['off', 'malware', 'family'];

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  Future<bool> getAutoConnect() async => (await _p).getBool(_autoConnect) ?? false;
  Future<void> setAutoConnect(bool value) async {
    await (await _p).setBool(_autoConnect, value);
  }

  Future<bool> getAutoReconnect() async => (await _p).getBool(_autoReconnect) ?? true;
  Future<void> setAutoReconnect(bool value) async {
    await (await _p).setBool(_autoReconnect, value);
  }

  Future<bool> getSmartFallback() async =>
      (await _p).getBool(_smartFallback) ?? RemoteConfigService.instance.smartFallbackDefault;
  Future<void> setSmartFallback(bool value) async {
    await (await _p).setBool(_smartFallback, value);
  }

  Future<bool> getPreferUdp() async => (await _p).getBool(_preferUdp) ?? true;
  Future<void> setPreferUdp(bool value) async {
    await (await _p).setBool(_preferUdp, value);
  }

  Future<String> getLastMode() async => (await _p).getString(_lastMode) ?? 'free';
  Future<void> setLastMode(String value) async {
    await (await _p).setString(_lastMode, value);
  }

  Future<List<String>> getSplitExclude() async => (await _p).getStringList(_splitExclude) ?? [];
  Future<void> setSplitExclude(List<String> value) async {
    await (await _p).setStringList(_splitExclude, value);
  }

  Future<String> getDnsFilter() async {
    final v = (await _p).getString(_dnsFilter) ?? 'off';
    if (v == 'ads') return 'malware'; // migrate 1.0.5 beta value
    return dnsFilterValues.contains(v) ? v : 'off';
  }

  Future<void> setDnsFilter(String value) async {
    await (await _p).setString(_dnsFilter, dnsFilterValues.contains(value) ? value : 'off');
  }

  /// Counts successful connections; returns the new total.
  Future<int> incrementConnectCount() async {
    final prefs = await _p;
    final next = (prefs.getInt(_connectCount) ?? 0) + 1;
    await prefs.setInt(_connectCount, next);
    return next;
  }

  Future<bool> getReviewAsked() async => (await _p).getBool(_reviewAsked) ?? false;
  Future<void> setReviewAsked() async {
    await (await _p).setBool(_reviewAsked, true);
  }
}
