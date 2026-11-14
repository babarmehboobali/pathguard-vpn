import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/ads_service.dart';
import '../services/premium_service.dart';
import '../theme/app_theme.dart';

/// Opt-in offer: "Watch a short video → no ads for 6 hours".
/// The video plays ONLY if the user taps Watch (AdMob rewarded policy).
Future<void> showRewardOffer(BuildContext context) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Icon(Icons.ondemand_video_rounded, color: AppTheme.accentStart, size: 40),
      title: Text(ctx.tr('reward_title'), textAlign: TextAlign.center),
      content: Text(
        ctx.tr('reward_body'),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'no'),
          child: Text(ctx.tr('reward_no')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, 'watch'),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(ctx.tr('reward_watch')),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (choice == 'watch') {
    await watchRewardAndReport(context);
  }
}

/// Plays the video (user already opted in) and shows the outcome.
Future<void> watchRewardAndReport(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = L10n.of(context);
  final result = await AdsService.instance.showRewardedForAdFree();
  final key = switch (result) {
    RewardResult.granted => 'reward_granted',
    RewardResult.notFinished => 'reward_not_finished',
    RewardResult.noAd => 'ads_no_ad',
    RewardResult.atCap => 'reward_cap',
  };
  messenger?.showSnackBar(SnackBar(content: Text(l10n.t(key))));
}

String formatAdFree(BuildContext context, Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// Small pill on the home screen:
///  * ads on  → "Remove ads 6h" (greyed with "No ad available, try later" when no video is loaded)
///  * ad-free → "Ad-free: 5h 12m" plus a "+6h" button until the 24 h cap
class AdFreeChip extends StatefulWidget {
  const AdFreeChip({super.key});

  @override
  State<AdFreeChip> createState() => _AdFreeChipState();
}

class _AdFreeChipState extends State<AdFreeChip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ads = AdsService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([ads.ready, ads.rewardedReady, PremiumService.changes]),
      builder: (context, _) {
        if (!ads.ready.value) return const SizedBox.shrink();
        final adFree = PremiumService.isAdFreeNow;
        final canWatch = ads.rewardedReady.value && !PremiumService.isAtCapNow;
        final label = adFree
            ? context.tr('ads_free_left', {'time': formatAdFree(context, PremiumService.remainingNow)})
            : context.tr('ads_remove_6h');

        void onTap() {
          if (!ads.rewardedReady.value) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.tr('ads_no_ad'))),
            );
            return;
          }
          if (PremiumService.isAtCapNow) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.tr('reward_cap'))),
            );
            return;
          }
          showRewardOffer(context);
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: adFree
                    ? AppTheme.success.withValues(alpha: 0.15)
                    : AppTheme.surfaceGlass,
                border: Border.all(
                  color: adFree
                      ? AppTheme.success.withValues(alpha: 0.6)
                      : (canWatch ? AppTheme.accentStart.withValues(alpha: 0.6) : AppTheme.divider),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    adFree ? Icons.verified_rounded : Icons.ondemand_video_rounded,
                    size: 16,
                    color: adFree
                        ? AppTheme.success
                        : (canWatch ? AppTheme.accentStart : AppTheme.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: canWatch || adFree ? AppTheme.textPrimary : AppTheme.textSecondary,
                    ),
                  ),
                  if (adFree && canWatch) ...[
                    const SizedBox(width: 6),
                    Text('+6h',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.accentStart)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
