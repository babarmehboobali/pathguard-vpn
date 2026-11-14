// Renders real app screens to PNG for the Play Store listing.
// Run (CI does this): flutter test screenshots/screenshot_test.dart
// Output: build/screenshots/*.png (1080x2400).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pathguard_vpn/l10n/l10n.dart';
import 'package:pathguard_vpn/screens/appearance_screen.dart';
import 'package:pathguard_vpn/screens/countries_screen.dart';
import 'package:pathguard_vpn/screens/home_screen.dart';
import 'package:pathguard_vpn/screens/settings_screen.dart';
import 'package:pathguard_vpn/screens/tools_screen.dart';
import 'package:pathguard_vpn/services/locale_service.dart';
import 'package:pathguard_vpn/services/vpngate_service.dart';
import 'package:pathguard_vpn/services/theme_service.dart';
import 'package:pathguard_vpn/theme/app_theme.dart';

const _outDir = 'build/screenshots';
final _shotKey = GlobalKey();

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final p in paths) {
    final f = File(p);
    if (f.existsSync()) {
      final bytes = f.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      any = true;
    }
  }
  if (any) await loader.load();
}

void _mockChannels(WidgetTester tester, {Map<String, dynamic>? vpnEvent}) {
  final m = tester.binding.defaultBinaryMessenger;
  const silent = <String>[
    'pathguard/vpn',
    'dev.fluttercommunity.plus/connectivity',
    'plugins.flutter.io/google_mobile_ads',
    'plugins.flutter.io/google_mobile_ads/ump',
    'dev.britannio.in_app_review',
    'plugins.flutter.io/path_provider',
    'de.ffuf.in_app_update/methods',
    'dev.fluttercommunity.plus/share',
    'flutter.baseflow.com/permissions/methods',
    'miguelruivo.flutter.plugins.filepicker',
  ];
  for (final name in silent) {
    m.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
  }
  m.setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    MockStreamHandler.inline(onListen: (_, sink) => sink.success(<String>['wifi'])),
  );
  m.setMockStreamHandler(
    const EventChannel('pathguard/vpn/events'),
    MockStreamHandler.inline(onListen: (_, sink) {
      if (vpnEvent != null) sink.success(vpnEvent);
    }),
  );
}

Future<void> _style(String mode, String accent, String layout) async {
  await ThemeService.instance.update(mode: mode, accent: accent, layout: layout, haptics: false);
  AppTheme.apply(mode: mode, accent: accent);
}

Widget _app(Widget home, {String lang = 'en'}) {
  return RepaintBoundary(
    key: _shotKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.current,
      locale: Locale(lang),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  // Let real async work (asset loading) finish, then repaint.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(hours: 3));
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

final _connected = <String, dynamic>{
  'state': 'connected',
  'mode': 'free',
  'countryCode': 'JP',
  'countryName': 'Japan',
  'ip': '219.100.37.112',
  'ping': 42,
  'bytesIn': 184 * 1024 * 1024,
  'bytesOut': 23 * 1024 * 1024,
};

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    final mf = '$root/bin/cache/artifacts/material_fonts';
    await _loadFont('Roboto', <String>[
      '$mf/Roboto-Regular.ttf',
      '$mf/Roboto-Medium.ttf',
      '$mf/Roboto-Bold.ttf',
      '$mf/Roboto-Light.ttf',
      '$mf/Roboto-Black.ttf',
    ]);
    await _loadFont('MaterialIcons', <String>['$mf/MaterialIcons-Regular.otf']);
    const noto = '/usr/share/fonts/truetype/noto';
    await _loadFont('NotoSansArabic', <String>['$noto/NotoSansArabic-Regular.ttf', '$noto/NotoSansArabic-Bold.ttf']);
    await _loadFont('NotoColorEmoji', <String>['$noto/NotoColorEmoji.ttf']);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'vpn_consent_accepted': true,
      'intro_done': true,
    });
    await ThemeService.instance.load();
  });

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget Function() screen, {
    String mode = 'dark',
    String accent = 'aurora',
    String layout = 'classic',
    String lang = 'en',
    Map<String, dynamic>? vpn,
  }) async {
    _phone(tester);
    _mockChannels(tester, vpnEvent: vpn);
    await _style(mode, accent, layout);
    await LocaleService.instance.set(lang);
    await tester.pumpWidget(_app(screen(), lang: lang));
    await _settle(tester);
    await _capture(tester, name);
    await _finish(tester);
  }

  testWidgets('01 home connected', (t) => shot(t, '01_home_connected', () => const HomeScreen(), vpn: _connected));
  testWidgets('02 home idle', (t) => shot(t, '02_home_idle', () => const HomeScreen()));
  testWidgets('03 compact emerald', (t) => shot(t, '03_layout_compact', () => const HomeScreen(), accent: 'emerald', layout: 'compact', vpn: _connected));
  testWidgets('04 minimal light', (t) => shot(t, '04_light_minimal', () => const HomeScreen(), mode: 'light', accent: 'ocean', layout: 'minimal', vpn: _connected));
  testWidgets('05 countries', (t) => shot(t, '05_countries', () => CountriesScreen(initialServers: VpnGateService.parseCsvForTest(File('assets/vpngate_snapshot.csv').readAsStringSync()))));
  testWidgets('06 appearance', (t) => shot(t, '06_appearance', () => const AppearanceScreen(), accent: 'sunset'));
  testWidgets('07 tools', (t) => shot(t, '07_tools', () => const ToolsScreen()));
  testWidgets('08 settings', (t) => shot(t, '08_settings', () => const SettingsScreen()));
  testWidgets('09 arabic', (t) => shot(t, '09_arabic', () => const HomeScreen(), lang: 'ar', accent: 'gold', vpn: _connected));
}
