
import 'package:flutter/material.dart';

import '../../game/services/audio_service.dart';
import 'holo_frame.dart';
import 'marquee_text.dart';
import 'tokens.dart';


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
      painter: HoloFramePainter(
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
  Widget build(BuildContext context) => MarqueeText(
    '// ${text.toUpperCase()}',
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
