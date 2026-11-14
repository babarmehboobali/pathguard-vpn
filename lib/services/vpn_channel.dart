import 'dart:async';
import 'package:flutter/services.dart';
import '../models/vpn_state.dart';
import 'ads_service.dart';
import 'crash_service.dart';

class VpnChannel {
  static const MethodChannel _method = MethodChannel('pathguard/vpn');
  static const EventChannel _event = EventChannel('pathguard/vpn/events');

  VpnState _current = const VpnState();

  Stream<VpnState> get stateStream =>
      _event.receiveBroadcastStream().map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        _current = VpnState.fromMap(map, previous: _current);
        return _current;
      });

  Future<bool> prepare() async {
    // The VPN permission dialog sends the app to background briefly.
    AdsService.instance.suppressAppOpen();
    try {
      final result = await _method.invokeMethod<bool>('prepare');
      await CrashService.instance.recordError('channel prepare -> $result', StackTrace.current);
      return result ?? false;
    } catch (e) {
      await CrashService.instance.recordError('channel prepare error: $e', StackTrace.current);
      return false;
    }
  }

  Future<void> connect({
    required String mode,
    String? config,
    String? countryCode,
    String? serverIp,
    List<String>? disallowedApps,
    bool preferUdp = true,
  }) async {
    await CrashService.instance.recordError('channel connect mode=$mode', StackTrace.current);
    await _method.invokeMethod('connect', {
      'mode': mode,
      'config': config,
      'countryCode': countryCode,
      'serverIp': serverIp,
      'disallowedApps': disallowedApps,
      'preferUdp': preferUdp,
    });
  }

  Future<void> disconnect() async {
    await CrashService.instance.recordError('channel disconnect', StackTrace.current);
    await _method.invokeMethod('disconnect');
  }

  Future<void> setSplitTunnel(List<String> disallowed) async {
    await _method.invokeMethod('setSplitTunnel', {'disallowed': disallowed});
  }

  /// Opens Android VPN settings (Always-on VPN / Block connections without VPN).
  Future<bool> openVpnSettings() async {
    AdsService.instance.suppressAppOpen(const Duration(minutes: 5));
    try {
      return await _method.invokeMethod<bool>('openVpnSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, String>>> listInstalledApps() async {
    final result = await _method.invokeMethod<List<dynamic>>('listInstalledApps');
    if (result == null) return <Map<String, String>>[];
    return result.map((e) => Map<String, String>.from(e as Map)).toList();
  }
}

