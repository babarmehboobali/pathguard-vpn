# PathGuard VPN 1.0.5 (+1005) — upgrade notes

Built on the **1.0.4+1004** source. Everything from 1.0.4 is kept: production AdMob IDs, SA/PK pinned countries,
alias search, no silent cross-country fallback, the Tor ExitNodes fix, the OpenVPN foreground-service fix, targetSdk 36.

## Ads (banner + 6-hour rewarded)
- **Banner**: anchored adaptive banner at the bottom of the Home, Countries and Tools screens.
- **First connection after each app open**: once the VPN connects, the app shows a choice:
  "Remove ads for 6 hours?" with **Watch video** / **No thanks**. The video plays only after the user taps Watch,
  as AdMob requires for rewarded ads. It never plays by itself.
- Ad-free time is granted **only** in `onUserEarnedReward`. Each video adds +6 h, stacking up to a 24 h cap.
- While ad-free, the banner and interstitials are hidden. The banner **comes back by itself** when the time runs out.
- Home has an "Ad-free" pill: "Remove ads 6h", then "Ad-free: 5h 12m +6h". If no video is loaded it is greyed out
  and shows "No ad available, try later".
- Interstitial: paced (every 3rd action, at least 60 s apart). Never shown while ad-free or on top of another ad.
- Files: `lib/services/ads_service.dart`, `lib/services/premium_service.dart`, `lib/widgets/banner_ad_widget.dart`,
  `lib/widgets/reward_prompt.dart`.

## 20 languages (with right-to-left support)
English, العربية, اردو, فارسی, Türkçe, Русский, Bahasa Indonesia, हिन्दी, বাংলা, Español, Português, Français,
Deutsch, 简体中文, Tiếng Việt, ไทย, 한국어, 日本語, Bahasa Melayu, Italiano.
- Follows the phone's language by default. Can be changed in Settings → Language, or from the 🌐 button on the
  disclosure screen.
- Arabic, Urdu and Persian are laid out right-to-left automatically.
- Strings are in `assets/l10n/<code>.json` (144 keys each). The engine is `lib/l10n/l10n.dart`, used as `context.tr('key')`.
  A missing key falls back to English, so the UI can't crash on a missing translation.
- `test/l10n_assets_test.dart` checks that every language has every key and the same placeholders.

## New features
| Feature | Where |
|---|---|
| **Smart Connect**: if every Free server fails, it switches to Stealth automatically (toggle in Settings) | Home |
| **Auto-reconnect** when the tunnel drops or the network comes back (up to 3 tries, with back-off) | Home |
| **Auto-connect on app open** (this setting existed but did nothing before; it now works) | Settings |
| **Safe browsing DNS**: Cloudflare malware/phishing or family filter, on Free and Stealth. No ad blocking, because Play's VpnService policy forbids it | Settings |
| **Kill switch**: opens Android "Always-on VPN + Block connections without VPN" | Settings |
| **Favorites ⭐ and Recent servers**, with "Online now / May be offline" | Countries |
| **Auto (fastest)** option at the top of the server list | Countries |
| **My IP & location** check (ipwho.is, falling back to ipify) | Tools |
| **Speed test**: ping / download / upload (Cloudflare speed endpoints) | Tools |
| **Data usage**: today / 7 days / 30 days, stored only on the device | Tools |
| **Import your own .ovpn** ("My servers"), connects with no fallback to other servers | Tools |
| **In-app rating prompt** after the 3rd good connection, plus Rate / Share entries | Settings |
| Settings and Tools are reachable from Home (1.0.2 had no button to open Settings) | Home toolbar |

## More countries
- Tor and Stealth exit list: **33 countries that connect reliably**, up from 31 real ones in 1.0.4 (Moldova and Ukraine
  added, SA/PK removed because they have almost no Tor exits). 7 countries with fewer relays are labelled "may be slower".
- The country counts in the Home subtitle are now calculated from the list, not hard-coded.
- Free (VPN Gate) countries depend on volunteers who are online. Choosing a country now only falls back to other
  servers **in that same country**, matching the 1.0.4 "no silent cross-country fallback" rule.

## Look & feel (new)
- **Themes**: Dark, Light, AMOLED black, or follow the phone setting. Colours switch instantly without
  disconnecting or leaving the screen.
- **6 colour styles**: Aurora, Emerald, Ocean, Sunset, Rose and Gold. They change buttons, gradients and highlights.
- **3 home layouts**:
  - **Classic**: modes, server card and stats.
  - **Compact**: smaller button plus quick-connect chips for your favourite and recent servers.
  - **Minimal**: one big button and the server name.
- All of this lives in Settings → Appearance, with a small preview of each layout. On small phones every
  layout scrolls instead of overflowing.

## More free tools (new)
- **Live speed**: the current download/upload speed is shown under Down/Up while connected.
- **Session summary** after you disconnect: location, duration, data down and up. The paced full-screen ad
  comes after this sheet, never on top of it.
- **Connection history**: the last 30 sessions, stored only on the phone (Tools → Data usage → History).
- **Pause VPN** for 5, 15, 30 or 60 min, then it reconnects automatically. There's also a "Resume now" button.
- **Auto-off timer** that disconnects after 15, 30, 60 or 120 min.
- **Haptic feedback** on connect and disconnect (can be turned off).
- **Help & FAQ**: 5 short answers to the most common problems, in all 20 languages.
- **Fix**: data usage was not recorded when the user tapped Disconnect. Every session is now recorded once.

## Earning upgrades (ads only, no purchases)
- **App Open ads**: a full-screen ad shown when the user *comes back* to the app after at least 30 s away.
  It never shows on first launch, never within 4 min of another full-screen ad, and never while ad-free.
  It also never shows after a screen the app itself opened (VPN permission, VPN settings, file picker,
  share, rating). Ads expire after 4 h, as AdMob requires.
  **Switched off until you paste your App Open unit ID into `lib/config/ads_config.dart` (`appOpenId`).**
- **Remote settings file**: `https://smartpathapps.com/apps/pathguard-config.json` (template in
  `docs/pathguard-config.json`). It lets you change, without publishing an update:
  - how often interstitials show (every N actions, minimum gap)
  - App Open on/off and its gap
  - the first-connect video offer on/off
  - the banner on/off
  - the Smart Connect default
  - a minimum app build (shows an "update" notice)
  - an announcement card on Home, written in any of the 20 languages

  Every number is clamped to a policy-safe minimum, so a typo can't make ads too aggressive. If the file is
  missing, the built-in defaults are used.
- No in-app purchases. The app stays free with ads.

## Quality: only things that work are shown
- **Free servers that fail the connection test are hidden** from the list and skipped when connecting, so
  connecting is faster and fails less. If every server in a country fails the test, the app still tries them
  as a last resort.
- **Saudi Arabia / Pakistan** appear at the top of the Free list only while they have a working server.
- **Tor/Stealth countries trimmed to 33 with enough Tor exits to connect reliably.** Saudi Arabia, Pakistan
  and other countries with almost no Tor exits were removed. A user whose saved exit country was removed goes
  back to "Fastest / any country".

## Setup checklist (you)
1. **AdMob** → Apps → PathGuard VPN → Ad units → **Add ad unit → App open** → copy the ID into
   `AdsConfig.appOpenId`. This step is optional: without it, App Open ads simply stay off.
2. **Website**: upload `docs/pathguard-config.json` as `https://smartpathapps.com/apps/pathguard-config.json`.
   This step is optional: without it, the defaults are used.
3. **Store listing**: paste the 20 translations from `docs/PathGuard_store_listing_20_languages.md`.
4. **Privacy policy**: add one line saying the app downloads a settings file from smartpathapps.com.
5. Build, then check Play Console → App bundle explorer → "Supports 16 KB".

## Native change
- `VpnPlugin.kt`: new `openVpnSettings` method (`Settings.ACTION_VPN_SETTINGS`), used by the kill-switch entry.

## New dependencies (pubspec.yaml)
- `flutter_localizations` (SDK), `in_app_review: ^2.0.10`, `file_picker: ^10.3.0`
- `intl` changed to `any`, because `flutter_localizations` pins its version.
- Version is now `1.0.5+1005`. `versionCode` is 1005 in `android/app/build.gradle.kts`.

## Build
```bash
flutter pub get
flutter test
flutter build appbundle --release
flutter build apk --release --target-platform android-arm64
```

## Merged from 1.0.4 (kept as is)
- `lib/config/ads_config.dart`: production IDs (App `~4943613486`, banner `/4452658893`, interstitial `/1826495550`,
  rewarded `/9513413885`). Release `admobAppId` in `build.gradle.kts` is unchanged.
- SA and PK are pinned at the top of the Free list while they have a working server, and are searchable by alias: KSA, Saudi, السعودية, Pak, پاکستان.
- A chosen country (Free or Stealth) never silently falls back to another country. Smart Connect's switch to
  Stealth only happens in Auto mode.
- Native 1.0.4 fixes (`TorEngine.kt`, `NotificationHelper.kt`, `VpnTileService.kt`, `gradle.properties`) are untouched.
- The 1.0.4 "Remove ads +6h" button is replaced by the new ad-free pill. It follows the same rules: +6 h per finished
  video, stacking, 24 h cap, greyed out with "No ad available, try later" when no video is loaded.
- One deliberate difference: during the 5 Free connection attempts you can tap the button to cancel. In 1.0.4 the
  button ignored taps until all attempts finished, which could take up to about 80 seconds.
- Tests: the 1.0.4 `countries_search_test.dart` and its +6h/24h premium test are kept, and new tests were added.
