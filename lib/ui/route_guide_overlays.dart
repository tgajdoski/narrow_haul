import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/ui/space_ui.dart';

const _guideColor = SpaceColors.cyan;

/// Game-over help for a stuck pilot: "Show route" and "Watch a demo flight".
/// Nothing at all unless [NarrowHaulGame.canShowRoute].
class RouteHelpButtons extends StatelessWidget {
  const RouteHelpButtons({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    if (!game.canShowRoute) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (!game.routeGuideOn) ...[
              Expanded(
                child: HoloButton(
                  label: 'Show route',
                  icon: Icons.route_rounded,
                  height: 40,
                  fontSize: 11.5,
                  onPressed: game.showRoute,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: HoloButton(
                label: 'Watch a demo',
                icon: Icons.smart_display_outlined,
                height: 40,
                fontSize: 11.5,
                onPressed: game.startDemoFlight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'A guided flight can earn up to 2★',
          textAlign: TextAlign.center,
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
              child: HoloChip(
                icon: Icons.smart_display_outlined,
                label: 'DEMO FLIGHT',
                color: _guideColor,
                highlight: true,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: ValueListenableBuilder<bool>(
                valueListenable: game.demoFinished,
                builder: (context, done, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HoloButton(
                      label: 'Hangar',
                      icon: Icons.home_rounded,
                      sound: UiSound.back,
                      expand: false,
                      onPressed: game.backToMenu,
                    ),
                    const SizedBox(width: 12),
                    HoloButton.primary(
                      label: done ? 'Fly it yourself' : 'Take the controls',
                      icon: Icons.flight_takeoff_rounded,
                      accent: done ? SpaceColors.coral : _guideColor,
                      sound: UiSound.launch,
                      height: 46,
                      fontSize: 14,
                      expand: false,
                      onPressed: game.takeControlsFromDemo,
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
    return HoloToggle(
      icon: Icons.route_rounded,
      title: 'Route guide',
      subtitle: 'Guided flights earn up to 2★',
      value: game.routeGuideOn,
      onChanged: (v) => setState(() => game.setRouteGuide(v)),
    );
  }
}
