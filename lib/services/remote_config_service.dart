import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Remote settings fetched from a small JSON file on your website, so ad pacing
/// and features can be tuned WITHOUT publishing an app update.
///
/// File: https://smartpathapps.com/apps/pathguard-config.json (see docs/pathguard-config.json)
/// Every value is clamped to a policy-safe range, so a typo in the file can
/// never make ads more aggressive than AdMob / Play allow.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const String url = 'https://smartpathapps.com/apps/pathguard-config.json';
  static const String _cacheKey = 'remote_config_cache_v1';

  // ---- values (defaults = what ships in the app) ----
  bool bannerEnabled = true;
  int interstitialEveryActions = 3; // >= 2
  int interstitialMinGapSec = 60; // >= 45
  bool appOpenEnabled = true;
  int appOpenMinGapSec = 240; // >= 120 (also counts other full-screen ads)
  int appOpenMinBackgroundSec = 30; // >= 10
  bool firstConnectRewardOffer = true;
  bool smartFallbackDefault = true;
  int minSupportedBuild = 0; // builds below this see an "update" notice
  Map<String, String> announcement = const <String, String>{}; // lang -> text

  /// Notifies when fresh values are applied (e.g. to show an announcement).
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) _apply(cached);
    } catch (_) {}
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return;
      if (_apply(r.body)) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, r.body);
      }
    } catch (_) {
      // Offline or file missing: keep cached / default values.
    }
  }

  static int _int(Object? v, int fallback, {required int min, required int max}) {
    final n = v is num ? v.toInt() : int.tryParse('$v');
    if (n == null) return fallback;
    return n.clamp(min, max);
  }

  static bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

  /// Test hook.
  @visibleForTesting
  bool applyJson(String raw) => _apply(raw);

  bool _apply(String raw) {
    try {
      final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      bannerEnabled = _bool(j['banner_enabled'], bannerEnabled);
      interstitialEveryActions =
          _int(j['interstitial_every_actions'], interstitialEveryActions, min: 2, max: 20);
      interstitialMinGapSec =
          _int(j['interstitial_min_gap_sec'], interstitialMinGapSec, min: 45, max: 3600);
      appOpenEnabled = _bool(j['app_open_enabled'], appOpenEnabled);
      appOpenMinGapSec = _int(j['app_open_min_gap_sec'], appOpenMinGapSec, min: 120, max: 86400);
      appOpenMinBackgroundSec =
          _int(j['app_open_min_background_sec'], appOpenMinBackgroundSec, min: 10, max: 3600);
      firstConnectRewardOffer = _bool(j['first_connect_reward_offer'], firstConnectRewardOffer);
      smartFallbackDefault = _bool(j['smart_fallback_default'], smartFallbackDefault);
      minSupportedBuild = _int(j['min_supported_build'], minSupportedBuild, min: 0, max: 1 << 30);
      final a = j['announcement'];
      announcement = a is Map
          ? a.map((k, v) => MapEntry('$k', '$v')).cast<String, String>()
          : const <String, String>{};
      version.value++;
      return true;
    } catch (e) {
      debugPrint('RemoteConfig: ignored bad JSON ($e)');
      return false;
    }
  }

  /// Announcement in the user's language, falling back to English.
  String? announcementFor(String lang) {
    final t = announcement[lang] ?? announcement['en'];
    return (t == null || t.trim().isEmpty) ? null : t.trim();
  }
}
