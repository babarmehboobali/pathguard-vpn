import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ads_config.dart';
import '../services/ads_service.dart';
import '../services/premium_service.dart';
import '../services/remote_config_service.dart';

/// Anchored adaptive banner.
///
/// Hides itself while the user has ad-free time from a rewarded video, and
/// loads again automatically the moment that time runs out.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _banner;
  bool _loaded = false;
  bool _loading = false;

  bool get _shouldShow =>
      AdsService.instance.canShowAds &&
      !PremiumService.isAdFreeNow &&
      RemoteConfigService.instance.bannerEnabled;

  @override
  void initState() {
    super.initState();
    PremiumService.changes.addListener(_sync);
    AdsService.instance.ready.addListener(_sync);
    RemoteConfigService.instance.version.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted) return;
    if (_shouldShow) {
      if (_banner == null && !_loading) _load();
    } else {
      _disposeBanner();
      setState(() {});
    }
  }

  Future<void> _load() async {
    _loading = true;
    final width = MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null || !_shouldShow) {
      _loading = false;
      return;
    }
    _banner = BannerAd(
      adUnitId: AdsConfig.effectiveBannerId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _loading = false;
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _banner = null;
          _loading = false;
          if (mounted) setState(() => _loaded = false);
        },
      ),
    )..load();
  }

  void _disposeBanner() {
    _banner?.dispose();
    _banner = null;
    _loaded = false;
    _loading = false;
  }

  @override
  void dispose() {
    PremiumService.changes.removeListener(_sync);
    AdsService.instance.ready.removeListener(_sync);
    RemoteConfigService.instance.version.removeListener(_sync);
    _disposeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (!_loaded || banner == null || !_shouldShow) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: banner.size.width.toDouble(),
        height: banner.size.height.toDouble(),
        child: AdWidget(ad: banner),
      ),
    );
  }
}
