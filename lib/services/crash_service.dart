import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CrashService {
  CrashService._();
  static final CrashService instance = CrashService._();

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/crash_log.txt');
  }

  Future<void> recordError(Object error, StackTrace stack) async {
    final file = await _file;
    final msg = '${DateTime.now().toIso8601String()}\n$error\n$stack\n\n';
    await file.writeAsString(msg, mode: FileMode.append);
  }

  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    await recordError(details.exception, details.stack ?? StackTrace.empty);
  }

  Future<String> readLog() async {
    final file = await _file;
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Future<void> clear() async {
    final file = await _file;
    if (await file.exists()) await file.delete();
  }

  Future<void> share() async {
    final text = await readLog();
    if (text.isEmpty) return;
    await Share.share(text, subject: 'PathGuard crash report');
  }
}
