import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/vpn_state.dart';
import '../theme/app_theme.dart';

class ConnectButton extends StatefulWidget {
  final VpnConnectionState state;
  final VoidCallback onPressed;

  /// Outer diameter (Classic 196, Compact 150, Minimal 230).
  final double size;

  const ConnectButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.size = 196,
  });

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnecting = widget.state == VpnConnectionState.connecting ||
        widget.state == VpnConnectionState.disconnecting;
    final isConnected = widget.state == VpnConnectionState.connected;
    final isError = widget.state == VpnConnectionState.error;

    final double outerSize = widget.size;
    final double innerSize = widget.size * 0.806;

    return GestureDetector(
      onTap: widget.onPressed,
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer ambient glow
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: outerSize,
              height: outerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  if (isConnected)
                    BoxShadow(
                      color: AppTheme.connected.withOpacity(0.38),
                      blurRadius: 36,
                      spreadRadius: 6,
                    )
                  else if (isConnecting)
                    BoxShadow(
                      color: AppTheme.accentStart.withOpacity(0.28),
                      blurRadius: 28,
                      spreadRadius: 4,
                    )
                  else if (isError)
                    BoxShadow(
                      color: AppTheme.danger.withOpacity(0.35),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                ],
              ),
            ),

            // Animated gradient sweep ring / status ring
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  size: Size(outerSize, outerSize),
                  painter: _RingPainter(
                    progress: _controller.value,
                    state: widget.state,
                  ),
                );
              },
            ),

            // Core circular power button
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected
                    ? AppTheme.connectedCore
                    : AppTheme.buttonCore,
                border: Border.all(
                  color: isConnected
                      ? AppTheme.connected.withOpacity(0.6)
                      : AppTheme.divider,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: widget.size * 0.326,
                  color: isConnected
                      ? AppTheme.connected
                      : isError
                          ? AppTheme.danger
                          : AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final VpnConnectionState state;

  _RingPainter({
    required this.progress,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Subtle track circle
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = AppTheme.divider;
    canvas.drawCircle(center, radius, trackPaint);

    if (state == VpnConnectionState.connected) {
      final connectedPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5
        ..color = AppTheme.connected;
      canvas.drawCircle(center, radius, connectedPaint);
      return;
    }

    if (state == VpnConnectionState.error) {
      final errorPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5
        ..color = AppTheme.danger;
      canvas.drawCircle(center, radius, errorPaint);
      return;
    }

    if (state == VpnConnectionState.connecting ||
        state == VpnConnectionState.disconnecting) {
      final startAngle = (progress * 2 * math.pi) - (math.pi / 2);
      final sweepAngle = 1.45 * math.pi;

      final gradient = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [
          AppTheme.accentStart.withValues(alpha: 0),
          AppTheme.accentStart,
          AppTheme.accentEnd,
          AppTheme.accentStart,
        ],
        stops: const [0.0, 0.35, 0.8, 1.0],
        transform: GradientRotation(startAngle),
      );

      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5
        ..strokeCap = StrokeCap.round
        ..shader = gradient.createShader(rect);

      canvas.drawArc(rect, startAngle, sweepAngle, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.state != state;
  }
}

