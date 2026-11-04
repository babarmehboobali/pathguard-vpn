import 'dart:ui' show PlatformDispatcher;
import 'dart:async';
import 'package:flutter/material.dart';
import 'app.dart';
import 'services/consent_service.dart';
import 'services/ads_service.dart';
import 'services/update_service.dart';
import 'services/crash_service.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      CrashService.instance.recordFlutterError(details);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashService.instance.recordError(error, stack);
      return true;
    };
    runApp(const PathGuardApp());
    unawaited(_initBackground());
  }, (error, stack) {
    CrashService.instance.recordError(error, stack);
  });
}

Future<void> _initBackground() async {
  try {
    await ConsentService().requestUmpConsent().timeout(const Duration(seconds: 8));
  } catch (_) {}
  try {
    await AdsService.instance.initialize().timeout(const Duration(seconds: 10));
  } catch (_) {}
  try {
    await UpdateService().checkAndUpdateImmediate().timeout(const Duration(seconds: 5));
  } catch (_) {}
}
