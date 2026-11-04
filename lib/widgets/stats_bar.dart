import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatsBar extends StatelessWidget {
  final Duration duration;
  final int bytesIn;
  final int bytesOut;
  final int? ping;

  const StatsBar({
    super.key,
    required this.duration,
    required this.bytesIn,
    required this.bytesOut,
    this.ping,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _item('Time', _formatDuration(duration)),
          _item('Down', _formatBytes(bytesIn)),
          _item('Up', _formatBytes(bytesOut)),
          _item('Ping', ping != null ? '${ping}ms' : '—'),
        ],
      ),
    );
  }

  Widget _item(String label, String value) => Column(
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      );

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
