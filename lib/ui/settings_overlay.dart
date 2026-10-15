import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/fleet_service.dart';
import 'package:narrow_haul/game/services/games_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/motion_input.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/reminder_service.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/tilt_steer.dart';
import 'package:narrow_haul/ui/feedback_mail.dart';
import 'package:narrow_haul/ui/licenses_screen.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/store_feedback.dart';
import 'package:url_launcher/url_launcher.dart';

part 'settings_sections.dart';

/// Settings ('settings' overlay) — opened from the hangar or the pause menu,
/// and returns to whichever opened it. Switches on the left, purchases and
/// links on the right (the only part that may scroll).
class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  ProgressService get _p => ProgressService.instance;

  Future<void> _set(Future<void> Function(bool) setter, bool v) async {
    await setter(v);
    widget.game.applySettings();
    if (mounted) setState(() {});
  }

  Future<void> _setReminders(bool v) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!v) {
      await ReminderService.disable();
    } else if (!await ReminderService.enable(where: 'settings')) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text("Notifications are off for Narrow Haul. Turn them on in the phone's Settings."),
          behavior: SnackBarBehavior.floating,
        ));
    }
    if (mounted) setState(() {});
  }

  void _back() {
    widget.game.closeSettings();
  }

  @override
  Widget build(BuildContext context) {
    final toggles = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HoloToggle(
          icon: Icons.volume_up_rounded,
          title: 'Sound effects',
          value: _p.soundEnabled,
          onChanged: (v) => _set(_p.setSoundEnabled, v),
        ),
        HoloToggle(
          icon: Icons.music_note_rounded,
          title: 'Music',
          value: _p.musicEnabled,
          onChanged: (v) => _set(_p.setMusicEnabled, v),
        ),
        HoloToggle(
          icon: Icons.vibration_rounded,
          title: 'Vibration',
          subtitle: 'Crash, landing and rope hook',
          value: _p.hapticsEnabled,
          onChanged: (v) => _set(_p.setHapticsEnabled, v),
        ),
        if (ReminderService.supported)
          HoloToggle(
            icon: Icons.notifications_none_rounded,
            title: 'Reminders',
            subtitle: 'Daily dispatch and the next run, at most once a day',
            value: _p.remindersEnabled ?? false,
            onChanged: _setReminders,
          ),
        HoloToggle(
          icon: Icons.swap_horiz_rounded,
          title: 'Left-handed controls',
          subtitle: 'Thrust on the left, steering on the right',
          value: _p.leftHanded,
          onChanged: (v) => _set(_p.setLeftHanded, v),
        ),
        HoloToggle(
          icon: Icons.map_outlined,
          title: 'Minimap',
          value: _p.minimapEnabled,
          onChanged: (v) => _set(_p.setMinimapEnabled, v),
        ),
        if (MotionInput.available)
          _PresetRow<bool>(
            icon: Icons.screen_rotation_alt_rounded,
            title: 'Steer with',
            values: const [true, false],
            value: FlightTuning.tilt,
            label: (tilt) => tilt ? 'Tilt' : 'Joystick',
            blurb: (tilt) => tilt
                ? 'Tilt the phone like a wheel, no stick on screen'
                : 'The on-screen stick',
            onChanged: (v) {
              setState(() => FlightTuning.tilt = v);
              _p.setTiltSteer(v);
            },
          ),
        if (!FlightTuning.tilt || !MotionInput.available)
          _PresetRow<SteerMode>(
            icon: Icons.rotate_right_rounded,
            title: 'Joystick',
            values: SteerMode.values,
            value: FlightTuning.steer,
            label: (m) => m.label,
            blurb: (m) => m.blurb,
            onChanged: (m) {
              setState(() => FlightTuning.steer = m);
              _p.setSteerMode(m.name);
            },
          ),
        if (FlightTuning.tilt && MotionInput.available) ...[
          _PresetRow<TiltMode>(
            icon: Icons.screen_rotation_rounded,
            title: 'Tilt mode',
            values: TiltMode.values,
            value: FlightTuning.tiltMode,
            label: (m) => m.label,
            blurb: (m) => m.blurb,
            onChanged: (m) {
              setState(() => FlightTuning.tiltMode = m);
              _p.setTiltMode(m.name);
            },
          ),
          _PresetRow<TiltSensitivity>(
            icon: Icons.tune_rounded,
            title: 'Tilt sensitivity',
            values: TiltSensitivity.values,
            value: FlightTuning.tiltSensitivity,
            label: (m) => m.label,
            blurb: (m) => m.blurb,
            onChanged: (m) {
              setState(() => FlightTuning.tiltSensitivity = m);
              _p.setTiltSensitivity(m.name);
            },
          ),
        ],
        _PresetRow<CameraMode>(
          icon: Icons.videocam_outlined,
          title: 'Camera',
          values: CameraMode.values,
          value: FlightTuning.camera,
          label: (m) => m.label,
          blurb: (m) => m.blurb,
          onChanged: (m) {
            setState(() => FlightTuning.camera = m);
            _p.setCameraMode(m.name);
          },
        ),
        HoloListRow(
          icon: Icons.zoom_in_rounded,
          title: 'Zoom',
          subtitle: FlightTuning.cameraZoom == 1
              ? 'Pinch with two fingers in flight (mouse wheel or + / −)'
              : 'Tap to reset · pinch with two fingers in flight',
          trailing: '${FlightTuning.cameraZoom.toStringAsFixed(1)}×',
          onTap: FlightTuning.cameraZoom == 1
              ? null
              : () {
                  setState(() => FlightTuning.cameraZoom = 1);
                  _p.setCameraZoom(1);
                },
        ),
      ],
    );

    final panel = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: PanelEntrance(
              child: HoloPanel(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        HoloBackButton(
                          onPressed: _back,
                          label: widget.game.isPaused ? 'Pause' : 'Hangar',
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'SETTINGS',
                          style: hudLabel(
                            18,
                            color: SpaceColors.cyan,
                            spacing: 3.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const PanelTitle('Cockpit'),
                                const SizedBox(height: 4),
                                Flexible(
                                  child: SingleChildScrollView(child: toggles),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            height: 200,
                            color: const Color(0x2200B4D8),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const PanelTitle('Account & info'),
                                const SizedBox(height: 4),
                                Flexible(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _PurchasesSection(
                                          onChanged: () => setState(() {}),
                                        ),
                                        _AboutSection(game: widget.game),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.game.isPaused) {
      return ColoredBox(color: const Color(0xB3020510), child: panel);
    }
    return Stack(
      children: [
        const Positioned.fill(child: SpaceBackdrop()),
        Positioned.fill(child: panel),
      ],
    );
  }
}

/// Cockpit preset row: tap cycles through [values]; the chip shows the
/// current one, the subtitle says what it does.
class _PresetRow<T> extends StatelessWidget {
  const _PresetRow({
    required this.icon,
    required this.title,
    required this.values,
    required this.value,
    required this.label,
    required this.blurb,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final List<T> values;
  final T value;
  final String Function(T) label;
  final String Function(T) blurb;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title: ${label(value)}',
      child: InkWell(
        onTap: () {
          onChanged(values[(values.indexOf(value) + 1) % values.length]);
          AudioService.playUi(UiSound.select);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: SpaceColors.cyan),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14)),
                    MarqueeText(
                      blurb(value),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: HoloChip(label: '${label(value)}  ›', highlight: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
