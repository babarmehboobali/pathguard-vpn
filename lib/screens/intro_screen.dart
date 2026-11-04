import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Short (~1.5 s) branded intro shown once per cold start.
class IntroScreen extends StatefulWidget {
  final VoidCallback onDone;
  const IntroScreen({super.key, required this.onDone});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _pulse.repeat();
    Future.delayed(const Duration(milliseconds: 1500), _finish);
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    final scale = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutBack));
    return Scaffold(
      backgroundColor: const Color(0xFF05081A),
      body: Center(
        child: FadeTransition(
          opacity: fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final t = _pulse.value;
                    final glow = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 190 + 20 * glow,
                          height: 190 + 20 * glow,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              transform: GradientRotation(t * 2 * math.pi),
                              colors: const [
                                Color(0xFF00E5FF),
                                Color(0xFF7C4DFF),
                                Color(0xFF00E5FF),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.25 + 0.35 * glow),
                                blurRadius: 30 + 20 * glow,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 182 + 20 * glow,
                          height: 182 + 20 * glow,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF05081A),
                          ),
                        ),
                        child!,
                      ],
                    );
                  },
                  child: ScaleTransition(
                    scale: scale,
                    child: ClipOval(
                      child: Image.asset('assets/brand/logo.png', width: 170, height: 170),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'PathGuard VPN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
