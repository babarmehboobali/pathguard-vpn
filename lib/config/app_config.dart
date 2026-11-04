class AppConfig {
  static const bool enableWarp = false; // feature flag – set true only if WARP is fully implemented
  static const int consentVersion = 1;
  static const String privacyPolicyUrl = 'https://example.com/privacy'; // replace
  static const String githubUrl = 'https://github.com/example/pathguard-vpn'; // replace
  static const String licensesUrl = 'https://example.com/licenses'; // replace

  static const List<String> torExitCountries = [
    'us', 'de', 'nl', 'gb', 'fr', 'ca', 'se', 'ch', 'fi', 'no',
    'at', 'pl', 'ro', 'cz', 'es', 'it', 'jp', 'sg', 'in', 'au',
    'br', 'kr', 'mx', 'tr', 'za', 'any'
  ];
}
