import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

class StatsBar extends StatelessWidget {
  final Duration duration;
  final int bytesIn;
  final int bytesOut;
  final int? ping;

  /// Live speed in bytes per second (null = hide).
  final double? downRate;
  final double? upRate;

  const StatsBar({
    super.key,
    required this.duration,
    required this.bytesIn,
    required this.bytesOut,
    this.ping,
    this.downRate,
    this.upRate,
  });

  static String formatRate(double bps) {
    final bits = bps * 8;
    if (bits < 1000 * 1000) return '${(bits / 1000).toStringAsFixed(0)} kbps';
    return '${(bits / (1000 * 1000)).toStringAsFixed(1)} Mbps';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _item(context.tr('stat_time'), _formatDuration(duration)),
          _item(context.tr('stat_down'), _formatBytes(bytesIn),
              sub: downRate == null ? null : '↓ ${formatRate(downRate!)}'),
          _item(context.tr('stat_up'), _formatBytes(bytesOut),
              sub: upRate == null ? null : '↑ ${formatRate(upRate!)}'),
          _item(context.tr('stat_ping'), ping != null ? '${ping}ms' : '—'),
        ],
      ),
    );
  }

  Widget _item(String label, String value, {String? sub}) => Column(
        children: [
          Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, textDirection: TextDirection.ltr, style: TextStyle(color: AppTheme.connected, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
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
