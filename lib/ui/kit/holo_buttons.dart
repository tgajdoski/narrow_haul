import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/services/audio_service.dart';
import '../../game/services/haptics.dart';
import 'chamfer.dart';
import 'holo_frame.dart';
import 'marquee_text.dart';
import 'tokens.dart';


enum HoloVariant { primary, secondary, ghost }

/// Shake + [UiSound.denied] for taps on something locked.
mixin DeniedShake<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  late final AnimationController shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  void deny() {
    AudioService.playUi(UiSound.denied);
    shake.forward(from: 0);
  }

  Widget shaking(Widget child) => AnimatedBuilder(
    animation: shake,
    builder: (context, child) {
      final t = shake.value;
      final dx = shake.isAnimating
          ? math.sin(t * math.pi * 6) * 6 * (1 - t)
          : 0.0;
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
    child: child,
  );

  @override
  void dispose() {
    shake.dispose();
    super.dispose();
  }
}

/// Chamfered cockpit button: icon + letter-spaced label (+ optional
/// subtitle). Primary buttons glow and pulse. Plays [sound] (by variant
/// when omitted) and a light haptic tick on primary presses. With
/// [onPressed] null and [onLocked] set, a tap shakes it and buzzes.
class HoloButton extends StatefulWidget {
  const HoloButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.subtitle,
    this.variant = HoloVariant.secondary,
    this.accent,
    this.sound,
    this.onLocked,
    this.height = 46,
    this.fontSize = 14,
    this.expand = true,
  });

  /// Big glowing call to action.
  const HoloButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.subtitle,
    this.accent,
    this.sound,
    this.onLocked,
    this.height = 50,
    this.fontSize = 16,
    this.expand = true,
  }) : variant = HoloVariant.primary;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? subtitle;
  final HoloVariant variant;
  final Color? accent;
  final UiSound? sound;
  final VoidCallback? onLocked;
  final double height;
  final double fontSize;
  final bool expand;

  @override
  State<HoloButton> createState() => _HoloButtonState();
}

class _HoloButtonState extends State<HoloButton>
    with TickerProviderStateMixin, DeniedShake {
  bool _down = false;
  AnimationController? _pulse;

  bool get _primary => widget.variant == HoloVariant.primary;
  bool get _enabled => widget.onPressed != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final want = _primary && spaceAnimationsOn(context);
    if (want && _pulse == null) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat(reverse: true);
    } else if (!want && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  void _tap() {
    final action = widget.onPressed;
    if (action == null) {
      if (widget.onLocked != null) {
        deny();
        widget.onLocked!();
      }
      return;
    }
    AudioService.playUi(widget.sound ?? UiSound.select);
    if (_primary) Haptics.light();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? SpaceColors.cyan;
    final enabled = _enabled;
    final fg = switch (widget.variant) {
      HoloVariant.primary => enabled ? SpaceColors.bg : Colors.white38,
      _ => enabled ? (_down ? Colors.white : accent) : Colors.white30,
    };

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon case final icon?) ...[
          Icon(icon, size: widget.fontSize + 6, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MarqueeText(
                widget.label.toUpperCase(),
                style: hudLabel(widget.fontSize, color: fg, spacing: 2),
              ),
              if (widget.subtitle case final sub?) ...[
                const SizedBox(height: 2),
                MarqueeText(
                  sub,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: _primary
                        ? SpaceColors.bg.withValues(alpha: 0.7)
                        : Colors.white54,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: content,
    );

    Widget frame(double pulse) {
      final fill = switch (widget.variant) {
        HoloVariant.primary =>
          enabled
              ? Color.lerp(accent, Colors.white, _down ? 0.3 : 0.08 * pulse)!
              : SpaceColors.track,
        HoloVariant.secondary =>
          _down ? accent.withValues(alpha: 0.28) : const Color(0xCC0B1626),
        HoloVariant.ghost =>
          _down ? accent.withValues(alpha: 0.18) : const Color(0x55081222),
      };
      return CustomPaint(
        painter: HoloFramePainter(
          accent: enabled ? accent : Colors.white24,
          fill: fill,
          cut: widget.height * 0.28,
          glow: _primary && enabled ? 0.6 + 0.4 * pulse : (_down ? 0.6 : 0),
          brackets: _primary || _down,
          scanlines: false,
          borderAlpha: widget.variant == HoloVariant.ghost ? 0.35 : 0.8,
          fillGradient: !_primary,
        ),
        child: SizedBox(
          height: widget.height,
          child: Center(widthFactor: widget.expand ? null : 1, child: content),
        ),
      );
    }

    final pulse = _pulse;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled || widget.onLocked != null ? _tap : null,
        child: shaking(
          AnimatedScale(
            scale: _down ? 0.97 : 1,
            duration: const Duration(milliseconds: 90),
            child: pulse == null
                ? frame(0)
                : AnimatedBuilder(
                    animation: pulse,
                    builder: (context, _) =>
                        frame(Curves.easeInOut.transform(pulse.value)),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Big square menu tile: icon, label, optional subtitle and corner badge.
class HoloTile extends StatefulWidget {
  const HoloTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.accent = SpaceColors.cyan,
    this.sound = UiSound.select,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? badge;
  final Color accent;
  final VoidCallback onTap;
  final UiSound sound;

  /// Icon beside the text instead of above it (wide tiles).
  final bool large;

  @override
  State<HoloTile> createState() => _HoloTileState();
}

class _HoloTileState extends State<HoloTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.accent;
    final icon = Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: a.withValues(alpha: 0.12),
        border: Border.all(color: a.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: a.withValues(alpha: 0.25), blurRadius: 10),
        ],
      ),
      child: Icon(widget.icon, color: a, size: widget.large ? 26 : 22),
    );
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          widget.label.toUpperCase(),
          maxLines: 1,
          style: hudLabel(widget.large ? 17 : 13, spacing: 2),
        ),
        if (widget.subtitle case final sub?) ...[
          const SizedBox(height: 2),
          MarqueeText(
            sub,
            style: TextStyle(color: a.withValues(alpha: 0.8), fontSize: 10.5),
          ),
        ],
      ],
    );
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          AudioService.playUi(widget.sound);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 90),
          child: CustomPaint(
            painter: HoloFramePainter(
              accent: a,
              fill: _down ? a.withValues(alpha: 0.22) : const Color(0xCC0B1626),
              cut: 14,
              glow: _down ? 0.8 : 0.25,
              brackets: true,
              scanlines: true,
              borderAlpha: 0.55,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: widget.large
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [icon, const SizedBox(width: 12), text],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [icon, const SizedBox(height: 6), text],
                            ),
                    ),
                  ),
                ),
                if (widget.badge case final badge?)
                  Positioned(
                    top: 6,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: SpaceColors.gold,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: SpaceColors.bg,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Back button for screen headers: `◀ HANGAR`, plays [UiSound.back].
class HoloBackButton extends StatelessWidget {
  const HoloBackButton({
    super.key,
    required this.onPressed,
    this.label = 'Hangar',
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => HoloButton(
    label: label,
    icon: Icons.chevron_left_rounded,
    onPressed: onPressed,
    sound: UiSound.back,
    variant: HoloVariant.ghost,
    height: 36,
    fontSize: 11,
    expand: false,
  );
}

/// Small status pill: `★ 54/180`, `DAILY ✓ 🔥3`… Tappable when [onTap].
class HoloChip extends StatelessWidget {
  const HoloChip({
    super.key,
    required this.label,
    this.leading,
    this.icon,
    this.color = SpaceColors.cyan,
    this.onTap,
    this.highlight = false,
  });

  final String label;
  final Widget? leading;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;

  /// Filled background (e.g. something waiting for the player).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: ShapeDecoration(
        color: highlight
            ? color.withValues(alpha: 0.22)
            : const Color(0xB30B1626),
        shape: ChamferBorder(cut: 8).copyWithSide(
          BorderSide(color: color.withValues(alpha: highlight ? 0.9 : 0.5)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?leading,
          if (icon case final icon?) Icon(icon, size: 15, color: color),
          if (leading != null || icon != null) const SizedBox(width: 6),
          Text(label, style: hudLabel(11.5, color: color, spacing: 1.2)),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 14, color: color),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AudioService.playUi(UiSound.select);
        onTap!();
      },
      child: chip,
    );
  }
}
