import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/ads_config.dart';
import 'premium_service.dart';

class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  final PremiumService _premium = PremiumService();
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  int _actionCount = 0;
  DateTime? _lastInterstitial;
  bool _canRequestAds = false;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    if (_canRequestAds && !(await _premium.isPremium())) {
      _loadInterstitial();
      _loadRewarded();
    }
    _initialized = true;
  }

  bool get canShowAds => _canRequestAds && _initialized;

  Future<bool> isPremium() => _premium.isPremium();

  Future<void> onUserAction() async {
    if (await isPremium() || !_initialized) return;
    _actionCount++;
    final now = DateTime.now();
    final enoughTime = _lastInterstitial == null ||
        now.difference(_lastInterstitial!).inSeconds >= 60;
    if (_actionCount >= 3 && enoughTime && _interstitial != null) {
      _interstitial!.show();
      _lastInterstitial = now;
      _actionCount = 0;
      _loadInterstitial();
    }
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdsConfig.effectiveInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: AdsConfig.effectiveRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  Future<bool> showRewardedForPremium() async {
    if (!_initialized || _rewarded == null) {
      _loadRewarded();
      return false;
    }
    final completer = Completer<bool>();
    _rewarded!.show(onUserEarnedReward: (ad, reward) async {
      await _premium.grantPremium(const Duration(minutes: 60));
      completer.complete(true);
    });
    _rewarded!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewarded = null;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewarded = null;
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    return completer.future;
  }

  void dispose() {
    _interstitial?.dispose();
    _rewarded?.dispose();
  }
}
