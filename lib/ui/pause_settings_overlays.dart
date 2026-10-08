import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/ui/route_guide_overlays.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/store_feedback.dart';
import 'package:narrow_haul/ui/tap_sound.dart';
import 'package:url_launcher/url_launcher.dart';

const _panelColor = SpaceColors.panel;

/// Mid-flight pause menu ('pause' overlay): one wide cockpit panel, every
/// action in a single row so it fits a landscape phone.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    return HoloDialog(
      maxWidth: 620,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAUSED',
                      style:
                          hudLabel(
                            24,
                            color: SpaceColors.cyanBright,
                            spacing: 5,
                          ).copyWith(
                            shadows: const [
                              Shadow(color: SpaceColors.cyan, blurRadius: 14),
                            ],
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      game.currentLevelDef.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (game.routeGuideAvailable)
                SizedBox(width: 250, child: RouteGuideToggle(game: game)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 68,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: HoloButton.primary(
                    label: 'Resume',
                    icon: Icons.play_arrow_rounded,
                    sound: UiSound.close,
                    height: 68,
                    fontSize: 18,
                    onPressed: game.resumeGame,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HoloTile(
                    icon: Icons.replay_rounded,
                    label: 'Restart',
                    accent: SpaceColors.coral,
                    sound: UiSound.launch,
                    onTap: game.restartLevel,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HoloTile(
                    icon: Icons.tune_rounded,
                    label: 'Settings',
                    accent: Colors.white70,
                    onTap: () {
                      game.overlays.remove('pause');
                      game.overlays.add('settings');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HoloTile(
                    icon: Icons.home_rounded,
                    label: 'Hangar',
                    sound: UiSound.back,
                    onTap: game.backToMenu,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

  void _back() {
    final game = widget.game;
    game.overlays.remove('settings');
    game.overlays.add(game.isPaused ? 'pause' : 'menu');
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
        if (!kReleaseMode) _FlightTuningSection(game: widget.game),
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

/// Remove-ads / Supporter Pack, Restore purchases and the UMP privacy entry
/// point (only shown where consent rules require it).
class _PurchasesSection extends StatelessWidget {
  const _PurchasesSection({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final m = MonetizationService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: m.entitlements,
      builder: (context, _, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!m.adsRemoved && m.canBuy(ProductIds.removeAds))
            _row(
              icon: Icons.block_rounded,
              title: 'Remove ads',
              subtitle:
                  'No more ads between missions. '
                  'Rewarded ads stay optional.',
              trailing: m.priceOf(ProductIds.removeAds),
              onTap: () => buyWithFeedback(context, ProductIds.removeAds),
            ),
          if (m.canBuy(ProductIds.supporterPack) &&
              !ProgressService.instance.isProductGranted(
                ProductIds.supporterPack,
              ))
            _row(
              icon: Icons.diamond_outlined,
              title: 'Supporter Pack',
              subtitle:
                  'Remove ads + Supporter Livery + '
                  '${ProductIds.supporterCoins} 💰',
              trailing: m.priceOf(ProductIds.supporterPack),
              onTap: () => buyWithFeedback(context, ProductIds.supporterPack),
            ),
          if (m.adsRemoved)
            _row(
              icon: Icons.favorite_rounded,
              title: 'Ads removed',
              subtitle: 'Thanks for supporting Narrow Haul!',
            ),
          if (m.storeAvailable)
            _row(
              icon: Icons.restore_rounded,
              title: 'Restore purchases',
              onTap: () => restoreWithFeedback(context),
            ),
          // Dev builds only: drop sandbox test purchases so ads show again.
          if (!kReleaseMode && ProgressService.instance.hasPurchased)
            _row(
              icon: Icons.bug_report_outlined,
              title: 'Reset purchases (dev)',
              subtitle: 'Forget test purchases on this device',
              onTap: () async {
                await ProgressService.instance.debugClearPurchases();
                m.entitlements.value++;
                onChanged();
              },
            ),
          ValueListenableBuilder<bool>(
            valueListenable: m.privacyOptionsRequired,
            builder: (context, required, _) => !required
                ? const SizedBox.shrink()
                : _row(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy options',
                    subtitle: 'Change your ad consent choices',
                    onTap: m.showPrivacyOptions,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    String? trailing,
    Future<void> Function()? onTap,
  }) {
    return HoloListRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap == null
          ? null
          : () async {
              await onTap();
              onChanged();
            },
    );
  }
}

/// Privacy policy, support, open-source licenses and (from the main menu
/// only, never mid-flight) Reset progress.
class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.game});

  final NarrowHaulGame game;

  static final _privacyUrl = Uri.parse('https://zafrk.com/narrow-haul/privacy');
  static final _supportUrl = Uri.parse('https://zafrk.com/narrow-haul/support');

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _linkRow(
          Icons.shield_outlined,
          'Privacy policy',
          () => _open(_privacyUrl),
        ),
        _linkRow(
          Icons.help_outline_rounded,
          'Support',
          () => _open(_supportUrl),
        ),
        _linkRow(
          Icons.description_outlined,
          'Licenses',
          () => showLicensePage(
            context: context,
            applicationName: 'Narrow Haul',
            applicationLegalese: '© 2026 zafrk',
          ),
        ),
        if (!game.isPaused)
          _linkRow(Icons.favorite_border_rounded, 'Credits · Delivered by', () {
            game.overlays.remove('settings');
            game.overlays.add('menu');
            game.creditsVisible.value = true;
          }),
        if (!game.isPaused)
          _linkRow(
            Icons.restart_alt_rounded,
            'Reset progress',
            () => _confirmReset(context),
            color: const Color(0xFFFF6B6B),
          ),
      ],
    );
  }

  static Future<void> _open(Uri url) async {
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser available: nothing sensible to do in a game.
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panelColor,
        title: const Text('Reset progress?'),
        content: const Text(
          'This erases your stars, times, rank, coins, achievements and Garage '
          'items. Purchases (ad removal, Supporter Livery) and settings are '
          'kept. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: withTapSound(() => Navigator.of(context).pop(false)),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: withTapSound(() => Navigator.of(context).pop(true)),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF6B6B),
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ProgressService.instance.resetProgress(
      keepCosmeticIds: {
        for (final item in CosmeticsService.all)
          if (item.supporterOnly) item.id,
      },
    );
    CosmeticsService.clearTrials();
    game.applySettings();
    game.overlays.remove('settings');
    game.overlays.add('menu');
  }

  Widget _linkRow(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color color = Colors.white60,
  }) {
    return HoloListRow(icon: icon, title: title, onTap: onTap, color: color);
  }
}

/// Dev builds only: live handling knobs ([FlightTuning]) to find the turn
/// feel on a phone. Changes apply at once (open Settings from the pause menu
/// mid-flight) and persist on release of the slider.
class _FlightTuningSection extends StatefulWidget {
  const _FlightTuningSection({required this.game});

  final NarrowHaulGame game;

  @override
  State<_FlightTuningSection> createState() => _FlightTuningSectionState();
}

class _FlightTuningSectionState extends State<_FlightTuningSection> {
  void _change({double? turn, double? expo, double? spin}) {
    setState(() => FlightTuning.set(turn: turn, expo: expo, spin: spin));
  }

  Future<void> _save() => ProgressService.instance.setDevFlightTuning(
    FlightTuning.turnMul,
    FlightTuning.curveExpo,
    FlightTuning.spinUp,
  );

  @override
  Widget build(BuildContext context) {
    final spec = widget.game.ship?.spec ?? kKestrel;
    final secs = spec.secondsPerFullRotation / FlightTuning.turnMul;
    final degPerSec = 360 / secs;
    final half = FlightTuning.shapeAxis(0.5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const PanelTitle('Flight tuning (dev)', color: SpaceColors.gold),
        _slider(
          label: 'Turn speed ×${FlightTuning.turnMul.toStringAsFixed(2)}',
          detail:
              '${spec.name}: ${secs.toStringAsFixed(1)} s / 360° '
              '(${degPerSec.round()}°/s)',
          value: FlightTuning.turnMul,
          min: FlightTuning.turnMulMin,
          max: FlightTuning.turnMulMax,
          divisions: 25,
          onChanged: (v) => _change(turn: v),
        ),
        Row(
          children: [
            Expanded(
              child: _slider(
                label: 'Stick curve ${FlightTuning.curveExpo.toStringAsFixed(2)}',
                detail: 'Half stick → ${(half * 100).round()}% turn',
                value: FlightTuning.curveExpo,
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: (v) => _change(expo: v),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 36,
              child: CustomPaint(
                painter: _CurvePainter(FlightTuning.curveExpo),
              ),
            ),
          ],
        ),
        _slider(
          label:
              'Spin-up ${(FlightTuning.spinUp * 1000).round()} ms',
          detail: FlightTuning.spinUp == 0
              ? 'Instant (stock)'
              : 'Time to full turn rate',
          value: FlightTuning.spinUp,
          min: 0,
          max: FlightTuning.spinUpMax,
          divisions: 12,
          onChanged: (v) => _change(spin: v),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: FlightTuning.isStock
                ? null
                : () {
                    _change(turn: 1.0, expo: 0.0, spin: 0.0);
                    _save();
                  },
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reset to stock'),
          ),
        ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required String detail,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SpaceColors.textFaint,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: SpaceColors.gold,
              inactiveTrackColor: SpaceColors.track,
              thumbColor: SpaceColors.gold,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: SizedBox(
              height: 26,
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
                onChangeEnd: (_) => _save(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stick → turn-rate response for the current curve (dashed: linear).
class _CurvePainter extends CustomPainter {
  _CurvePainter(this.expo);

  final double expo;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, frame);
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()..color = const Color(0x33FFFFFF),
    );
    final path = Path();
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      final y = FlightTuning.shapeAxis(x, expo: expo);
      final p = Offset(x * size.width, size.height * (1 - y));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = SpaceColors.gold
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.expo != expo;
}
