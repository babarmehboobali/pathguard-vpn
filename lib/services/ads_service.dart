import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ads_config.dart';
import 'premium_service.dart';
import 'remote_config_service.dart';

enum RewardResult { granted, notFinished, noAd, atCap }

/// Central ad controller: banner gating, paced interstitials, App Open ads and
/// the opt-in rewarded video that removes ads for 6 hours.
///
/// Policy notes:
///  * Rewarded ads are NEVER shown automatically — the app offers them
///    (Watch / No thanks) and plays only after the user taps Watch.
///  * App Open ads only appear when the user RETURNS to the app after being
///    away for a while — never on first launch, never right after another
///    full-screen ad, never after a system dialog the app itself opened
///    (VPN permission, VPN settings, file picker, share sheet, Play rating).
///  * No ads at all while ad-free (rewarded time).
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  final PremiumService _premium = PremiumService();
  RemoteConfigService get _cfg => RemoteConfigService.instance;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  AppOpenAd? _appOpen;
  DateTime? _appOpenLoadedAt;
  bool _interstitialLoading = false;
  bool _rewardedLoading = false;
  bool _appOpenLoading = false;
  Timer? _rewardedRetry;
  int _actionCount = 0;
  DateTime? _lastFullscreen;
  DateTime? _backgroundSince;
  DateTime? _suppressAppOpenUntil;
  bool _canRequestAds = false;
  bool _initialized = false;
  bool _offeredThisSession = false;
  bool _fullscreenShowing = false;
  StreamSubscription<AppState>? _appStateSub;

  /// True once the SDK is initialised and consent allows ad requests.
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  /// True while a rewarded video is loaded and can be shown.
  final ValueNotifier<bool> rewardedReady = ValueNotifier<bool>(false);

  Future<void> initialize() async {
    if (_initialized) return;
    await _premium.load();
    await MobileAds.instance.initialize();
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    _initialized = true;
    ready.value = _canRequestAds;
    PremiumService.changes.addListener(_onAdFreeChanged);
    if (_canRequestAds) {
      _loadRewarded();
      if (!PremiumService.isAdFreeNow) {
        _loadInterstitial();
        _loadAppOpen();
      }
      _listenAppState();
    }
  }

  bool get canShowAds => _canRequestAds && _initialized;

  bool get isRewardedReady => _rewarded != null;

  Future<bool> isPremium() => _premium.isPremium();

  void _onAdFreeChanged() {
    if (!PremiumService.isAdFreeNow && canShowAds) {
      _loadInterstitial();
      _loadAppOpen();
    }
  }

  bool get _recentFullscreen {
    final last = _lastFullscreen;
    return last != null &&
        DateTime.now().difference(last).inSeconds < _cfg.interstitialMinGapSec;
  }

  // ---------------------------------------------------------------- interstitial

  /// Paced interstitial: every Nth action, with a minimum gap; never while
  /// ad-free or while another full-screen ad is open.
  Future<void> onUserAction() async {
    if (!canShowAds || PremiumService.isAdFreeNow || _fullscreenShowing) return;
    _actionCount++;
    final ad = _interstitial;
    if (_actionCount >= _cfg.interstitialEveryActions && !_recentFullscreen && ad != null) {
      _interstitial = null;
      _actionCount = 0;
      _lastFullscreen = DateTime.now();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (_) => _fullscreenShowing = true,
        onAdDismissedFullScreenContent: (a) {
          _fullscreenShowing = false;
          _lastFullscreen = DateTime.now();
          a.dispose();
          _loadInterstitial();
        },
        onAdFailedToShowFullScreenContent: (a, _) {
          _fullscreenShowing = false;
          a.dispose();
          _loadInterstitial();
        },
      );
      await ad.show();
    }
  }

  void _loadInterstitial() {
    if (_interstitialLoading || _interstitial != null || !canShowAds) return;
    if (PremiumService.isAdFreeNow) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: AdsConfig.effectiveInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (_) {
          _interstitialLoading = false;
          _interstitial = null;
        },
      ),
    );
  }

  // -------------------------------------------------------------------- app open

  bool get _appOpenConfigured => AdsConfig.effectiveAppOpenId.isNotEmpty;

  void _loadAppOpen() {
    if (!_appOpenConfigured || !_cfg.appOpenEnabled) return;
    if (_appOpenLoading || _appOpen != null || !canShowAds || PremiumService.isAdFreeNow) return;
    _appOpenLoading = true;
    AppOpenAd.load(
      adUnitId: AdsConfig.effectiveAppOpenId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenLoading = false;
          _appOpen = ad;
          _appOpenLoadedAt = DateTime.now();
        },
        onAdFailedToLoad: (_) {
          _appOpenLoading = false;
          _appOpen = null;
        },
      ),
    );
  }

  void _listenAppState() {
    if (_appStateSub != null) return;
    AppStateEventNotifier.startListening();
    _appStateSub = AppStateEventNotifier.appStateStream.listen((state) {
      if (state == AppState.background) {
        _backgroundSince = DateTime.now();
      } else if (state == AppState.foreground) {
        _maybeShowAppOpen();
      }
    });
  }

  /// Call right before the app itself opens a system screen (VPN permission,
  /// settings, file picker, share sheet, rating) so returning from it does not
  /// trigger an App Open ad.
  void suppressAppOpen([Duration d = const Duration(minutes: 2)]) {
    _suppressAppOpenUntil = DateTime.now().add(d);
  }

  void _maybeShowAppOpen() {
    final since = _backgroundSince;
    _backgroundSince = null;
    if (!canShowAds || !_cfg.appOpenEnabled || PremiumService.isAdFreeNow) return;
    if (_fullscreenShowing || since == null) return;
    final now = DateTime.now();
    if (_suppressAppOpenUntil != null && now.isBefore(_suppressAppOpenUntil!)) return;
    if (now.difference(since).inSeconds < _cfg.appOpenMinBackgroundSec) return;
    final last = _lastFullscreen;
    if (last != null && now.difference(last).inSeconds < _cfg.appOpenMinGapSec) return;

    final ad = _appOpen;
    if (ad == null) {
      _loadAppOpen();
      return;
    }
    // App Open ads expire after 4 hours.
    if (_appOpenLoadedAt != null && now.difference(_appOpenLoadedAt!).inHours >= 4) {
      ad.dispose();
      _appOpen = null;
      _loadAppOpen();
      return;
    }
    _appOpen = null;
    _lastFullscreen = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _fullscreenShowing = true,
      onAdDismissedFullScreenContent: (a) {
        _fullscreenShowing = false;
        _lastFullscreen = DateTime.now();
        a.dispose();
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        _fullscreenShowing = false;
        a.dispose();
        _loadAppOpen();
      },
    );
    ad.show();
  }

  // -------------------------------------------------------------------- rewarded

  void _loadRewarded() {
    if (_rewardedLoading || _rewarded != null || !canShowAds) return;
    _rewardedLoading = true;
    _rewardedRetry?.cancel();
    RewardedAd.load(
      adUnitId: AdsConfig.effectiveRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoading = false;
          _rewarded = ad;
          rewardedReady.value = true;
        },
        onAdFailedToLoad: (_) {
          _rewardedLoading = false;
          _rewarded = null;
          rewardedReady.value = false;
          _rewardedRetry = Timer(const Duration(seconds: 60), _loadRewarded);
        },
      ),
    );
  }

  /// True only for the first successful connection after the app is opened,
  /// when ads are on and a rewarded video is ready. Marks the session as offered.
  bool takeFirstConnectOffer() {
    if (_offeredThisSession) return false;
    _offeredThisSession = true;
    return _cfg.firstConnectRewardOffer &&
        canShowAds &&
        !PremiumService.isAdFreeNow &&
        _rewarded != null;
  }

  /// Plays the rewarded video after the user tapped "Watch".
  /// Ad-free time is granted only inside onUserEarnedReward.
  Future<RewardResult> showRewardedForAdFree() async {
    final ad = _rewarded;
    if (!canShowAds || ad == null) {
      _loadRewarded();
      return RewardResult.noAd;
    }
    if (await _premium.isAtCap()) return RewardResult.atCap;

    _rewarded = null;
    rewardedReady.value = false;
    final completer = Completer<RewardResult>();
    Future<bool>? grant;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _fullscreenShowing = true,
      onAdDismissedFullScreenContent: (a) async {
        _fullscreenShowing = false;
        _lastFullscreen = DateTime.now();
        a.dispose();
        _loadRewarded();
        final granted = grant != null && await grant!;
        if (!completer.isCompleted) {
          completer.complete(granted ? RewardResult.granted : RewardResult.notFinished);
        }
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        _fullscreenShowing = false;
        a.dispose();
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(RewardResult.noAd);
      },
    );
    await ad.show(onUserEarnedReward: (_, __) {
      grant ??= _premium.addRewardTime();
    });
    return completer.future;
  }

  /// Kept for older call sites.
  Future<bool> showRewardedForPremium() async =>
      (await showRewardedForAdFree()) == RewardResult.granted;

  void dispose() {
    _rewardedRetry?.cancel();
    _appStateSub?.cancel();
    _interstitial?.dispose();
    _rewarded?.dispose();
    _appOpen?.dispose();
  }
}
