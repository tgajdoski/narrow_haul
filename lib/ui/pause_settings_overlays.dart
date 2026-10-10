import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/fleet_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
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
                      game.openSettingsFromPause();
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
        _PresetRow<SteerMode>(
          icon: Icons.rotate_right_rounded,
          title: 'Steering',
          values: SteerMode.values,
          value: FlightTuning.steer,
          label: (m) => m.label,
          blurb: (m) => m.blurb,
          onChanged: (m) {
            setState(() => FlightTuning.steer = m);
            _p.setSteerMode(m.name);
          },
        ),
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
          if (!ProgressService.instance.hasFullGame && m.canBuy(ProductIds.fullGame))
            _row(
              icon: Icons.all_inclusive_rounded,
              title: 'Full Game',
              subtitle:
                  'Every Expedition, and no ads between missions. '
                  'Yours for good.',
              trailing: m.priceOf(ProductIds.fullGame),
              onTap: () => buyWithFeedback(context, ProductIds.fullGame),
            ),
          if (m.canBuy(ProductIds.supporterPack) &&
              !ProgressService.instance.isProductGranted(
                ProductIds.supporterPack,
              ))
            _row(
              icon: Icons.diamond_outlined,
              title: 'Supporter Pack',
              subtitle:
                  'Full Game + Supporter Livery + '
                  '${ProductIds.supporterCoins} 💰',
              trailing: m.priceOf(ProductIds.supporterPack),
              onTap: () => buyWithFeedback(context, ProductIds.supporterPack),
            ),
          if ((m.canBuy(ProductIds.fleetPass) || kFleetPreview) && !FleetService.ownsAll)
            _row(
              icon: Icons.flight_rounded,
              title: 'Fleet Pass',
              subtitle: 'Every ship now, and every ship to come. '
                  'Each one is also earned by play.',
              trailing: m.priceOf(ProductIds.fleetPass),
              onTap: () => buyWithFeedback(context, ProductIds.fleetPass),
            ),
          if (m.adsRemoved)
            _row(
              icon: Icons.favorite_rounded,
              title: ProgressService.instance.hasFullGame ? 'Full Game' : 'Ads removed',
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
            game.closeSettings();
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
    game.closeSettings();
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
                    Text(
                      blurb(value),
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
