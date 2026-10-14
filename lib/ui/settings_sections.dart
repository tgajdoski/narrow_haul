part of 'settings_overlay.dart';

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
              subtitle: ProgressService.instance.hasFullGame
                  ? 'Supporter Livery + ${ProductIds.supporterCoins} 💰 '
                      '(you already own the Full Game)'
                  : 'Full Game + Supporter Livery + '
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
          if (m.adFreeUntil case final until?)
            _row(
              icon: Icons.favorite_rounded,
              title: 'Ad-free until '
                  '${MaterialLocalizations.of(context).formatShortMonthDay(until)}',
              subtitle: 'Thanks for your support!',
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
        if (GamesService.supported) const _GamesRows(),
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
          Icons.mail_outline_rounded,
          'Send feedback · ideas',
          () => openFeedbackMail(
            context,
            levelId: game.currentLevelDef.saveId,
            source: 'settings',
          ),
        ),
        if (!game.isPaused)
          _linkRow(Icons.favorite_border_rounded, 'Credits · Approved by', () {
            game.closeSettings();
            game.creditsVisible.value = true;
          }),
        _linkRow(
          Icons.description_outlined,
          'Open-source licenses',
          () => openLicenses(context),
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
      builder: (context) => HoloDialog(
        title: 'Reset progress?',
        accent: SpaceColors.red,
        maxWidth: 440,
        scrim: Colors.transparent,
        footer: Row(
          children: [
            Expanded(
              child: HoloButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HoloButton(
                label: 'Reset',
                accent: SpaceColors.red,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
        child: const Text(
          'This erases your stars, times, rank, coins, achievements and Garage '
          'items. Purchases (ad removal, Supporter Livery) and settings are '
          'kept. This cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
        ),
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

/// Play Games / Game Center: achievements and the stars leaderboard once
/// signed in, else a row to sign in (cloud save comes with it).
class _GamesRows extends StatelessWidget {
  const _GamesRows();

  @override
  Widget build(BuildContext context) {
    final name = GamesService.platformName;
    return ValueListenableBuilder<bool>(
      valueListenable: GamesService.signedIn,
      builder: (context, signedIn, _) => signedIn
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HoloListRow(
                  icon: Icons.emoji_events_outlined,
                  title: '$name achievements',
                  subtitle: 'Progress saved to the cloud',
                  onTap: GamesService.showAchievements,
                ),
                HoloListRow(
                  icon: Icons.leaderboard_outlined,
                  title: 'Star leaderboard',
                  onTap: GamesService.showLeaderboard,
                ),
              ],
            )
          : HoloListRow(
              icon: Icons.cloud_sync_outlined,
              title: 'Sign in to $name',
              subtitle: 'Cloud save, achievements, leaderboard',
              onTap: () => unawaited(GamesService.signIn()),
            ),
    );
  }
}
