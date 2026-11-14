import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ad-free time earned from rewarded videos.
///
/// Rules (SmartPath standard):
///  * each finished rewarded video grants +6 h without banner / interstitial ads
///  * time stacks, capped at 24 h from "now"
///  * time is granted ONLY from the earned-reward callback (never for free)
class PremiumService {
  static const String _expiryKey = 'premium_expiry';
  static const Duration rewardStep = Duration(hours: 6);
  static const Duration maxStack = Duration(hours: 24);

  /// Epoch-ms until which ads are hidden (0 = ads on). Shared app-wide so the
  /// banner and the ad-free chip react instantly, and again when time runs out.
  static final ValueNotifier<int> adFreeUntil = ValueNotifier<int>(0);
  /// Fires when the ad-free state changes.
  static Listenable get changes => adFreeUntil;

  static Timer? _expiryTimer;
  static bool _loaded = false;

  static bool get isAdFreeNow =>
      DateTime.now().millisecondsSinceEpoch < adFreeUntil.value;

  static Duration get remainingNow {
    final ms = adFreeUntil.value - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? Duration(milliseconds: ms) : Duration.zero;
  }

  /// True when another video would add less than one minute (already at cap).
  static bool get isAtCapNow => remainingNow >= maxStack - const Duration(minutes: 1);

  static void _apply(int expiry) {
    final now = DateTime.now().millisecondsSinceEpoch;
    adFreeUntil.value = expiry > now ? expiry : 0;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (expiry > now) {
      _expiryTimer = Timer(Duration(milliseconds: expiry - now + 500), () => _apply(0));
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _apply(prefs.getInt(_expiryKey) ?? 0);
    _loaded = true;
  }

  Future<void> _save(int expiry) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_expiryKey, expiry);
    _loaded = true;
    _apply(expiry);
  }

  Future<bool> isPremium() async {
    await load();
    return isAdFreeNow;
  }

  Future<Duration> remaining() async {
    await load();
    return remainingNow;
  }

  Future<bool> isAtCap() async {
    await load();
    return isAtCapNow;
  }

  /// Stacks [duration] onto any remaining ad-free time, capped at [maxStack]
  /// from now (same behaviour as 1.0.4).
  Future<void> grantPremium(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = prefs.getInt(_expiryKey) ?? 0;
    final base = current > now ? current : now;
    var next = base + duration.inMilliseconds;
    final cap = now + maxStack.inMilliseconds;
    if (next > cap) next = cap;
    await _save(next);
  }

  /// Adds [rewardStep] (+6 h) on top of any remaining time, capped at [maxStack].
  /// Returns false if the user was already at the cap.
  Future<bool> addRewardTime() async {
    await load();
    if (isAtCapNow) return false;
    await grantPremium(rewardStep);
    return true;
  }

  /// Clears the ad-free window.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_expiryKey);
    _apply(0);
  }
}
