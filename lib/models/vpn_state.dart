enum VpnConnectionState { idle, connecting, connected, disconnecting, error }

class VpnState {
  final VpnConnectionState state;
  final String? countryCode;
  final String? countryName;
  final String? ip;
  final int? ping;
  final int bytesIn;
  final int bytesOut;
  final Duration connectedDuration;
  final String? mode;
  final String? errorMessage;

  const VpnState({
    this.state = VpnConnectionState.idle,
    this.countryCode,
    this.countryName,
    this.ip,
    this.ping,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.connectedDuration = Duration.zero,
    this.mode,
    this.errorMessage,
  });

  VpnState copyWith({
    VpnConnectionState? state,
    String? countryCode,
    String? countryName,
    String? ip,
    int? ping,
    int? bytesIn,
    int? bytesOut,
    Duration? connectedDuration,
    String? mode,
    String? errorMessage,
  }) =>
      VpnState(
        state: state ?? this.state,
        countryCode: countryCode ?? this.countryCode,
        countryName: countryName ?? this.countryName,
        ip: ip ?? this.ip,
        ping: ping ?? this.ping,
        bytesIn: bytesIn ?? this.bytesIn,
        bytesOut: bytesOut ?? this.bytesOut,
        connectedDuration: connectedDuration ?? this.connectedDuration,
        mode: mode ?? this.mode,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  factory VpnState.fromMap(Map<String, dynamic> map, {VpnState? previous}) {
    VpnConnectionState? newState;
    if (map.containsKey('state')) {
      final stateStr = (map['state'] as String?)?.toLowerCase() ?? 'idle';
      switch (stateStr) {
        case 'connecting':
          newState = VpnConnectionState.connecting;
          break;
        case 'connected':
          newState = VpnConnectionState.connected;
          break;
        case 'disconnecting':
          newState = VpnConnectionState.disconnecting;
          break;
        case 'error':
          newState = VpnConnectionState.error;
          break;
        default:
          newState = VpnConnectionState.idle;
      }
    }
    return (previous ?? const VpnState()).copyWith(
      state: newState,
      countryCode: map['countryCode'] as String?,
      countryName: map['countryName'] as String?,
      ip: map['ip'] as String?,
      ping: map['ping'] as int?,
      bytesIn: map['bytesIn'] as int?,
      bytesOut: map['bytesOut'] as int?,
      mode: map['mode'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}
