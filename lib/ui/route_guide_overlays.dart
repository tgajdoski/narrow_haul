import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/ui/fonts.dart';

const _guideColor = Color(0xFF00B4D8);

/// Game-over help for a stuck pilot: "Show route" and "Watch a demo flight".
/// Nothing at all unless [NarrowHaulGame.canShowRoute].
class RouteHelpButtons extends StatelessWidget {
  const RouteHelpButtons({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    if (!game.canShowRoute) return const SizedBox.shrink();
    final style = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      side: const BorderSide(color: Color(0x6600B4D8)),
      foregroundColor: _guideColor,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (!game.routeGuideOn) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: game.showRoute,
                  icon: const Icon(Icons.route_rounded, size: 18),
                  label: const Text('Show route'),
                  style: style,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: game.startDemoFlight,
                icon: const Icon(Icons.smart_display_outlined, size: 18),
                label: const Text('Watch a demo'),
                style: style,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'A guided flight can earn up to 2★',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}

/// 'demo' overlay: a badge over the replay and a way back to the controls.
class DemoFlightOverlay extends StatelessWidget {
  const DemoFlightOverlay({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xAA0D1B2A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x6600B4D8)),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Text(
                    'DEMO FLIGHT',
                    style: TextStyle(
                      fontFamily: kDisplayFont,
                      color: _guideColor,
                      letterSpacing: 3,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: ValueListenableBuilder<bool>(
                valueListenable: game.demoFinished,
                builder: (context, done, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: game.backToMenu,
                      icon: const Icon(Icons.home_rounded, size: 18),
                      label: const Text('Menu'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: game.takeControlsFromDemo,
                      icon: const Icon(Icons.flight_takeoff_rounded, size: 18),
                      label: Text(
                        done ? 'Fly it yourself' : 'Take the controls',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: done ? const Color(0xFFE07A5F) : _guideColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pause-menu switch for a level whose route was unlocked.
class RouteGuideToggle extends StatefulWidget {
  const RouteGuideToggle({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  State<RouteGuideToggle> createState() => _RouteGuideToggleState();
}

class _RouteGuideToggleState extends State<RouteGuideToggle> {
  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return SwitchListTile(
      value: game.routeGuideOn,
      onChanged: (v) => setState(() => game.setRouteGuide(v)),
      activeThumbColor: _guideColor,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      secondary: const Icon(Icons.route_rounded, color: Colors.white60),
      title: const Text('Route guide', style: TextStyle(fontSize: 14)),
      subtitle: const Text(
        'Guided flights earn up to 2★',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }
}
