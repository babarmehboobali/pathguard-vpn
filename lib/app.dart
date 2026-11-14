import 'screens/intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/l10n.dart';
import 'services/locale_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'screens/consent_screen.dart';
import 'screens/home_screen.dart';
import 'services/consent_service.dart';
import 'services/crash_service.dart';

class PathGuardApp extends StatefulWidget {
  const PathGuardApp({super.key});

  @override
  State<PathGuardApp> createState() => _PathGuardAppState();
}

class _PathGuardAppState extends State<PathGuardApp> with WidgetsBindingObserver {
  bool _introDone = false;
  bool _checked = false;
  bool _accepted = false;
  String? _crashLog;

  @override
  void initState() {
    super.initState();
    _applyTheme();
    ThemeService.instance.revision.addListener(_onThemeChanged);
    WidgetsBinding.instance.addObserver(this);
    ErrorWidget.builder = (details) => Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Text(
          'Something went wrong\n${details.exception}',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
    _check();
  }

  Future<void> _check() async {
    final accepted = await ConsentService().hasAcceptedVpnConsent();
    final log = await CrashService.instance.readLog();
    if (mounted) {
      setState(() {
        _accepted = accepted;
        _checked = true;
        _crashLog = log.isNotEmpty ? log : null;
      });
    }
  }

  void _showCrashDialog() {
    if (_crashLog == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('crash_report')),
        content: SingleChildScrollView(child: Text(_crashLog!)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _crashLog!));
              Navigator.pop(ctx);
            },
            child: Text(ctx.tr('copy')),
          ),
          TextButton(
            onPressed: () async {
              await CrashService.instance.share();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(ctx.tr('share')),
          ),
          TextButton(
            onPressed: () async {
              await CrashService.instance.clear();
              if (mounted) setState(() => _crashLog = null);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(ctx.tr('clear')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_crashLog != null && _checked && _introDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showCrashDialog());
    }
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleService.instance.locale,
      builder: (context, chosen, _) => _buildApp(chosen),
    );
  }

  @override
  void dispose() {
    ThemeService.instance.revision.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Resolves "system" to the phone's light/dark setting and applies the palette.
  void _applyTheme() {
    final ts = ThemeService.instance;
    var mode = ts.mode;
    if (mode == 'system') {
      final b = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      mode = b == Brightness.light ? 'light' : 'dark';
    }
    AppTheme.apply(mode: mode, accent: ts.accent);
    SystemChrome.setSystemUIOverlayStyle(
      AppTheme.isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
    );
  }

  @override
  void didChangePlatformBrightness() {
    if (ThemeService.instance.mode == 'system') _onThemeChanged();
  }

  /// Re-applies colours everywhere WITHOUT recreating screens, so the VPN
  /// state, open pages and scroll positions are kept.
  void _onThemeChanged() {
    _applyTheme();
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void rebuild(Element el) {
        el.markNeedsBuild();
        el.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    });
  }

  static const List<LocalizationsDelegate<dynamic>> _delegates = <LocalizationsDelegate<dynamic>>[
    L10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  Widget _buildApp(Locale? chosen) {
    if (!_introDone) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: chosen,
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: _delegates,
        localeResolutionCallback: (device, _) => L10n.resolve(device),
        home: IntroScreen(onDone: () => setState(() => _introDone = true)),
      );
    }
    return MaterialApp(
      title: 'PathGuard VPN',
      theme: AppTheme.current,
      debugShowCheckedModeBanner: false,
      locale: chosen,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: _delegates,
      localeResolutionCallback: (device, _) => L10n.resolve(device),
      home: !_checked
          ? Scaffold(
              backgroundColor: AppTheme.background,
              body: Center(child: CircularProgressIndicator()),
            )
          : _accepted
              ? const HomeScreen()
              : ConsentScreen(
                  onAccepted: () => setState(() => _accepted = true),
                  onDeclined: () => setState(() => _accepted = false),
                ),
    );
  }
}
