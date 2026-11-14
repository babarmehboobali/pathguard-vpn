import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../models/server.dart';
import '../models/vpn_state.dart';
import '../services/ads_service.dart';
import '../services/crash_service.dart';
import '../services/favorites_service.dart';
import '../services/history_service.dart';
import '../services/imported_servers_service.dart';
import '../services/remote_config_service.dart';
import '../services/settings_service.dart';
import '../services/theme_service.dart';
import '../services/usage_service.dart';
import '../services/vpn_channel.dart';
import '../services/vpngate_service.dart';
import '../theme/app_theme.dart';
import '../utils/flag.dart';
import '../utils/ovpn_tools.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/connect_button.dart';
import '../widgets/reward_prompt.dart';
import '../widgets/stats_bar.dart';
import 'countries_screen.dart';
import 'settings_screen.dart';
import 'tools_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _prefLastMode = 'last_mode';
  static const String _prefLastServer = 'last_selected_server';
  static const String _prefLastTorCountryCode = 'last_tor_country_code';
  static const String _prefLastTorCountryName = 'last_tor_country_name';
  static const String _prefLastFreeCountry = 'last_free_country';

  static const int _maxAutoReconnects = 3;

  final VpnChannel _channel = VpnChannel();
  final VpnGateService _vpngate = VpnGateService();
  final AdsService _ads = AdsService.instance;
  final SettingsService _settings = SettingsService();

  StreamSubscription<VpnState>? _stateSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _uiTimer;
  Timer? _reconnectTimer;
  DateTime? _connectedSince;
  Duration _liveDuration = Duration.zero;

  VpnState _state = const VpnState();
  List<Server> _candidates = <Server>[];
  bool _loadingServers = true;
  String _mode = 'free';
  Server? _selected;

  /// Free mode: a country chosen without a specific server (e.g. pinned SA / PK).
  String? _selectedCountryCode;
  String? _selectedCountryName;
  bool _userPickedMode = false;
  String _torCountryCode = 'auto';
  String _torCountryName = '';
  bool _busy = false;
  bool _userCancelledFreeLoop = false;
  String _stageText = '';
  Completer<bool>? _freeAttemptCompleter;

  /// True between the user tapping Connect and the user tapping Disconnect.
  bool _userWantsConnection = false;
  int _reconnectAttempts = 0;
  bool _autoConnectChecked = false;
  bool _hadNetwork = true;
  Server? _connectingServer;
  int _sessionBytesIn = 0;
  int _sessionBytesOut = 0;

  // Session tracking (summary sheet + history)
  bool _sessionActive = false;
  DateTime? _sessionStart;
  String _sessionPlace = '';
  String _sessionMode = '';

  // Live speed (bytes per second, smoothed)
  int _lastIn = 0;
  int _lastOut = 0;
  DateTime? _lastSample;
  double _downRate = 0;
  double _upRate = 0;

  // Pause VPN / Auto-off timers (work while the app is running)
  DateTime? _pauseUntil;
  Timer? _pauseTimer;
  DateTime? _autoOffAt;
  Timer? _autoOffTimer;
  Timer? _countdownTicker;

  // Quick connect (favorites + recents) for the Compact layout
  List<Server> _quick = <Server>[];

  @override
  void initState() {
    super.initState();
    _restorePersistedSelection();
    _stateSub = _channel.stateStream.listen(_onState);
    _netSub = Connectivity().onConnectivityChanged.listen(_onNetwork);
    _loadQuick();

    _loadCandidates();
  }

  // ------------------------------------------------------------------ state

  void _onState(VpnState s) {
    if (!mounted) return;

    if (s.mode != null && s.mode!.isNotEmpty && s.mode != _mode) {
      _mode = s.mode!;
    }

    final wasConnected = _state.state == VpnConnectionState.connected;
    final nowConnected = s.state == VpnConnectionState.connected;

    if (_freeAttemptCompleter != null && !_freeAttemptCompleter!.isCompleted) {
      if (nowConnected && s.mode == 'free') {
        _freeAttemptCompleter!.complete(true);
      } else if (s.state == VpnConnectionState.error || s.state == VpnConnectionState.idle) {
        _freeAttemptCompleter!.complete(false);
      }
    }

    if (nowConnected) {
      _startDurationTickerIfNeeded();
      _sessionBytesIn = s.bytesIn;
      _sessionBytesOut = s.bytesOut;
      _sampleSpeed(s.bytesIn, s.bytesOut);
    } else {
      _stopDurationTicker();
      _resetSpeed();
    }

    setState(() {
      _state = s;
      if (s.state == VpnConnectionState.connecting &&
          s.errorMessage != null &&
          s.errorMessage!.isNotEmpty) {
        _stageText = s.errorMessage!;
      } else if (s.state != VpnConnectionState.connecting) {
        _stageText = '';
      }
      if (s.mode != null && s.mode!.isNotEmpty) {
        _mode = s.mode!;
      }
    });

    if (!wasConnected && nowConnected) {
      _onConnected();
    } else if (wasConnected && !nowConnected) {
      _endSession(userInitiated: false);
      if (s.state == VpnConnectionState.idle || s.state == VpnConnectionState.error) {
        _maybeAutoReconnect();
      }
    }
  }

  /// Runs once per successful connection.
  Future<void> _onConnected() async {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _sessionActive = true;
    _sessionStart = DateTime.now();
    _sessionMode = _mode;
    _sessionPlace = _serverRowTitle();
    _haptic(light: true);
    final server = _connectingServer;
    if (_mode == 'free' && server != null && !ImportedServersService.isImported(server)) {
      unawaited(FavoritesService.instance.addRecent(server));
    }

    // Ads: first connection after app open → offer (never auto-play) the 6 h reward.
    if (_ads.takeFirstConnectOffer()) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) await showRewardOffer(context);
    } else {
      await _ads.onUserAction();
    }

    // Ask for a Play rating once, after the 3rd good connection.
    final count = await _settings.incrementConnectCount();
    if (count == 3 && !await _settings.getReviewAsked()) {
      await _settings.setReviewAsked();
      try {
        final review = InAppReview.instance;
        if (await review.isAvailable()) await review.requestReview();
      } catch (_) {}
    }
  }

  /// Ends the current session once: saves usage + history and, after a
  /// user disconnect, shows the session summary (then a paced interstitial).
  Future<void> _endSession({required bool userInitiated}) async {
    if (!_sessionActive) {
      if (userInitiated) await _ads.onUserAction();
      return;
    }
    _sessionActive = false;
    _cancelAutoOff();
    final start = _sessionStart ?? DateTime.now();
    final seconds = DateTime.now().difference(start).inSeconds;
    final bytesIn = _sessionBytesIn;
    final bytesOut = _sessionBytesOut;
    _sessionBytesIn = 0;
    _sessionBytesOut = 0;
    unawaited(UsageService.instance.addSession(bytesIn: bytesIn, bytesOut: bytesOut));
    unawaited(HistoryService.instance.add(SessionRecord(
      start: start,
      seconds: seconds,
      bytesIn: bytesIn,
      bytesOut: bytesOut,
      mode: _sessionMode,
      place: _sessionPlace,
    )));
    if (userInitiated && seconds >= 10 && mounted) {
      await _showSessionSummary(seconds, bytesIn, bytesOut);
    }
    if (userInitiated) await _ads.onUserAction();
  }

  Future<void> _showSessionSummary(int seconds, int bytesIn, int bytesOut) async {
    String fmt(int s) {
      final d = Duration(seconds: s);
      final h = d.inHours.toString().padLeft(2, '0');
      final m = (d.inMinutes % 60).toString().padLeft(2, '0');
      final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$h:$m:$sec';
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        Widget row(IconData icon, String k, String v) => ListTile(
              dense: true,
              leading: Icon(icon, color: AppTheme.accentStart),
              title: Text(k, style: TextStyle(color: AppTheme.textSecondary)),
              trailing: Text(v,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_rounded, color: AppTheme.connected, size: 40),
                const SizedBox(height: 6),
                Text(ctx.tr('session_title'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                row(Icons.public_rounded, ctx.tr('session_place'), _sessionPlace),
                row(Icons.timer_outlined, ctx.tr('session_duration'), fmt(seconds)),
                row(Icons.arrow_downward_rounded, ctx.tr('stat_down'),
                    UsageService.formatBytes(bytesIn)),
                row(Icons.arrow_upward_rounded, ctx.tr('stat_up'),
                    UsageService.formatBytes(bytesOut)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(ctx.tr('ok')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ live speed

  void _sampleSpeed(int bytesIn, int bytesOut) {
    final now = DateTime.now();
    final last = _lastSample;
    if (last != null) {
      final dt = now.difference(last).inMilliseconds / 1000.0;
      if (dt >= 0.5) {
        final dIn = (bytesIn - _lastIn).clamp(0, 1 << 40) / dt;
        final dOut = (bytesOut - _lastOut).clamp(0, 1 << 40) / dt;
        _downRate = _downRate == 0 ? dIn : _downRate * 0.6 + dIn * 0.4;
        _upRate = _upRate == 0 ? dOut : _upRate * 0.6 + dOut * 0.4;
        _lastIn = bytesIn;
        _lastOut = bytesOut;
        _lastSample = now;
      }
    } else {
      _lastIn = bytesIn;
      _lastOut = bytesOut;
      _lastSample = now;
    }
  }

  void _resetSpeed() {
    _lastSample = null;
    _downRate = 0;
    _upRate = 0;
  }

  void _haptic({bool light = false}) {
    if (!ThemeService.instance.haptics) return;
    light ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
  }

  // ------------------------------------------------------ pause / auto-off

  void _ensureCountdown() {
    final need = _pauseUntil != null || _autoOffAt != null;
    if (need && _countdownTicker == null) {
      _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!need) {
      _countdownTicker?.cancel();
      _countdownTicker = null;
    }
  }

  String _left(DateTime until) {
    final d = until.difference(DateTime.now());
    final s = d.isNegative ? 0 : d.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<int?> _pickMinutes(String titleKey, List<int> options) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(ctx.tr(titleKey),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final m in options)
              ListTile(
                leading: Icon(Icons.timer_outlined, color: AppTheme.accentStart),
                title: Text(ctx.tr('minutes', {'n': m})),
                onTap: () => Navigator.pop(ctx, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Pause: disconnect now and reconnect automatically after N minutes.
  Future<void> _pause() async {
    final m = await _pickMinutes('pause_title', const [5, 15, 30, 60]);
    if (m == null || !mounted) return;
    _userWantsConnection = false;
    _reconnectTimer?.cancel();
    _cancelAutoOff();
    if (_sessionActive) await _endSession(userInitiated: false);
    await _channel.disconnect();
    _pauseUntil = DateTime.now().add(Duration(minutes: m));
    _pauseTimer?.cancel();
    _pauseTimer = Timer(Duration(minutes: m), _resumeFromPause);
    _ensureCountdown();
    if (mounted) setState(() {});
  }

  void _resumeFromPause() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _pauseUntil = null;
    _ensureCountdown();
    if (!mounted) return;
    _userWantsConnection = true;
    _reconnectAttempts = 0;
    _startConnection();
  }

  void _cancelPause() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _pauseUntil = null;
    _ensureCountdown();
  }

  /// Auto-off (sleep timer): disconnect after N minutes.
  Future<void> _setAutoOff() async {
    if (_autoOffAt != null) {
      setState(_cancelAutoOff);
      return;
    }
    final m = await _pickMinutes('autooff_title', const [15, 30, 60, 120]);
    if (m == null || !mounted) return;
    _autoOffAt = DateTime.now().add(Duration(minutes: m));
    _autoOffTimer?.cancel();
    _autoOffTimer = Timer(Duration(minutes: m), () {
      _autoOffAt = null;
      _ensureCountdown();
      if (mounted && _state.state == VpnConnectionState.connected) _toggle();
    });
    _ensureCountdown();
    setState(() {});
  }

  void _cancelAutoOff() {
    _autoOffTimer?.cancel();
    _autoOffTimer = null;
    _autoOffAt = null;
    _ensureCountdown();
  }

  // ------------------------------------------------------------ quick connect

  Future<void> _loadQuick() async {
    final favs = await FavoritesService.instance.favorites();
    final recent = await FavoritesService.instance.recents();
    final seen = <String>{};
    final out = <Server>[];
    for (final s in [...favs, ...recent]) {
      if (seen.add(FavoritesService.keyOf(s))) out.add(s);
      if (out.length >= 6) break;
    }
    if (mounted) setState(() => _quick = out);
  }

  Future<void> _quickConnect(Server s) async {
    await _applyPickedServer(s);
    await _toggle();
  }

  Future<void> _maybeAutoReconnect() async {
    if (!_userWantsConnection || _busy) return;
    if (!await _settings.getAutoReconnect()) return;
    if (_reconnectAttempts >= _maxAutoReconnects) return;
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    if (mounted) setState(() => _stageText = context.tr('reconnecting'));
    _reconnectTimer = Timer(delay, () {
      if (!mounted || !_userWantsConnection) return;
      if (_state.state == VpnConnectionState.connected ||
          _state.state == VpnConnectionState.connecting) {
        return;
      }
      _startConnection();
    });
  }

  void _onNetwork(List<ConnectivityResult> results) {
    final hasNet = results.any((r) => r != ConnectivityResult.none);
    final cameBack = hasNet && !_hadNetwork;
    _hadNetwork = hasNet;
    if (cameBack &&
        _userWantsConnection &&
        _state.state != VpnConnectionState.connected &&
        _state.state != VpnConnectionState.connecting) {
      _reconnectAttempts = 0;
      _maybeAutoReconnect();
    }
  }

  void _startDurationTickerIfNeeded() {
    if (_connectedSince == null) {
      _connectedSince = DateTime.now();
      _liveDuration = Duration.zero;
    }
    _uiTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedSince == null) return;
      setState(() => _liveDuration = DateTime.now().difference(_connectedSince!));
    });
  }

  void _stopDurationTicker() {
    _uiTimer?.cancel();
    _uiTimer = null;
    _connectedSince = null;
    _liveDuration = Duration.zero;
  }

  @override
  void dispose() {
    _stopDurationTicker();
    _reconnectTimer?.cancel();
    _stateSub?.cancel();
    _netSub?.cancel();
    _pauseTimer?.cancel();
    _autoOffTimer?.cancel();
    _countdownTicker?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------- persistence

  Future<void> _restorePersistedSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_prefLastMode);
      final savedServerJson = prefs.getString(_prefLastServer);
      final savedTorCode = prefs.getString(_prefLastTorCountryCode);
      final savedTorName = prefs.getString(_prefLastTorCountryName);
      final savedFreeCountry = prefs.getString(_prefLastFreeCountry);

      Server? restoredServer;
      if (savedServerJson != null && savedServerJson.isNotEmpty) {
        try {
          restoredServer =
              Server.fromJson(Map<String, dynamic>.from(jsonDecode(savedServerJson) as Map));
        } catch (_) {}
      }

      if (!mounted || _userPickedMode) return;
      setState(() {
        if (savedMode == 'free' ||
            savedMode == 'tor' ||
            savedMode == 'stealth' ||
            savedMode == 'warp') {
          _mode = savedMode!;
        }
        if (restoredServer != null) {
          _selected = restoredServer;
          _selectedCountryCode =
              restoredServer.countryShort.isNotEmpty ? restoredServer.countryShort : null;
        } else if (savedFreeCountry != null && savedFreeCountry.length == 2) {
          _selectedCountryCode = savedFreeCountry;
          _selectedCountryName =
              const <String, String>{'SA': 'Saudi Arabia', 'PK': 'Pakistan'}[savedFreeCountry];
        }
        if (savedTorCode != null &&
            VpnGateService.torExitCountries.any((c) => c.code == savedTorCode)) {
          _torCountryCode = savedTorCode;
        }
        if (savedTorName != null && savedTorName.isNotEmpty) _torCountryName = savedTorName;
      });
    } catch (_) {}
  }

  Future<void> _persistMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastMode, mode);
    } catch (_) {}
  }

  Future<void> _persistSelectedServer(Server? server) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (server == null) {
        await prefs.remove(_prefLastServer);
      } else {
        await prefs.setString(_prefLastServer, jsonEncode(server.toJson()));
      }
    } catch (_) {}
  }

  Future<void> _persistFreeCountry(String? code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (code == null) {
        await prefs.remove(_prefLastFreeCountry);
      } else {
        await prefs.setString(_prefLastFreeCountry, code);
      }
    } catch (_) {}
  }

  Future<void> _persistTorCountry(String code, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastTorCountryCode, code);
      await prefs.setString(_prefLastTorCountryName, name);
    } catch (_) {}
  }

  // ----------------------------------------------------------------- servers

  Future<void> _loadCandidates({bool force = false}) async {
    if (mounted) setState(() => _loadingServers = true);
    try {
      final result = await _vpngate.fetchServers(forceRefresh: force);
      _candidates = result.servers;
      if (mounted) setState(() => _loadingServers = false);
      if (_candidates.isNotEmpty) {
        _candidates =
            await _vpngate.pingAndScore(_candidates, maxParallel: 25, timeoutMs: 800);
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('loadCandidates error: $e');
      if (mounted) setState(() => _loadingServers = false);
    }
    _maybeAutoConnectOnOpen();
  }

  Future<void> _maybeAutoConnectOnOpen() async {
    if (_autoConnectChecked) return;
    _autoConnectChecked = true;
    if (!await _settings.getAutoConnect()) return;
    if (!mounted || _state.state != VpnConnectionState.idle) return;
    await _toggle();
  }

  Future<String> _withDns(String? configBase64) async {
    if (configBase64 == null || configBase64.isEmpty) return configBase64 ?? '';
    final preset = await _settings.getDnsFilter();
    return OvpnTools.applyDns(configBase64, preset);
  }

  // ------------------------------------------------------------------ actions

  Future<void> _toggle() async {
    if (_busy) return;
    final isActiveOrConnecting = _state.state == VpnConnectionState.connected ||
        _state.state == VpnConnectionState.connecting ||
        _state.state == VpnConnectionState.disconnecting;

    if (isActiveOrConnecting) {
      _haptic();
      _busy = true;
      _userWantsConnection = false;
      _reconnectTimer?.cancel();
      _userCancelledFreeLoop = true;
      if (_freeAttemptCompleter != null && !_freeAttemptCompleter!.isCompleted) {
        _freeAttemptCompleter!.complete(false);
      }
      _stopDurationTicker();
      if (mounted) {
        setState(() {
          _stageText = context.tr('status_disconnecting');
          _state = _state.copyWith(state: VpnConnectionState.disconnecting);
        });
      }
      try {
        await _channel.disconnect();
        unawaited(_endSession(userInitiated: true));
      } catch (e) {
        await CrashService.instance.recordError(e, StackTrace.current);
      } finally {
        _busy = false;
      }
      return;
    }

    _haptic();
    _cancelPause();
    _userWantsConnection = true;
    _reconnectAttempts = 0;
    await _startConnection();
  }

  Future<void> _startConnection() async {
    if (_busy) return;
    _busy = true;
    try {
      final prepared = await _channel.prepare();
      if (!prepared) {
        _userWantsConnection = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('err_permission_denied'))),
          );
          setState(() => _state = const VpnState());
        }
        return;
      }

      await _persistMode(_mode);

      if (_mode == 'free') {
        await _connectFreeWithAutoFallback();
      } else if (_mode == 'tor') {
        final exitCode = _torCountryCode == 'auto' ? null : _torCountryCode;
        if (mounted) {
          setState(() {
            _stageText = context.tr('stage_tor_boot');
            _state = VpnState(
                state: VpnConnectionState.connecting, mode: 'tor', countryCode: exitCode);
          });
        }
        await _channel.connect(mode: 'tor', countryCode: exitCode);
      } else if (_mode == 'stealth') {
        await _connectStealth();
      } else if (_mode == 'warp') {
        if (mounted) {
          setState(() {
            _stageText = context.tr('stage_warp');
            _state = VpnState(
              state: VpnConnectionState.connecting,
              mode: 'warp',
              countryCode: _selected?.countryShort,
            );
          });
        }
        await _channel.connect(mode: 'warp', countryCode: _selected?.countryShort);
      }
    } catch (e) {
      await CrashService.instance.recordError(e, StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
        setState(() => _state = _state.copyWith(
              state: VpnConnectionState.error,
              errorMessage: e.toString(),
            ));
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _connectStealth() async {
    final exitCode = _torCountryCode == 'auto' ? null : _torCountryCode;
    // obfs4 -> Snowflake -> OpenVPN TCP 443
    final stealthOvpn = _vpngate.pickBestStealthTcp443Server(_candidates, countryCode: exitCode);
    if (stealthOvpn == null && exitCode != null) {
      // 1.0.4 rule: a chosen country never silently falls back to another one.
      if (mounted) {
        setState(() => _state = VpnState(
              state: VpnConnectionState.error,
              mode: 'stealth',
              countryCode: exitCode,
              errorMessage: context.tr('err_no_free_servers'),
            ));
      }
      return;
    }
    if (mounted) {
      setState(() {
        _stageText = context.tr('stage_stealth_start');
        _state = VpnState(
          state: VpnConnectionState.connecting,
          mode: 'stealth',
          countryCode: exitCode ?? stealthOvpn?.countryShort,
        );
      });
    }
    await _channel.connect(
      mode: 'stealth',
      config: stealthOvpn == null ? null : await _withDns(stealthOvpn.openVpnConfigBase64),
      countryCode: exitCode ?? stealthOvpn?.countryShort,
      serverIp: stealthOvpn?.ip,
      preferUdp: false,
    );
  }

  /// Builds the try-queue.
  ///  * imported .ovpn → only that server
  ///  * a chosen country → that server, then other servers in the SAME country
  ///    (no silent cross-country fallback)
  ///  * Auto → best servers worldwide
  String? get _requestedFreeCountry {
    final c = _selectedCountryCode ?? _selected?.countryShort;
    return (c != null && c.length == 2) ? c : null;
  }

  /// Drops servers that failed the reachability test, unless that leaves none.
  List<Server> _preferAlive(List<Server> list) {
    final alive = list.where((s) => !s.isDead).toList();
    return alive.isNotEmpty ? alive : list;
  }

  List<Server> _buildFreeQueue() {
    final sel = _selected;
    if (ImportedServersService.isImported(sel)) return <Server>[sel!];
    final country = _requestedFreeCountry;
    if (country != null) {
      final inCountry = _candidates
          .where((s) => s.countryShort == country && s.openVpnConfigBase64.isNotEmpty)
          .toList();
      if (sel != null && sel.openVpnConfigBase64.isNotEmpty && sel.countryShort == country) {
        inCountry.removeWhere((s) => s.ip == sel.ip);
        inCountry.insert(0, sel);
      }
      return _preferAlive(inCountry);
    }
    return _preferAlive(_candidates.where((s) => s.openVpnConfigBase64.isNotEmpty).toList());
  }

  Future<void> _connectFreeWithAutoFallback() async {
    _userCancelledFreeLoop = false;
    if (_candidates.isEmpty && !ImportedServersService.isImported(_selected)) {
      if (mounted) {
        setState(() {
          _stageText = context.tr('stage_finding_fastest');
          _state = const VpnState(state: VpnConnectionState.connecting, mode: 'free');
        });
      }
      await _loadCandidates(force: true);
    }

    final queue = _buildFreeQueue();
    if (queue.isEmpty) {
      if (mounted) {
        setState(() => _state = VpnState(
              state: VpnConnectionState.error,
              mode: 'free',
              countryCode: _requestedFreeCountry,
              errorMessage: context.tr('err_no_free_servers'),
            ));
      }
      if (_requestedFreeCountry == null) await _smartFallbackToStealth();
      return;
    }

    final maxTries = queue.length < 5 ? queue.length : 5;
    _busy = false;

    for (var i = 0; i < maxTries; i++) {
      if (_userCancelledFreeLoop || !mounted || _mode != 'free') return;
      final candidate = queue[i];
      _connectingServer = candidate;
      setState(() {
        _stageText = maxTries > 1
            ? context.tr('stage_trying',
                {'country': candidate.countryLong, 'i': i + 1, 'n': maxTries})
            : context.tr('stage_connecting_to', {'country': candidate.countryLong});
        _state = VpnState(
          state: VpnConnectionState.connecting,
          mode: 'free',
          countryCode: candidate.countryShort,
          ip: candidate.ip,
        );
      });

      _freeAttemptCompleter = Completer<bool>();
      await _channel.connect(
        mode: 'free',
        config: await _withDns(candidate.openVpnConfigBase64),
        countryCode: candidate.countryShort,
        serverIp: candidate.ip,
        preferUdp: await _settings.getPreferUdp(),
      );

      final connected = await _freeAttemptCompleter!.future.timeout(
        const Duration(seconds: 16),
        onTimeout: () => false,
      );

      if (connected) return;
      if (_userCancelledFreeLoop || _mode != 'free') return;
    }

    if (!_userCancelledFreeLoop && mounted && _mode == 'free') {
      setState(() {
        _stageText = '';
        _state = VpnState(
          state: VpnConnectionState.error,
          mode: 'free',
          errorMessage: context.tr('err_free_busy'),
        );
      });
      if (_requestedFreeCountry == null) await _smartFallbackToStealth();
    }
  }

  /// Smart Connect: when every Free server fails in Auto mode, try Stealth
  /// automatically (announced with a snackbar). Never used when the user chose
  /// a specific country or an imported server (1.0.4: no cross-country fallback).
  Future<void> _smartFallbackToStealth() async {
    if (!mounted || _userCancelledFreeLoop || !_userWantsConnection) return;
    if (ImportedServersService.isImported(_selected)) return;
    if (!await _settings.getSmartFallback()) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('smart_fallback_stealth'))),
    );
    setState(() => _mode = 'stealth');
    await _persistMode('stealth');
    await _connectStealth();
  }

  Future<void> _switchMode(String newMode) async {
    if (_mode == newMode) return;
    _userPickedMode = true;
    _userCancelledFreeLoop = true;
    _userWantsConnection = false;
    _reconnectTimer?.cancel();
    if (_freeAttemptCompleter != null && !_freeAttemptCompleter!.isCompleted) {
      _freeAttemptCompleter!.complete(false);
    }
    _stopDurationTicker();
    final wasActive = _state.state == VpnConnectionState.connected ||
        _state.state == VpnConnectionState.connecting;
    setState(() {
      _mode = newMode;
      _stageText = '';
      _state = VpnState(
        state: VpnConnectionState.idle,
        mode: newMode,
        countryCode: (newMode == 'tor' || newMode == 'stealth')
            ? (_torCountryCode == 'auto' ? null : _torCountryCode)
            : _selected?.countryShort,
      );
    });
    await _persistMode(newMode);
    if (wasActive) await _channel.disconnect();
  }

  Future<void> _applyPickedServer(Server server) async {
    final wasActive = _state.state == VpnConnectionState.connected ||
        _state.state == VpnConnectionState.connecting;
    _userWantsConnection = false;
    _reconnectTimer?.cancel();
    _stopDurationTicker();
    _userPickedMode = true;
    setState(() {
      _selected = server;
      _selectedCountryCode = server.countryShort.isNotEmpty ? server.countryShort : null;
      _selectedCountryName = null;
      _mode = 'free';
      _state = VpnState(
        state: VpnConnectionState.idle,
        mode: 'free',
        countryCode: server.countryShort,
      );
    });
    await _persistSelectedServer(server);
    await _persistFreeCountry(null);
    await _persistMode('free');
    if (wasActive) await _channel.disconnect();
  }

  /// Free mode: connect to a country (best server inside it), e.g. pinned SA / PK.
  Future<void> _applyFreeCountry(String code, String name) async {
    final wasActive = _state.state == VpnConnectionState.connected ||
        _state.state == VpnConnectionState.connecting;
    _userWantsConnection = false;
    _userPickedMode = true;
    _stopDurationTicker();
    setState(() {
      _selected = null;
      _selectedCountryCode = code;
      _selectedCountryName = name;
      _mode = 'free';
      _state = VpnState(state: VpnConnectionState.idle, mode: 'free', countryCode: code);
    });
    await _persistSelectedServer(null);
    await _persistFreeCountry(code);
    await _persistMode('free');
    if (wasActive) await _channel.disconnect();
  }

  Future<void> _pickServer() async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => CountriesScreen(
          initialServers: _candidates,
          currentMode: _mode,
          selectedCountryCode: _torCountryCode,
        ),
      ),
    );
    unawaited(_loadQuick());
    if (!mounted || result == null) return;

    if (result is Server) {
      await _applyPickedServer(result);
    } else if (result == 'auto') {
      await _applyAutoFree();
    } else if (result is Map && result['mode'] == 'free') {
      await _applyFreeCountry(
        (result['countryCode'] ?? '').toString(),
        (result['countryLong'] ?? '').toString(),
      );
    } else if (result is Map) {
      final wasActive = _state.state == VpnConnectionState.connected ||
          _state.state == VpnConnectionState.connecting;
      final code = (result['countryCode'] ?? 'auto').toString();
      final name = (result['countryLong'] ?? '').toString();
      _userWantsConnection = false;
      _stopDurationTicker();
      setState(() {
        _torCountryCode = code;
        _torCountryName = name;
        _state = VpnState(
          state: VpnConnectionState.idle,
          mode: _mode,
          countryCode: code == 'auto' ? null : code,
        );
      });
      await _persistTorCountry(code, name);
      if (wasActive) await _channel.disconnect();
    } else if (result is String) {
      if (result == 'free' || result == 'tor' || result == 'stealth' || result == 'warp') {
        await _switchMode(result);
      }
    }
  }

  Future<void> _applyAutoFree() async {
    final wasActive = _state.state == VpnConnectionState.connected ||
        _state.state == VpnConnectionState.connecting;
    _userWantsConnection = false;
    _userPickedMode = true;
    setState(() {
      _selected = null;
      _selectedCountryCode = null;
      _selectedCountryName = null;
      _mode = 'free';
      _state = const VpnState(state: VpnConnectionState.idle, mode: 'free');
    });
    await _persistSelectedServer(null);
    await _persistFreeCountry(null);
    await _persistMode('free');
    if (wasActive) await _channel.disconnect();
  }

  Future<void> _openTools() async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (_) => const ToolsScreen()),
    );
    if (!mounted) return;
    if (result is Server) {
      await _applyPickedServer(result);
      await _toggle();
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------- UI

  String get _torDisplayName => _torCountryName.isNotEmpty
      ? _torCountryName
      : context.tr('tor_any_country');

  int get _torCountryCount => VpnGateService.torExitCountries.length - 1;

  String _serverRowFlag() {
    if (_mode == 'tor' || _mode == 'stealth') {
      if (_torCountryCode != 'auto' && _torCountryCode.length == 2) {
        return flagEmoji(_torCountryCode);
      }
      return _mode == 'stealth' ? '🛡️' : '🧅';
    }
    if (_mode == 'warp') return '⚡';
    if (ImportedServersService.isImported(_selected)) return '🔑';
    if (_selected != null && _selected!.countryShort.isNotEmpty) {
      return flagEmoji(_selected!.countryShort);
    }
    if (_selectedCountryCode != null && _selectedCountryCode!.length == 2) {
      return flagEmoji(_selectedCountryCode!);
    }
    if (_state.countryCode != null &&
        _state.countryCode!.length == 2 &&
        _state.countryCode!.toLowerCase() != 'un') {
      return flagEmoji(_state.countryCode!);
    }
    if (_candidates.isNotEmpty) return flagEmoji(_candidates.first.countryShort);
    return '🌐';
  }

  String _serverRowTitle() {
    if (_mode == 'free') {
      if (_selected != null) return _selected!.countryLong;
      if (_selectedCountryCode != null) {
        return _selectedCountryName ??
            _candidates
                .where((s) => s.countryShort == _selectedCountryCode)
                .map((s) => s.countryLong)
                .firstOrNull ??
            _selectedCountryCode!;
      }
      if (_candidates.isNotEmpty) {
        return context.tr('server_auto_country', {'country': _candidates.first.countryLong});
      }
      return context.tr('server_auto_fastest');
    } else if (_mode == 'tor') {
      return _torCountryCode != 'auto'
          ? context.tr('tor_title_country', {'country': _torDisplayName})
          : context.tr('tor_title');
    } else if (_mode == 'stealth') {
      return _torCountryCode != 'auto'
          ? context.tr('stealth_title_country', {'country': _torDisplayName})
          : context.tr('stealth_title');
    }
    return context.tr('warp_title');
  }

  String _serverRowSubtitle() {
    if (_mode == 'tor') {
      return _torCountryCode != 'auto'
          ? context.tr('sub_tor_strict', {'code': _torCountryCode.toUpperCase(), 'n': _torCountryCount})
          : context.tr('sub_tor_any', {'n': _torCountryCount});
    }
    if (_mode == 'stealth') return context.tr('sub_stealth');
    if (_mode == 'warp') return context.tr('sub_warp');
    final working = _candidates.where((s) => !s.isDead).length;
    final countText = working > 0 ? context.tr('available_count', {'n': working}) : '';
    if (_selected == null && _selectedCountryCode != null) {
      final n = _candidates
          .where((s) =>
              s.countryShort == _selectedCountryCode &&
              s.openVpnConfigBase64.isNotEmpty &&
              !s.isDead)
          .length;
      return n == 0
          ? context.tr('no_free_now')
          : context.tr('sub_free_choose', {'count': context.tr('available_count', {'n': n})});
    }
    if (_selected != null && _selected!.ip.isNotEmpty) {
      return context.tr('sub_free_ip', {'ip': _selected!.ip, 'count': countText});
    }
    return context.tr('sub_free_choose', {'count': countText});
  }

  String _subCardModeLine() {
    if (_state.state == VpnConnectionState.connected) {
      return _state.ip ?? _mode.toUpperCase();
    }
    if (_mode == 'free') {
      return _selected?.ip.isNotEmpty == true ? _selected!.ip : context.tr('line_vpngate');
    } else if (_mode == 'tor') {
      return _torCountryCode != 'auto'
          ? context.tr('line_tor_exit', {'country': _torDisplayName})
          : context.tr('line_tor');
    } else if (_mode == 'stealth') {
      return context.tr('line_stealth');
    }
    return context.tr('line_warp');
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _state.state == VpnConnectionState.connected;
    final activeDuration = isConnected
        ? (_liveDuration > _state.connectedDuration ? _liveDuration : _state.connectedDuration)
        : Duration.zero;
    final layout = ThemeService.instance.layout;

    final List<Widget> children = switch (layout) {
      'compact' => [
          _header(),
          const SizedBox(height: 6),
          _modeBar(),
          const SizedBox(height: 10),
          _serverCard(dense: true),
          _announcement(),
          const Spacer(),
          ConnectButton(state: _state.state, onPressed: _toggle, size: 150),
          const SizedBox(height: 14),
          _statusText2(isConnected),
          _actionRow(isConnected),
          const SizedBox(height: 8),
          _quickConnectRow(),
          const Spacer(),
          _stats(activeDuration, isConnected),
        ],
      'minimal' => [
          _header(),
          _announcement(),
          const Spacer(),
          ConnectButton(state: _state.state, onPressed: _toggle, size: 230),
          const SizedBox(height: 22),
          _statusText2(isConnected),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _pickServer,
            icon: Text(_serverRowFlag(), style: const TextStyle(fontSize: 20)),
            label: Text(_serverRowTitle(),
                style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
          ),
          _actionRow(isConnected),
          const Spacer(),
          if (isConnected) _stats(activeDuration, isConnected) else const SizedBox(height: 8),
        ],
      _ => [
          _header(),
          const SizedBox(height: 8),
          _modeBar(),
          const SizedBox(height: 16),
          _serverCard(),
          _announcement(),
          const SizedBox(height: 12),
          Text(_subCardModeLine(),
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          if (_loadingServers && _mode == 'free')
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(context.tr('refreshing_servers'),
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ),
          const Spacer(),
          ConnectButton(state: _state.state, onPressed: _toggle),
          const SizedBox(height: 22),
          _statusText2(isConnected),
          _actionRow(isConnected),
          const Spacer(),
          _stats(activeDuration, isConnected),
        ],
    };

    return Scaffold(
      backgroundColor: AppTheme.background,
      bottomNavigationBar: const BannerAdWidget(),
      body: SafeArea(
        // Scrolls on very small screens instead of overflowing.
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: IntrinsicHeight(
                child: Column(children: [...children, const SizedBox(height: 8)]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 4, 4),
        child: Row(
          children: [
            Icon(Icons.shield_rounded, color: AppTheme.accentStart),
            const SizedBox(width: 6),
            const Text('PathGuard', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const Spacer(),
            const AdFreeChip(),
            IconButton(
              tooltip: context.tr('tools'),
              icon: const Icon(Icons.speed_rounded),
              onPressed: _openTools,
            ),
            IconButton(
              tooltip: context.tr('settings'),
              icon: const Icon(Icons.settings_rounded),
              onPressed: _openSettings,
            ),
          ],
        ),
      );

  Widget _modeBar() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(child: _modeChip('free', context.tr('mode_free'))),
            Expanded(child: _modeChip('tor', context.tr('mode_tor'))),
            Expanded(child: _modeChip('stealth', context.tr('mode_stealth'))),
            Expanded(child: _modeChip('warp', context.tr('mode_warp'))),
          ],
        ),
      );

  Widget _serverCard({bool dense = false}) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceGlass,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ListTile(
          dense: dense,
          leading: Text(_serverRowFlag(), style: TextStyle(fontSize: dense ? 24 : 30)),
          title: Text(_serverRowTitle(), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: dense
              ? null
              : Text(_serverRowSubtitle(),
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          onTap: _pickServer,
        ),
      );

  Widget _statusText2(bool isConnected) {
    final paused = _pauseUntil != null && !isConnected;
    final text = paused ? context.tr('paused_until', {'time': _left(_pauseUntil!)}) : _statusText();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(
          text,
          key: ValueKey<String>('${_state.state}_${_stageText}_$paused'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _state.state == VpnConnectionState.error
                ? AppTheme.danger
                : isConnected
                    ? AppTheme.connected
                    : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  /// Pause / Auto-off while connected, "Resume now" while paused.
  Widget _actionRow(bool isConnected) {
    if (_pauseUntil != null && !isConnected) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FilledButton.tonalIcon(
          onPressed: _resumeFromPause,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(context.tr('resume_now')),
        ),
      );
    }
    if (!isConnected) return const SizedBox(height: 8);
    final autoOff = _autoOffAt;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: _pause,
            icon: const Icon(Icons.pause_rounded, size: 18),
            label: Text(context.tr('pause')),
          ),
          OutlinedButton.icon(
            onPressed: _setAutoOff,
            icon: Icon(autoOff == null ? Icons.timer_outlined : Icons.timer_off_outlined, size: 18),
            label: Text(autoOff == null
                ? context.tr('autooff')
                : context.tr('autooff_active', {'time': _left(autoOff)})),
          ),
        ],
      ),
    );
  }

  Widget _quickConnectRow() {
    if (_quick.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Text(context.tr('quick_connect').toUpperCase(),
            style: TextStyle(
                color: AppTheme.accentStart,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 6),
        // SingleChildScrollView (not ListView): works inside IntrinsicHeight.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final s in _quick)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ActionChip(
                    backgroundColor: AppTheme.surfaceGlass,
                    side: BorderSide(color: AppTheme.divider),
                    avatar: Text(flagEmoji(s.countryShort)),
                    label: Text(s.countryLong, overflow: TextOverflow.ellipsis),
                    onPressed: () => _quickConnect(s),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stats(Duration activeDuration, bool isConnected) => StatsBar(
        duration: activeDuration,
        bytesIn: isConnected ? _state.bytesIn : 0,
        bytesOut: isConnected ? _state.bytesOut : 0,
        ping: isConnected
            ? (_state.ping ??
                ((_selected?.measuredPing ?? 0) > 0 ? _selected!.measuredPing : null))
            : null,
        downRate: isConnected ? _downRate : null,
        upRate: isConnected ? _upRate : null,
      );

  /// Message from the remote settings file (or an "update available" notice).
  Widget _announcement() {
    return ValueListenableBuilder<int>(
      valueListenable: RemoteConfigService.instance.version,
      builder: (context, _, __) {
        final cfg = RemoteConfigService.instance;
        final text = cfg.minSupportedBuild > _appBuild
            ? context.tr('update_needed')
            : cfg.announcementFor(L10n.of(context).locale.languageCode);
        if (text == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.accentStart.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accentStart.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.campaign_rounded, color: AppTheme.accentStart, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            ],
          ),
        );
      },
    );
  }

  /// Keep in sync with pubspec.yaml build number.
  static const int _appBuild = 1005;

  Widget _modeChip(String mode, String label) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => _switchMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(colors: [AppTheme.accentStart, AppTheme.accentEnd])
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: selected ? AppTheme.onAccent : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  String _statusText() {
    switch (_state.state) {
      case VpnConnectionState.connecting:
        return _stageText.isNotEmpty ? _stageText : context.tr('status_connecting');
      case VpnConnectionState.connected:
        return context.tr('status_connected');
      case VpnConnectionState.disconnecting:
        return context.tr('status_disconnecting');
      case VpnConnectionState.error:
        return _state.errorMessage ?? context.tr('status_failed');
      default:
        return _stageText.isNotEmpty ? _stageText : context.tr('status_tap_connect');
    }
  }
}
