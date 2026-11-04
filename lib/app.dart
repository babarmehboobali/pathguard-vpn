import 'screens/intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _PathGuardAppState extends State<PathGuardApp> {
  bool _introDone = false;
  bool _checked = false;
  bool _accepted = false;
  String? _crashLog;

  @override
  void initState() {
    super.initState();
    ErrorWidget.builder = (details) => Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Text(
          'Something went wrong\n${details.exception}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
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
        title: const Text('Crash report'),
        content: SingleChildScrollView(child: Text(_crashLog!)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _crashLog!));
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () async {
              await CrashService.instance.share();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () async {
              await CrashService.instance.clear();
              if (mounted) setState(() => _crashLog = null);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Clear'),
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
    if (!_introDone) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: IntroScreen(onDone: () => setState(() => _introDone = true)),
      );
    }
    return MaterialApp(
      title: 'PathGuard VPN',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: !_checked
          ? const Scaffold(
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
