import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/services/audio_service.dart';
import '../game/services/haptics.dart';
import 'fonts.dart';

/// The space UI kit: cockpit-style panels, buttons, chips and the animated
/// starfield shared by every menu and popup. Widgets play their own
/// [UiSound]s, so screens get sound without extra wiring.

// ─────────────────────────────────────────────────────────────────────────────
// Tokens
// ─────────────────────────────────────────────────────────────────────────────

abstract final class SpaceColors {
  static const bg = Color(0xFF050816);
  static const panel = Color(0xFF0D1B2A);
  static const panelDeep = Color(0xE6081222);
  static const track = Color(0xFF1B263B);
  static const cyan = Color(0xFF00B4D8);
  static const cyanBright = Color(0xFF5CE1FF);
  static const gold = Color(0xFFFFD166);
  static const green = Color(0xFF4ADE80);
  static const coral = Color(0xFFE07A5F);
  static const red = Color(0xFFFF6B6B);
  static const violet = Color(0xFF9B8CFF);
  static const textDim = Color(0x8AFFFFFF);
  static const textFaint = Color(0x5CFFFFFF);
}

/// Letter-spaced display label (RussoOne).
TextStyle hudLabel(
  double size, {
  Color color = Colors.white,
  double spacing = 1.6,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: kDisplayFont,
  fontSize: size,
  color: color,
  letterSpacing: spacing,
  fontWeight: weight,
  height: 1.1,
);

/// Looping UI animations (starfield, pulses) are off in widget tests, where
/// `pumpAndSettle` would never settle, and when the system asks for reduced
/// motion.
bool spaceAnimationsOn(BuildContext context) =>
    !_inTest && !MediaQuery.disableAnimationsOf(context);

final bool _inTest =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

// ─────────────────────────────────────────────────────────────────────────────
// Chamfered shape
// ─────────────────────────────────────────────────────────────────────────────

/// A rectangle with the top-left and bottom-right corners cut ([cut]) and the
/// other two slightly cut — the kit's signature silhouette.
Path chamferPath(Rect r, double cut) {
  final c = math.min(cut, math.min(r.width, r.height) / 2);
  final s = c * 0.35;
  return Path()
    ..moveTo(r.left + c, r.top)
    ..lineTo(r.right - s, r.top)
    ..lineTo(r.right, r.top + s)
    ..lineTo(r.right, r.bottom - c)
    ..lineTo(r.right - c, r.bottom)
    ..lineTo(r.left + s, r.bottom)
    ..lineTo(r.left, r.bottom - s)
    ..lineTo(r.left, r.top + c)
    ..close();
}

class ChamferBorder extends ShapeBorder {
  const ChamferBorder({this.cut = 12});
  final double cut;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      chamferPath(rect, cut);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      chamferPath(rect, cut);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => ChamferBorder(cut: cut * t);
}

class _HoloFramePainter extends CustomPainter {
  _HoloFramePainter({
    required this.accent,
    required this.fill,
    required this.cut,
    required this.glow,
    required this.brackets,
    required this.scanlines,
    this.borderAlpha = 0.75,
    this.fillGradient = true,
  });

  final Color accent;
  final Color fill;
  final double cut;
  final double glow;
  final bool brackets;
  final bool scanlines;
  final double borderAlpha;
  final bool fillGradient;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final path = chamferPath(r.deflate(0.75), cut);

    if (glow > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: 0.35 * glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, 8 * glow),
      );
    }

    final fillPaint = Paint()..color = fill;
    if (fillGradient) {
      fillPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.alphaBlend(accent.withValues(alpha: 0.10), fill), fill],
      ).createShader(r);
    }
    canvas.drawPath(path, fillPaint);

    if (scanlines) {
      canvas.save();
      canvas.clipPath(path);
      final line = Paint()..color = Colors.white.withValues(alpha: 0.025);
      for (var y = 1.0; y < size.height; y += 3) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
      }
      canvas.restore();
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: borderAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    if (brackets) {
      // Bright corner ticks on the two big chamfers.
      final c = math.min(cut, math.min(size.width, size.height) / 2);
      final p = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.square;
      final arm = math.min(18.0, size.width / 6);
      canvas.drawLine(Offset(1, c + 1), Offset(c + 1, 1), p);
      canvas.drawLine(Offset(c + 1, 1), Offset(c + 1 + arm, 1), p);
      canvas.drawLine(
        Offset(size.width - 1, size.height - c - 1),
        Offset(size.width - c - 1, size.height - 1),
        p,
      );
      canvas.drawLine(
        Offset(size.width - c - 1, size.height - 1),
        Offset(size.width - c - 1 - arm, size.height - 1),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_HoloFramePainter o) =>
      o.accent != accent ||
      o.fill != fill ||
      o.cut != cut ||
      o.glow != glow ||
      o.brackets != brackets ||
      o.scanlines != scanlines ||
      o.borderAlpha != borderAlpha;
}

// ─────────────────────────────────────────────────────────────────────────────
// Panels
// ─────────────────────────────────────────────────────────────────────────────

/// Holographic cockpit panel: chamfered card, glowing edge, corner brackets,
/// faint scanlines and an optional `// TITLE` strip.
class HoloPanel extends StatelessWidget {
  const HoloPanel({
    super.key,
    required this.child,
    this.title,
    this.titleTrailing,
    this.accent = SpaceColors.cyan,
    this.padding = const EdgeInsets.all(16),
    this.cut = 18,
    this.glow = 1,
    this.fill = SpaceColors.panelDeep,
    this.brackets = true,
  });

  final Widget child;
  final String? title;
  final Widget? titleTrailing;
  final Color accent;
  final EdgeInsets padding;
  final double cut;
  final double glow;
  final Color fill;
  final bool brackets;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return CustomPaint(
      painter: _HoloFramePainter(
        accent: accent,
        fill: fill,
        cut: cut,
        glow: glow,
        brackets: brackets,
        scanlines: true,
      ),
      child: Padding(
        padding: padding,
        child: title == null
            ? child
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: PanelTitle(title, color: accent)),
                      ?titleTrailing,
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(child: child),
                ],
              ),
      ),
    );
  }
}

/// `// TITLE` label used on panel headers.
class PanelTitle extends StatelessWidget {
  const PanelTitle(this.text, {super.key, this.color = SpaceColors.cyan});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    '// ${text.toUpperCase()}',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: hudLabel(11, color: color, spacing: 2.4),
  );
}

/// Popup entrance: scales and fades a panel in and plays [UiSound.open].
class PanelEntrance extends StatefulWidget {
  const PanelEntrance({super.key, required this.child, this.sound = true});
  final Widget child;
  final bool sound;

  @override
  State<PanelEntrance> createState() => _PanelEntranceState();
}

class _PanelEntranceState extends State<PanelEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void initState() {
    super.initState();
    if (widget.sound) AudioService.playUi(UiSound.open);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: t,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(t),
        child: widget.child,
      ),
    );
  }
}

/// Centred popup that always fits the screen: kept clear of notches,
/// [child] gets the room left by the pinned [footer], and only scrolls as a
/// last resort on tiny screens.
class HoloDialog extends StatelessWidget {
  const HoloDialog({
    super.key,
    required this.child,
    this.footer,
    this.maxWidth = 560,
    this.accent = SpaceColors.cyan,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 14),
    this.scrim = const Color(0xB3020510),
    this.sound = true,
  });

  final Widget child;
  final Widget? footer;

  /// Play [UiSound.open] on entry (off where the game already plays a cue).
  final bool sound;
  final double maxWidth;
  final Color accent;
  final String? title;
  final EdgeInsets padding;
  final Color scrim;

  @override
  Widget build(BuildContext context) {
    final footer = this.footer;
    return ColoredBox(
      color: scrim,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: PanelEntrance(
                sound: sound,
                child: HoloPanel(
                  accent: accent,
                  padding: padding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (title case final title?) ...[
                        PanelTitle(title, color: accent),
                        const SizedBox(height: 8),
                      ],
                      Flexible(child: SingleChildScrollView(child: child)),
                      if (footer != null) ...[
                        const SizedBox(height: 12),
                        footer,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Buttons
// ─────────────────────────────────────────────────────────────────────────────

enum HoloVariant { primary, secondary, ghost }

/// Shake + [UiSound.denied] for taps on something locked.
mixin _Denied<T extends StatefulWidget>
    on State<T>, TickerProviderStateMixin<T> {
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
    with TickerProviderStateMixin, _Denied {
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
              Text(
                widget.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hudLabel(widget.fontSize, color: fg, spacing: 2),
              ),
              if (widget.subtitle case final sub?) ...[
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
        painter: _HoloFramePainter(
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
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            painter: _HoloFramePainter(
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

extension on ChamferBorder {
  ShapeBorder copyWithSide(BorderSide side) => _SidedChamfer(cut, side);
}

class _SidedChamfer extends ChamferBorder {
  const _SidedChamfer(double cut, this.side) : super(cut: cut);
  final BorderSide side;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(
      chamferPath(rect.deflate(side.width / 2), cut),
      Paint()
        ..color = side.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = side.width,
    );
  }
}

/// Cockpit toggle row: icon, title, optional subtitle and a holo switch.
/// The whole row is the tap target; clicks up / down ([UiSound.toggleOn] /
/// [UiSound.toggleOff]) after the change, so turning Sound off is silent.
class HoloToggle extends StatelessWidget {
  const HoloToggle({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.accent = SpaceColors.cyan,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: title,
      child: InkWell(
        onTap: () {
          onChanged(!value);
          AudioService.playUi(value ? UiSound.toggleOff : UiSound.toggleOn);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: value ? accent : Colors.white38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14)),
                    if (subtitle case final sub?)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _HoloSwitch(value: value, accent: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoloSwitch extends StatelessWidget {
  const _HoloSwitch({required this.value, required this.accent});
  final bool value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 46,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: value ? accent.withValues(alpha: 0.25) : const Color(0x22FFFFFF),
        shape: const ChamferBorder(
          cut: 7,
        ).copyWithSide(BorderSide(color: value ? accent : Colors.white24)),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          decoration: ShapeDecoration(
            color: value ? accent : Colors.white38,
            shape: const ChamferBorder(cut: 5),
            shadows: value
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// Plain list row for settings-style actions.
class HoloListRow extends StatelessWidget {
  const HoloListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color = Colors.white60,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              AudioService.playUi(UiSound.select);
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14)),
                  if (subtitle case final sub?)
                    Text(
                      sub,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing case final t?)
              Text(
                t,
                style: const TextStyle(
                  color: SpaceColors.cyan,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Colors.white24,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Backdrop & screen scaffold
// ─────────────────────────────────────────────────────────────────────────────

class _Star {
  const _Star(this.x, this.y, this.r, this.layer, this.phase, this.tint);
  final double x, y, r;
  final int layer;
  final double phase;
  final Color tint;
}

final List<_Star> _stars = () {
  final rnd = math.Random(7);
  const tints = [Colors.white, Color(0xFFBDE9FF), Color(0xFFFFE7B8)];
  return [
    for (var i = 0; i < 160; i++)
      _Star(
        rnd.nextDouble(),
        rnd.nextDouble(),
        0.5 + rnd.nextDouble() * (i % 3 == 0 ? 1.4 : 0.8),
        i % 3,
        rnd.nextDouble() * math.pi * 2,
        tints[rnd.nextInt(tints.length)],
      ),
  ];
}();

/// Drifting three-layer parallax starfield over a deep-space nebula. Runs on
/// its own ticker, so it moves while the game engine is paused behind it.
class SpaceBackdrop extends StatefulWidget {
  const SpaceBackdrop({super.key, this.nebula = SpaceColors.cyan});

  /// Tint of the main nebula glow.
  final Color nebula;

  @override
  State<SpaceBackdrop> createState() => _SpaceBackdropState();
}

class _SpaceBackdropState extends State<SpaceBackdrop>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  final _time = ValueNotifier<double>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = spaceAnimationsOn(context);
    if (animate && _ticker == null) {
      _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)
        ..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SpacePainter(_time, widget.nebula),
        size: Size.infinite,
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  _SpacePainter(this.time, this.nebula) : super(repaint: time);
  final ValueListenable<double> time;
  final Color nebula;

  static const _speeds = [4.0, 9.0, 18.0]; // px/s per layer

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF070B1F), SpaceColors.bg, Color(0xFF03050D)],
        ).createShader(r),
    );
    // Nebula clouds breathing slowly.
    void cloud(Offset c, double radius, Color color, double alpha) {
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }

    final breathe = 0.85 + 0.15 * math.sin(t * 0.3);
    cloud(
      Offset(size.width * 0.78, size.height * 0.25),
      size.height * 0.9,
      nebula,
      0.13 * breathe,
    );
    cloud(
      Offset(size.width * 0.12, size.height * 0.95),
      size.height * 0.75,
      SpaceColors.violet,
      0.10 * (2 - breathe),
    );
    cloud(
      Offset(size.width * 0.45, size.height * 0.05),
      size.height * 0.5,
      const Color(0xFFE07A5F),
      0.04,
    );

    final paint = Paint();
    for (final s in _stars) {
      final w = size.width + 20;
      final x = (s.x * w - t * _speeds[s.layer]) % w - 10;
      final y = s.y * size.height;
      final twinkle = 0.55 + 0.45 * math.sin(t * (1.2 + s.layer) + s.phase);
      final a = (0.18 + 0.27 * s.layer) * twinkle;
      paint.color = s.tint.withValues(alpha: a.clamp(0, 1));
      canvas.drawCircle(Offset(x, y), s.r * (0.8 + 0.25 * s.layer), paint);
    }
  }

  @override
  bool shouldRepaint(_SpacePainter old) => old.nebula != nebula;
}

/// Full-screen cockpit screen: starfield, header bar (back button, title,
/// trailing chips) and a body.
class SpaceScreen extends StatelessWidget {
  const SpaceScreen({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
    this.accent = SpaceColors.cyan,
    this.trailing = const [],
    this.backLabel = 'Hangar',
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;
  final Color accent;
  final List<Widget> trailing;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: SpaceBackdrop(nebula: accent)),
        Positioned.fill(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Row(
                    children: [
                      HoloBackButton(onPressed: onBack, label: backLabel),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Text(
                          title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: hudLabel(18, color: accent, spacing: 3.5)
                              .copyWith(
                                shadows: [
                                  Shadow(
                                    color: accent.withValues(alpha: 0.6),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                        ),
                      ),
                      const Spacer(),
                      for (final w in trailing) ...[
                        const SizedBox(width: 8),
                        w,
                      ],
                    ],
                  ),
                ),
                _HeaderRule(color: accent),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderRule extends StatelessWidget {
  const _HeaderRule({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.6),
          color.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared bits
// ─────────────────────────────────────────────────────────────────────────────

/// Segmented bar with [value] in 0–1 (cockpit gauge look).
class HoloGauge extends StatelessWidget {
  const HoloGauge({
    super.key,
    required this.value,
    this.color = SpaceColors.cyan,
    this.height = 6,
    this.segments = 20,
  });

  final double value;
  final Color color;
  final double height;
  final int segments;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(
      painter: _GaugePainter(value.clamp(0.0, 1.0), color, segments),
      size: Size.infinite,
    ),
  );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value, this.color, this.segments);
  final double value;
  final Color color;
  final int segments;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.0;
    final w = (size.width - gap * (segments - 1)) / segments;
    final lit = value * segments;
    final on = Paint()..color = color;
    final off = Paint()..color = const Color(0x22FFFFFF);
    for (var i = 0; i < segments; i++) {
      final rect = Rect.fromLTWH(i * (w + gap), 0, w, size.height);
      if (i + 1 <= lit) {
        canvas.drawRect(rect, on);
      } else if (i < lit) {
        canvas.drawRect(rect, off);
        canvas.drawRect(
          Rect.fromLTWH(rect.left, 0, w * (lit - i), size.height),
          on,
        );
      } else {
        canvas.drawRect(rect, off);
      }
    }
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.value != value || o.color != color || o.segments != segments;
}

/// Progress ring with [value] in 0–1 and a [child] (label/icon) inside.
class HoloRing extends StatelessWidget {
  const HoloRing({
    super.key,
    required this.value,
    this.color = SpaceColors.cyan,
    this.size = 44,
    this.stroke = 3.5,
    this.child,
  });

  final double value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RingPainter(value.clamp(0.0, 1.0), color, stroke),
      child: Center(child: child),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.stroke);
  final double value;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = SpaceColors.track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (value <= 0) return;
    final sweep = math.pi * 2 * value;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.value != value || o.color != color || o.stroke != stroke;
}

/// `1m02s` / `12.4s`.
String formatFlightTime(double seconds) {
  if (seconds.isInfinite || seconds.isNaN) return '--';
  if (seconds >= 60) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toStringAsFixed(0).padLeft(2, '0');
    return '${m}m${s}s';
  }
  return '${seconds.toStringAsFixed(1)}s';
}
