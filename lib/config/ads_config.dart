class AdsConfig {
  // Production AdMob IDs (PathGuard). Debug builds use Google test IDs below.
  static const String admobAppId = 'ca-app-pub-1235513372019694~4943613486';
  static const String bannerId = 'ca-app-pub-1235513372019694/4452658893';
  static const String interstitialId = 'ca-app-pub-1235513372019694/1826495550';
  static const String rewardedId = 'ca-app-pub-1235513372019694/9513413885';

  /// App Open ad unit. PASTE YOUR ID HERE (AdMob → Apps → PathGuard → Ad units →
  /// Add ad unit → App open). While empty, App Open ads stay off in release builds.
  static const String appOpenId = '';

  // Google official test IDs (used in debug)
  static const String testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const String testRewardedId = 'ca-app-pub-3940256099942544/5224354917';
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String testAppOpenId = 'ca-app-pub-3940256099942544/9257395921';

  static String get effectiveBannerId =>
      const bool.fromEnvironment('dart.vm.product') ? bannerId : testBannerId;

  static String get effectiveInterstitialId =>
      const bool.fromEnvironment('dart.vm.product') ? interstitialId : testInterstitialId;

  static String get effectiveRewardedId =>
      const bool.fromEnvironment('dart.vm.product') ? rewardedId : testRewardedId;

  static String get effectiveAppId =>
      const bool.fromEnvironment('dart.vm.product') ? admobAppId : testAppId;

  /// Empty string = App Open ads disabled.
  static String get effectiveAppOpenId =>
      const bool.fromEnvironment('dart.vm.product') ? appOpenId : testAppOpenId;
}
