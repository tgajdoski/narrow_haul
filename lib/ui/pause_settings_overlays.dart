import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/ui/route_guide_overlays.dart';
import 'package:narrow_haul/ui/tap_sound.dart';
import 'package:url_launcher/url_launcher.dart';

const _panelColor = Color(0xFF0D1B2A);
const _accent = Color(0xFF00B4D8);

/// Shared dimmed backdrop + rounded card used by pause and settings.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.maxWidth = 380});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Material(
                color: _panelColor,
                borderRadius: BorderRadius.circular(16),
                // Scrolls rather than overflows on short landscape phones.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mid-flight pause menu ('pause' overlay).
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final buttonPad = const EdgeInsets.symmetric(vertical: 12);
    return _Panel(
      maxWidth: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PAUSED',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: _accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            game.currentLevelDef.name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: withTapSound(game.resumeGame),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              'Resume',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              padding: buttonPad,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: withTapSound(game.restartLevel),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Restart'),
            style: OutlinedButton.styleFrom(padding: buttonPad),
          ),
          if (game.routeGuideAvailable) ...[
            const SizedBox(height: 6),
            RouteGuideToggle(game: game),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: withTapSound(() {
                    game.overlays.remove('pause');
                    game.overlays.add('settings');
                  }),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Settings'),
                  style: OutlinedButton.styleFrom(padding: buttonPad),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: withTapSound(game.backToMenu),
                  icon: const Icon(Icons.home_rounded, size: 18),
                  label: const Text('Menu'),
                  style: OutlinedButton.styleFrom(padding: buttonPad),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Settings ('settings' overlay) — opened from the menu or the pause menu,
/// and returns to whichever opened it.
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
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: withTapSound(_back),
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white70,
              ),
              Text(
                'SETTINGS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: _accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _toggle(
            icon: Icons.volume_up_rounded,
            title: 'Sound effects',
            value: _p.soundEnabled,
            onChanged: (v) => _set(_p.setSoundEnabled, v),
          ),
          _toggle(
            icon: Icons.music_note_rounded,
            title: 'Music',
            value: _p.musicEnabled,
            onChanged: (v) => _set(_p.setMusicEnabled, v),
          ),
          _toggle(
            icon: Icons.vibration_rounded,
            title: 'Vibration',
            subtitle: 'Crash, landing and rope hook',
            value: _p.hapticsEnabled,
            onChanged: (v) => _set(_p.setHapticsEnabled, v),
          ),
          _toggle(
            icon: Icons.swap_horiz_rounded,
            title: 'Left-handed controls',
            subtitle: 'Thrust on the left, steering on the right',
            value: _p.leftHanded,
            onChanged: (v) => _set(_p.setLeftHanded, v),
          ),
          _toggle(
            icon: Icons.map_outlined,
            title: 'Minimap',
            value: _p.minimapEnabled,
            onChanged: (v) => _set(_p.setMinimapEnabled, v),
          ),
          const Divider(color: Color(0x22FFFFFF), height: 20),
          _PurchasesSection(onChanged: () => setState(() {})),
          const Divider(color: Color(0x22FFFFFF), height: 20),
          _AboutSection(game: widget.game),
        ],
      ),
    );
  }

  Widget _toggle({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: withTapSoundValue(onChanged),
      activeThumbColor: _accent,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      secondary: Icon(icon, color: Colors.white60),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
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
              onTap: () => m.buy(ProductIds.removeAds),
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
              onTap: () => m.buy(ProductIds.supporterPack),
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
              onTap: m.restore,
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
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon, color: Colors.white60),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
      trailing: trailing == null
          ? null
          : Text(
              trailing,
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.w700,
              ),
            ),
      onTap: withTapSound(onTap == null
          ? null
          : () async {
              await onTap();
              onChanged();
            }),
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
        _linkRow(Icons.shield_outlined, 'Privacy policy', () => _open(_privacyUrl)),
        _linkRow(Icons.help_outline_rounded, 'Support', () => _open(_supportUrl)),
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
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF6B6B)),
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
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      onTap: withTapSound(onTap),
    );
  }
}
