import 'dart:async';
import 'package:in_app_update/in_app_update.dart';

class UpdateService {
  Future<void> checkAndUpdateImmediate() async {
    try {
      final info = await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 4));
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate().timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // Sideloaded or no Play Store — ignore
    }
  }
}
