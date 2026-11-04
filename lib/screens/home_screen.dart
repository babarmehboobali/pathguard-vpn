import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../models/vpn_state.dart';
import '../models/server.dart';
import '../services/vpn_channel.dart';
import '../services/vpngate_service.dart';
import '../services/ads_service.dart';
import '../services/premium_service.dart';
import '../services/crash_service.dart';
import '../widgets/connect_button.dart';
import '../widgets/stats_bar.dart';
import '../widgets/banner_ad_widget.dart';
import '../utils/flag.dart';
import 'countries_screen.dart';

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

  final VpnChannel _channel = VpnChannel();
  final VpnGateService _vpngate = VpnGateService();
  final AdsService _ads = AdsService.instance;
  final PremiumService _premium = PremiumService();

  StreamSubscription<VpnState>? _stateSub;
  Timer? _uiTimer;
  DateTime? _connectedSince;
  Duration _liveDuration = Duration.zero;

  VpnState _state = const VpnState();
  bool _isPremium = false;
  List<Server> _candidates = <Server>[];
  bool _loadingServers = true;
  String? _loadError;
  String _source = '';
  String _mode = 'free';
  Server? _selected;
  String _torCountryCode = 'auto';
  String _torCountryName = 'Fastest / Any Country';
  bool _busy = false;
  bool _userCancelledFreeLoop = false;
  String _stageText = '';
  Completer<bool>? _freeAttemptCompleter;

  @override
  void initState() {
    super.initState();
    _restorePersistedSelection();
    _stateSub = _channel.stateStream.listen((s) {
      CrashService.instance.recordError('state: ${s.state} mode: ${s.mode}', StackTrace.current);
      if (!mounted) return;

      if (s.mode != null && s.mode!.isNotEmpty && s.mode != _mode) {
        if (s.state != VpnConnectionState.connected) {
          return;
        }
      }

      if (_freeAttemptCompleter != null && !_freeAttemptCompleter!.isCompleted) {
        if (s.state == VpnConnectionState.connected && s.mode == 'free') {
          _freeAttemptCompleter!.complete(true);
        } else if (s.state == VpnConnectionState.error || s.state == VpnConnectionState.idle) {
          _freeAttemptCompleter!.complete(false);
        }
      }

      if (s.state == VpnConnectionState.connected) {
        _startDurationTickerIfNeeded();
      } else {
        _stopDurationTicker();
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
        if (s.state == VpnConnectionState.connected &&
            s.mode != null &&
            s.mode!.isNotEmpty) {
          _mode = s.mode!;
        }
      });
    });
    _loadPremium();
    _loadCandidates();
  }

  void _startDurationTickerIfNeeded() {
    if (_connectedSince == null) {
      _connectedSince = DateTime.now();
      _liveDuration = Duration.zero;
    }
    _uiTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedSince == null) return;
      setState(() {
        _liveDuration = DateTime.now().difference(_connectedSince!);
      });
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
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _restorePersistedSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_prefLastMode);
      final savedServerJson = prefs.getString(_prefLastServer);
      final savedTorCode = prefs.getString(_prefLastTorCountryCode);
      final savedTorName = prefs.getString(_prefLastTorCountryName);

      Server? restoredServer;
      if (savedServerJson != null && savedServerJson.isNotEmpty) {
        try {
          final map = Map<String, dynamic>.from(jsonDecode(savedServerJson) as Map);
          restoredServer = Server.fromJson(map);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        if (savedMode == 'free' ||
            savedMode == 'tor' ||
            savedMode == 'stealth' ||
            savedMode == 'warp') {
          _mode = savedMode!;
        }
        if (restoredServer != null) {
          _selected = restoredServer;
        }
        if (savedTorCode != null && savedTorCode.isNotEmpty) {
          _torCountryCode = savedTorCode;
        }
        if (savedTorName != null && savedTorName.isNotEmpty) {
          _torCountryName = savedTorName;
        }
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

  Future<void> _persistTorCountry(String code, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastTorCountryCode, code);
      await prefs.setString(_prefLastTorCountryName, name);
    } catch (_) {}
  }

  Future<void> _loadPremium() async {
    _isPremium = await _premium.isPremium();
    if (mounted) setState(() {});
  }

  Future<void> _loadCandidates({bool force = false}) async {
    if (mounted) {
      setState(() {
        _loadingServers = true;
        _loadError = null;
      });
    }
    try {
      final result = await _vpngate.fetchServers(forceRefresh: force);
      _candidates = result.servers;
      _source = result.source;
      if (mounted) setState(() => _loadingServers = false);
      if (_candidates.isNotEmpty) {
        final scored = await _vpngate.pingAndScore(_candidates, maxParallel: 25, timeoutMs: 800);
        _candidates = scored;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('loadCandidates error: $e');
      if (mounted) {
        setState(() {
          _loadingServers = false;
          _loadError = 'Could not load servers ($e)';
        });
      }
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    _busy = true;
    final isActiveOrConnecting = _state.state == VpnConnectionState.connected ||
        _state.state == VpnConnectionState.connecting ||
        _state.state == VpnConnectionState.disconnecting;

    if (isActiveOrConnecting) {
      _userCancelledFreeLoop = true;
      if (_freeAttemptCompleter != null && !_freeAttemptCompleter!.isCompleted) {
        _freeAttemptCompleter!.complete(false);
      }
      _stopDurationTicker();
      if (mounted) {
        setState(() {
          _stageText = 'Disconnecting…';
          _state = _state.copyWith(state: VpnConnectionState.disconnecting);
        });
      }
      try {
        await _channel.disconnect();
        await _ads.onUserAction();
      } catch (e) {
        await CrashService.instance.recordError(e, StackTrace.current);
      } finally {
        _busy = false;
      }
      return;
    }

    try {
      final prepared = await _channel.prepare();
      if (!prepared) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('VPN permission denied')),
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
            _stageText = 'Bootstrapping Tor 5%…';
            _state = VpnState(
              state: VpnConnectionState.connecting,
              mode: 'tor',
              countryCode: exitCode,
            );
          });
        }
        await _channel.connect(
          mode: 'tor',
          countryCode: exitCode,
        );
      } else if (_mode == 'stealth') {
        final exitCode = _torCountryCode == 'auto' ? null : _torCountryCode;
        // Pick best TCP 443 OpenVPN server as the 3rd-stage Stealth fallback (obfs4 -> Snowflake -> OpenVPN TCP 443)
        final stealthOvpn = _vpngate.pickBestStealthTcp443Server(
          _candidates,
          countryCode: exitCode,
        );
        if (mounted) {
          setState(() {
            _stageText = 'Starting Stealth (obfs4)… 5%';
            _state = VpnState(
              state: VpnConnectionState.connecting,
              mode: 'stealth',
              countryCode: exitCode ?? stealthOvpn?.countryShort,
            );
          });
        }
        await _channel.connect(
          mode: 'stealth',
          config: stealthOvpn?.openVpnConfigBase64,
          countryCode: exitCode ?? stealthOvpn?.countryShort,
          serverIp: stealthOvpn?.ip,
          preferUdp: false,
        );
      } else if (_mode == 'warp') {
        if (mounted) {
          setState(() {
            _stageText = 'Connecting to WARP…';
            _state = VpnState(
              state: VpnConnectionState.connecting,
              mode: 'warp',
              countryCode: _selected?.countryShort,
            );
          });
        }
        await _channel.connect(
          mode: 'warp',
          countryCode: _selected?.countryShort,
        );
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

  Future<void> _connectFreeWithAutoFallback() async {
    _userCancelledFreeLoop = false;
    if (_candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _stageText = 'Finding fastest server…';
          _state = const VpnState(state: VpnConnectionState.connecting, mode: 'free');
        });
      }
      await _loadCandidates(force: true);
    }

    final queue = <Server>[];
    if (_selected != null && _selected!.openVpnConfigBase64.isNotEmpty) {
      queue.add(_selected!);
      for (final s in _candidates) {
        if (s.ip != _selected!.ip &&
            s.countryShort == _selected!.countryShort &&
            s.openVpnConfigBase64.isNotEmpty) {
          queue.add(s);
        }
      }
      for (final s in _candidates) {
        if (s.ip != _selected!.ip &&
            s.countryShort != _selected!.countryShort &&
            s.openVpnConfigBase64.isNotEmpty) {
          queue.add(s);
        }
      }
    } else {
      queue.addAll(_candidates.where((s) => s.openVpnConfigBase64.isNotEmpty));
    }

    if (queue.isEmpty) {
      if (mounted) {
        setState(() => _state = const VpnState(
              state: VpnConnectionState.error,
              mode: 'free',
              errorMessage: 'No free servers reachable — try Stealth or WARP',
            ));
      }
      return;
    }

    final maxTries = queue.length < 5 ? queue.length : 5;
    _busy = false;

    for (var i = 0; i < maxTries; i++) {
      if (_userCancelledFreeLoop || !mounted || _mode != 'free') return;
      final candidate = queue[i];
      setState(() {
        _stageText = maxTries > 1
            ? 'Trying ${candidate.countryLong} (${i + 1}/$maxTries)…'
            : 'Connecting to ${candidate.countryLong}…';
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
        config: candidate.openVpnConfigBase64,
        countryCode: candidate.countryShort,
        serverIp: candidate.ip,
        preferUdp: true,
      );

      final connected = await _freeAttemptCompleter!.future.timeout(
        const Duration(seconds: 16),
        onTimeout: () => false,
      );

      if (connected) {
        await _ads.onUserAction();
        return;
      }
      if (_userCancelledFreeLoop || _mode != 'free') {
        return;
      }
    }

    if (!_userCancelledFreeLoop && mounted && _mode == 'free') {
      setState(() {
        _stageText = '';
        _state = const VpnState(
          state: VpnConnectionState.error,
          mode: 'free',
          errorMessage: 'Free servers busy — tap to retry or use Stealth/WARP',
        );
      });
    }
  }

  Future<void> _switchMode(String newMode) async {
    if (_mode == newMode) return;
    _userCancelledFreeLoop = true;
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
    if (wasActive) {
      await _channel.disconnect();
    }
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
    if (!mounted || result == null) return;

    final wasActive = _state.state == VpnConnectionState.connected ||
        _state.state == VpnConnectionState.connecting;

    if (result is Server) {
      _stopDurationTicker();
      setState(() {
        _selected = result;
        _mode = 'free';
        _state = VpnState(
          state: VpnConnectionState.idle,
          mode: 'free',
          countryCode: result.countryShort,
        );
      });
      await _persistSelectedServer(result);
      await _persistMode('free');
      if (wasActive) {
        await _channel.disconnect();
      }
    } else if (result is Map) {
      final code = (result['countryCode'] ?? 'auto').toString();
      final name = (result['countryLong'] ?? 'Fastest / Any Country').toString();
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
      if (wasActive) {
        await _channel.disconnect();
      }
    } else if (result is String) {
      if (result == 'free' || result == 'tor' || result == 'stealth' || result == 'warp') {
        await _switchMode(result);
      }
    }
  }

  String _serverRowFlag() {
    if (_mode == 'tor' || _mode == 'stealth') {
      if (_torCountryCode != 'auto' && _torCountryCode.length == 2) {
        return flagEmoji(_torCountryCode);
      }
      return _mode == 'stealth' ? '🛡️' : '🧅';
    }
    if (_mode == 'warp') {
      return '⚡';
    }
    if (_selected != null && _selected!.countryShort.isNotEmpty) {
      return flagEmoji(_selected!.countryShort);
    }
    if (_state.countryCode != null &&
        _state.countryCode!.length == 2 &&
        _state.countryCode!.toLowerCase() != 'un') {
      return flagEmoji(_state.countryCode!);
    }
    if (_candidates.isNotEmpty) {
      return flagEmoji(_candidates.first.countryShort);
    }
    return flagEmoji('un');
  }

  String _serverRowTitle() {
    if (_mode == 'free') {
      if (_selected != null) return _selected!.countryLong;
      if (_candidates.isNotEmpty) return 'Auto (${_candidates.first.countryLong})';
      return 'Auto (Fastest Free)';
    } else if (_mode == 'tor') {
      return _torCountryCode != 'auto'
          ? 'Tor ($_torCountryName)'
          : 'Tor Onion Network';
    } else if (_mode == 'stealth') {
      return _torCountryCode != 'auto'
          ? 'Stealth ($_torCountryName)'
          : 'Stealth Anti-Censorship';
    } else {
      return 'Cloudflare WARP';
    }
  }

  String _serverRowSubtitle() {
    if (_mode == 'tor') {
      return _torCountryCode != 'auto'
          ? 'Strict ExitNode {${_torCountryCode.toLowerCase()}} • Tap to change (31 countries)'
          : 'Fastest / Any country • Tap to choose exit (31 countries)';
    }
    if (_mode == 'stealth') {
      return 'obfs4 → Snowflake → OpenVPN TCP 443 • Tap to choose country';
    }
    if (_mode == 'warp') {
      return 'WireGuard 1.1.1.1 tunnel • Fast & encrypted';
    }
    final countText = _candidates.isNotEmpty ? ' (${_candidates.length} available)' : '';
    if (_selected != null && _selected!.ip.isNotEmpty) {
      return '${_selected!.ip} • Tap to change server$countText';
    }
    return 'Tap to choose worldwide location$countText';
  }

  String _subCardModeLine() {
    if (_state.state == VpnConnectionState.connected) {
      return _state.ip ?? _mode.toUpperCase();
    }
    if (_mode == 'free') {
      return _selected?.ip.isNotEmpty == true ? _selected!.ip : 'VPN Gate OpenVPN';
    } else if (_mode == 'tor') {
      return _torCountryCode != 'auto'
          ? 'Tor Exit: $_torCountryName'
          : 'Tor Onion Router';
    } else if (_mode == 'stealth') {
      return 'Pluggable Transports (obfs4 / Snowflake / TCP-443)';
    } else {
      return 'Cloudflare 1.1.1.1';
    }
  }

  @override
  Widget build(BuildContext context) {
    final flag = _serverRowFlag();
    final title = _serverRowTitle();
    final isConnected = _state.state == VpnConnectionState.connected;
    final activeDuration = isConnected
        ? (_liveDuration > _state.connectedDuration ? _liveDuration : _state.connectedDuration)
        : Duration.zero;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(child: _modeChip('free', 'Free')),
                  Expanded(child: _modeChip('tor', 'Tor')),
                  Expanded(child: _modeChip('stealth', 'Stealth')),
                  Expanded(child: _modeChip('warp', 'WARP')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceGlass,
                borderRadius: BorderRadius.circular(20),
              ),
              child: ListTile(
                leading: Text(flag, style: const TextStyle(fontSize: 30)),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _serverRowSubtitle(),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                onTap: _pickServer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _subCardModeLine(),
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            if (_loadingServers && _mode == 'free')
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Refreshing worldwide servers…',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            const Spacer(),
            ConnectButton(
              state: _state.state,
              onPressed: _toggle,
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _statusText(),
                  key: ValueKey<String>('${_state.state}_$_stageText'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _state.state == VpnConnectionState.error
                        ? AppTheme.danger
                        : isConnected
                            ? const Color(0xFF00E676)
                            : Colors.white,
                  ),
                ),
              ),
            ),
            const Spacer(),
            StatsBar(
              duration: activeDuration,
              bytesIn: isConnected ? _state.bytesIn : 0,
              bytesOut: isConnected ? _state.bytesOut : 0,
              ping: isConnected ? (_state.ping ?? _selected?.measuredPing) : null,
            ),
            if (!_isPremium) const BannerAdWidget(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(String mode, String label) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => _switchMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [AppTheme.accentStart, AppTheme.accentEnd])
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: selected ? Colors.black : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  String _statusText() {
    switch (_state.state) {
      case VpnConnectionState.connecting:
        return _stageText.isNotEmpty ? _stageText : 'Connecting…';
      case VpnConnectionState.connected:
        return 'Secure tunnel active';
      case VpnConnectionState.disconnecting:
        return 'Disconnecting…';
      case VpnConnectionState.error:
        return _state.errorMessage ?? 'Connection failed — try Stealth or WARP';
      default:
        return 'Tap to connect';
    }
  }
}

