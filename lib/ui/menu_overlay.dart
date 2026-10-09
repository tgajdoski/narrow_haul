import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/ui/career_widgets.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/tow_art.dart';
import 'package:narrow_haul/game/overlay_ids.dart';

/// Main menu ('menu' overlay): the hangar. LAUNCH flies the next mission,
/// the tile rail opens every other screen, and the top bar carries the
/// pilot's rank and status chips. Fits a landscape phone without scrolling.
class MenuOverlay extends StatefulWidget {
  const MenuOverlay({super.key, required this.game});
  final NarrowHaulGame game;

  @override
  State<MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<MenuOverlay> {
  bool _contractsOpen = false;

  NarrowHaulGame get game => widget.game;

  void _toggleContracts() {
    AudioService.playUi(_contractsOpen ? UiSound.close : UiSound.open);
    setState(() => _contractsOpen = !_contractsOpen);
  }

  @override
  Widget build(BuildContext context) {
    final p = ProgressService.instance;
    final totalStars = LevelRegistry.totalStars();
    final maxStars = LevelRegistry.totalLevels * 3;
    final coins = p.getCosmeticCurrency();
    final dailyDone = p.isDailyChallengeComplete();
    final streak = p.getDailyStreak();
    final next = LevelRegistry.nextLevelIndex();
    final (world, indexInWorld) = LevelRegistry.worldOf(next);
    final nextDef = LevelRegistry.defAt(next);
    final contracts = ContractsService.isUnlocked
        ? ContractsService.today()
        : null;

    final topBar = Row(
      children: [
        Flexible(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AudioService.playUi(UiSound.select);
              game.openScreen(OverlayIds.pilotProfile);
            },
            child: CareerProgress(xp: p.getXp(), badgeSize: 34, compact: true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  HoloChip(
                    leading: const StarIcon(filled: true, size: 13),
                    label: '$totalStars/$maxStars',
                    color: SpaceColors.gold,
                  ),
                  const SizedBox(width: 8),
                  HoloChip(
                    leading: const Text('💰', style: TextStyle(fontSize: 12)),
                    label: '$coins',
                    color: SpaceColors.green,
                  ),
                  if (dailyDone) ...[
                    const SizedBox(width: 8),
                    HoloChip(
                      icon: Icons.task_alt_rounded,
                      label: [
                        'DAILY ✓',
                        if (streak > 0) '🔥$streak',
                        if (p.getDailyBestTime() case final t?)
                          formatFlightTime(t),
                      ].join(' '),
                      color: SpaceColors.green,
                    ),
                  ],
                  if (contracts != null) ...[
                    const SizedBox(width: 8),
                    HoloChip(
                      icon: Icons.assignment_outlined,
                      label:
                          '${contracts.where((c) => c.done).length}/${contracts.length}',
                      color: SpaceColors.cyan,
                      highlight: contracts.any((c) => !c.done),
                      onTap: _toggleContracts,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );

    final launch = HoloButton.primary(
      label: 'Launch',
      subtitle: '${world.name} ${indexInWorld + 1} · ${nextDef.name}',
      icon: Icons.rocket_launch_rounded,
      sound: UiSound.launch,
      height: 60,
      fontSize: 20,
      onPressed: game.beginPlay,
    );

    final launchColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Title(),
        Expanded(child: _ShipHero(ship: LevelRegistry.shipFor(next))),
        Row(
          children: [
            Expanded(flex: 3, child: launch),
            if (!dailyDone) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _DailyButton(game: game, streak: streak),
              ),
            ],
          ],
        ),
      ],
    );

    // Garage news: newly unlocked or affordable items (until looked at),
    // then gear owned but never flown; the subtitle names the next goal.
    final garage = GarageNotices.current();
    final garageNews = garage.fresh.length;
    final garageBadge = garageNews > 0
        ? '$garageNews NEW'
        : garage.unusedGear.isNotEmpty
        ? 'FIT'
        : null;
    final garageSubtitle = garage.unusedGear.isNotEmpty && garageNews == 0
        ? '${garage.unusedGear.first.name} not fitted'
        : garage.nextGoal?.label ?? 'Gear · Armory';

    final rail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: HoloTile(
            large: true,
            icon: Icons.public_rounded,
            label: 'Missions',
            subtitle:
                '${LevelRegistry.worlds.length} worlds · '
                '${LevelRegistry.totalLevels} missions',
            onTap: () => game.openScreen(OverlayIds.levelSelect),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: 6,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: HoloTile(
                  icon: Icons.build_circle_outlined,
                  label: 'Garage',
                  subtitle: garageSubtitle,
                  accent: SpaceColors.coral,
                  badge: garageBadge,
                  onTap: () => game.openScreen(OverlayIds.cosmetics),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HoloTile(
                  icon: Icons.badge_outlined,
                  label: 'Logbook',
                  subtitle: rankTitle(p.getXp()),
                  accent: SpaceColors.gold,
                  onTap: () => game.openScreen(OverlayIds.pilotProfile),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: 6,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: HoloTile(
                  icon: Icons.emoji_events_outlined,
                  label: 'Awards',
                  subtitle:
                      '${AchievementService.unlocked.length}'
                      '/${AchievementService.all.length}',
                  accent: SpaceColors.violet,
                  onTap: () => game.openScreen(OverlayIds.achievements),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HoloTile(
                  icon: Icons.tune_rounded,
                  label: 'Settings',
                  subtitle: 'Sound · Controls',
                  accent: Colors.white70,
                  onTap: () => game.openScreen(OverlayIds.settings),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Stack(
      children: [
        const Positioned.fill(child: SpaceBackdrop()),
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  SizedBox(height: 40, child: topBar),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 11, child: launchColumn),
                        const SizedBox(width: 16),
                        Expanded(flex: 9, child: rail),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_contractsOpen && contracts != null) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleContracts,
              child: const ColoredBox(color: Color(0x66000000)),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 52, 16, 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: PanelEntrance(
                      sound: false,
                      child: HoloPanel(
                        title: "Today's contracts",
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: ContractsList(contracts: contracts),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'NARROW HAUL',
            style: hudLabel(30, color: SpaceColors.cyanBright, spacing: 6)
                .copyWith(
                  shadows: const [
                    Shadow(color: SpaceColors.cyan, blurRadius: 18),
                    Shadow(color: Color(0x8800B4D8), blurRadius: 4),
                  ],
                ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'DEEP-SPACE CARGO TOW',
          style: hudLabel(10, color: Colors.white38, spacing: 4),
        ),
      ],
    );
  }
}

/// Today's daily challenge, until it's flown (then it's a top-bar chip).
class _DailyButton extends StatelessWidget {
  const _DailyButton({required this.game, required this.streak});
  final NarrowHaulGame game;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final levels = NarrowHaulGame.unlockedLevelIndices();
    final (_, testFlight) = DailyChallengeConfig.peekToday(levels);
    final name = testFlight
        ? DailyChallengeConfig.testFlightName
        : DailyChallengeConfig.forToday(levels).modifierName;
    return HoloButton(
      label: 'Daily',
      subtitle: streak > 0 ? '$name · 🔥$streak' : name,
      icon: Icons.bolt_rounded,
      accent: SpaceColors.gold,
      sound: UiSound.select,
      height: 60,
      fontSize: 16,
      onPressed: game.openDailyBriefing,
    );
  }
}

/// The next mission's ship hovering in the hangar, plume flickering, with a
/// cargo pod swinging on its tow line.
class _ShipHero extends StatefulWidget {
  const _ShipHero({required this.ship});
  final ShipSpec ship;

  @override
  State<_ShipHero> createState() => _ShipHeroState();
}

class _ShipHeroState extends State<_ShipHero>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c == null && spaceAnimationsOn(context)) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 4),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return LayoutBuilder(
      builder: (context, box) => c == null
          ? _frame(box.biggest, 0)
          : AnimatedBuilder(
              animation: c,
              builder: (context, _) => _frame(box.biggest, c.value),
            ),
    );
  }

  Widget _frame(Size size, double t) {
    if (size.height < 40) return const SizedBox.shrink();
    final tint = widget.ship.tint;
    final s = math.min(size.height * 0.62, size.width * 0.42);
    final bob = math.sin(t * 2 * math.pi) * size.height * 0.025;
    final sway = math.sin(t * 2 * math.pi + 1.1) * 0.16;
    final center = Offset(size.width * 0.5, s * 0.5 + size.height * 0.04 + bob);
    // Sprite: hull bottom (nozzle line) at y 181 of 256.
    final winch = center + Offset(0, s * 0.2);
    final pod = s * 0.26;
    final rope = math.max(0.0, size.height - winch.dy - pod * 0.7);
    final podCenter = winch + Offset(math.sin(sway), math.cos(sway)) * rope;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _HeroPainter(
              center: center,
              shipSize: s,
              winch: winch,
              podCenter: podCenter,
              flicker: t,
            ),
          ),
        ),
        Positioned(
          left: podCenter.dx - pod / 2,
          top: podCenter.dy - pod / 2,
          width: pod,
          height: pod,
          child: Image.asset(
            'assets/cargo.png',
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        Positioned(
          left: center.dx - s / 2,
          top: center.dy - s / 2,
          width: s,
          height: s,
          child: Image.asset(
            'assets/${widget.ship.sprite}',
            color: tint != null && widget.ship.sprite == 'ship.png'
                ? Color(tint)
                : null,
            colorBlendMode: BlendMode.modulate,
            errorBuilder: (_, _, _) => Image.asset('assets/ship.png'),
          ),
        ),
      ],
    );
  }
}

class _HeroPainter extends CustomPainter {
  _HeroPainter({
    required this.center,
    required this.shipSize,
    required this.winch,
    required this.podCenter,
    required this.flicker,
  });

  final Offset center;
  final double shipSize;
  final Offset winch;
  final Offset podCenter;
  final double flicker;

  @override
  void paint(Canvas canvas, Size size) {
    // Hangar spotlight under the ship.
    final glowC = Offset(center.dx, size.height * 0.98);
    canvas.drawOval(
      Rect.fromCenter(
        center: glowC,
        width: shipSize * 2.4,
        height: shipSize * 0.35,
      ),
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                SpaceColors.cyan.withValues(alpha: 0.22),
                SpaceColors.cyan.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCenter(
                center: glowC,
                width: shipSize * 2.4,
                height: shipSize * 0.35,
              ),
            ),
    );

    paintTowLine(canvas, winch, podCenter);
    paintThrustPlume(
      canvas,
      center + Offset(0, shipSize * 0.2),
      shipSize,
      flicker,
    );
  }

  @override
  bool shouldRepaint(_HeroPainter o) =>
      o.center != center || o.podCenter != podCenter || o.flicker != flicker;
}

/// Today's 3 contracts (menu popover).
class ContractsList extends StatelessWidget {
  const ContractsList({super.key, required this.contracts});
  final List<ContractStatus> contracts;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in contracts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(
                  c.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: c.done ? SpaceColors.green : Colors.white30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.contract.description,
                    style: TextStyle(
                      color: c.done ? Colors.white38 : Colors.white,
                      fontSize: 13,
                      decoration: c.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  c.done
                      ? '+${c.contract.xp} XP'
                      : '${c.progress}/${c.contract.target} · ${c.contract.xp} XP',
                  style: TextStyle(
                    color: c.done ? SpaceColors.green : SpaceColors.cyan,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (contracts.every((c) => c.done))
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'All done for today. New contracts tomorrow.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
      ],
    );
  }
}
