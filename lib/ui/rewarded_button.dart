import 'package:flutter/material.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// Opt-in rewarded-ad button. Hidden until an ad is actually loaded, so a tap
/// always pays out; runs [onReward] only when the reward was earned.
class RewardedButton extends StatefulWidget {
  const RewardedButton({
    super.key,
    required this.label,
    required this.note,
    required this.icon,
    required this.placement,
    required this.onReward,
  });

  final String label;
  final String note;
  final IconData icon;
  final String placement;
  final VoidCallback onReward;

  @override
  State<RewardedButton> createState() => _RewardedButtonState();
}

class _RewardedButtonState extends State<RewardedButton> {
  bool _busy = false;

  Future<void> _watch() async {
    setState(() => _busy = true);
    await MonetizationService.instance.showRewarded(
      widget.placement,
      onReward: widget.onReward,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MonetizationService.instance.rewardedReady,
      builder: (context, ready, _) {
        if (!ready && !_busy) return const SizedBox.shrink();
        return HoloButton(
          label: widget.label,
          subtitle: widget.note,
          icon: widget.icon,
          accent: SpaceColors.gold,
          height: 48,
          fontSize: 13,
          onPressed: _busy ? null : _watch,
        );
      },
    );
  }
}

/// Shows [child] only while a rewarded ad is loaded.
class WhenRewardedReady extends StatelessWidget {
  const WhenRewardedReady({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: MonetizationService.instance.rewardedReady,
    builder: (context, ready, child) => ready ? child! : const SizedBox.shrink(),
    child: child,
  );
}
