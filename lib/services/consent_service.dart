import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConsentService {
  static const String _vpnConsentKey = 'vpn_consent_accepted';
  static const String _vpnConsentVersionKey = 'vpn_consent_version';
  static const int currentConsentVersion = 1;

  Future<bool> hasAcceptedVpnConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(_vpnConsentKey) ?? false;
    final version = prefs.getInt(_vpnConsentVersionKey) ?? 0;
    return accepted && version >= currentConsentVersion;
  }

  Future<void> acceptVpnConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vpnConsentKey, true);
    await prefs.setInt(_vpnConsentVersionKey, currentConsentVersion);
  }

  Future<void> requestUmpConsent() async {
    final completer = Completer<void>();
    final params = ConsentRequestParameters();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        if (!completer.isCompleted) {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
              if (!completer.isCompleted) completer.complete();
            });
          } catch (_) {
            if (!completer.isCompleted) completer.complete();
          }
          if (!completer.isCompleted) completer.complete();
        }
      },
      (error) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future.timeout(const Duration(seconds: 8));
  }
}
