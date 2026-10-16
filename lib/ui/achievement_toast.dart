import 'dart:async';

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// Slides a banner in from the top when an achievement is announced
/// mid-flight.
class AchievementToastHost extends StatefulWidget {
  const AchievementToastHost({super.key});

  @override
  State<AchievementToastHost> createState() => _AchievementToastHostState();
}

class _AchievementToastHostState extends State<AchievementToastHost> {
  AchievementMeta? _shown;
  bool _visible = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    AchievementService.announced.addListener(_onAnnounced);
  }

  @override
  void dispose() {
    AchievementService.announced.removeListener(_onAnnounced);
    super.dispose();
  }

  void _onAnnounced() {
    final a = AchievementService.announced.value;
    if (a == null) return;
    final token = ++_token;
    AudioService.playAchievement();
    setState(() {
      _shown = a;
      _visible = true;
    });
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted && token == _token) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _shown;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, -1.5),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            child: Center(
              child: a == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: HoloPanel(
                        accent: SpaceColors.gold,
                        cut: 12,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(a.icon, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'ACHIEVEMENT UNLOCKED',
                                  style: TextStyle(
                                    color: Color(0xFFFFD166),
                                    fontSize: 9,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${a.title}  ·  +100 XP',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
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
