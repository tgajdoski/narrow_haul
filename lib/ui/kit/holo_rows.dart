
import 'package:flutter/material.dart';

import '../../game/services/audio_service.dart';
import 'chamfer.dart';
import 'marquee_text.dart';
import 'tokens.dart';


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
                      MarqueeText(
                        sub,
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
