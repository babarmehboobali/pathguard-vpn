class AdsConfig {
  // Replace these with your real AdMob IDs before release.
  // Debug builds automatically use Google test IDs.
  static const String admobAppId = 'ADMOB_APP_ID';
  static const String bannerId = 'BANNER_ID';
  static const String interstitialId = 'INTERSTITIAL_ID';
  static const String rewardedId = 'REWARDED_ID';

  // Google official test IDs (used in debug)
  static const String testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const String testRewardedId = 'ca-app-pub-3940256099942544/5224354917';
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';

  static String get effectiveBannerId =>
      const bool.fromEnvironment('dart.vm.product') ? bannerId : testBannerId;

  static String get effectiveInterstitialId =>
      const bool.fromEnvironment('dart.vm.product') ? interstitialId : testInterstitialId;

  static String get effectiveRewardedId =>
      const bool.fromEnvironment('dart.vm.product') ? rewardedId : testRewardedId;

  static String get effectiveAppId =>
      const bool.fromEnvironment('dart.vm.product') ? admobAppId : testAppId;
}
