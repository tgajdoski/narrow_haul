import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/physics_core.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/fleet_service.dart';
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/fleet.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/game/story/story.dart';
import 'package:narrow_haul/ui/career_widgets.dart';
import 'package:narrow_haul/ui/garage_overlay.dart' show GarageOverlay;
import 'package:narrow_haul/ui/ship_showcase.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/story_card.dart';

/// One line of a mission briefing: what the pilot will face (or get).
class BriefingFact {
  const BriefingFact(this.icon, this.label, {this.kind = FactKind.info});
  final IconData icon;
  final String label;
  final FactKind kind;

  @override
  String toString() => label;
}

/// [warn]: makes the flight harder. [help]: makes it easier. [info]: neither.
enum FactKind { info, warn, help }

/// What's special about flat level [index]: ship, physics, force fields,
/// hazards and pickups. [daily] layers today's challenge modifiers on top;
/// [testFlight] means the ship is swapped for another one at launch.
List<BriefingFact> briefingFacts(
  int index, {
  DailyChallengeConfig? daily,
  bool testFlight = false,
}) {
  final def = LevelRegistry.defAt(index);
  // A daily flies the level's own ship (or the Test Flight's).
  final ship = daily != null || testFlight
      ? LevelRegistry.shipFor(index)
      : FleetService.flownShipFor(index);
  final m = def.modifiers;
  final facts = <BriefingFact>[
    if (testFlight)
      const BriefingFact(
        Icons.swap_horiz_rounded,
        'Test Flight: another ship',
        kind: FactKind.warn,
      )
    else
      BriefingFact(
        Icons.rocket_rounded,
        isNewShip(ship) ? '${ship.name} · new ship' : ship.name,
        kind: isNewShip(ship) ? FactKind.warn : FactKind.info,
      ),
  ];

  final g = combinedGravityMul(m.gravityMul, daily?.gravityMultiplier ?? 1);
  if (g == 0) {
    facts.add(const BriefingFact(Icons.blur_on_rounded, 'Zero-g'));
  } else if ((g - 1).abs() > 0.01) {
    facts.add(
      BriefingFact(
        g > 1 ? Icons.south_rounded : Icons.north_rounded,
        '${g > 1 ? 'Heavy' : 'Light'} gravity ${_trim(g)} g',
        kind: g > 1 ? FactKind.warn : FactKind.help,
      ),
    );
  }

  final burn = m.fuelDrainMul * (daily?.fuelDrainMultiplier ?? 1);
  if ((burn - 1).abs() > 0.01) {
    facts.add(
      BriefingFact(
        Icons.local_gas_station_rounded,
        burn > 1
            ? 'Fuel burn ×${_mul(burn)}'
            : 'Fuel lasts ×${_mul(1 / burn)}',
        kind: burn > 1 ? FactKind.warn : FactKind.help,
      ),
    );
  }
  if (m.cargoDensityMul > 1) {
    facts.add(
      BriefingFact(
        Icons.anchor_rounded,
        'Heavy cargo ×${_mul(m.cargoDensityMul)}',
        kind: FactKind.warn,
      ),
    );
  }
  if (m.wallFriction != null) {
    facts.add(
      const BriefingFact(
        Icons.ac_unit_rounded,
        'Icy walls',
        kind: FactKind.warn,
      ),
    );
  }

  if (def is CaveLevelDef) {
    final spec = def.spec;
    final winds = spec.fields.whereType<WindZoneSpec>();
    if (winds.isNotEmpty) {
      facts.add(
        BriefingFact(
          Icons.air_rounded,
          winds.any((w) => w.gustAmp > 0) ? 'Gusting wind' : 'Wind',
          kind: FactKind.warn,
        ),
      );
    }
    final zones = spec.fields.whereType<GravityZoneSpec>();
    if (zones.any((z) => z.gx == 0 && z.gy == 0)) {
      facts.add(const BriefingFact(Icons.blur_circular_rounded, 'Zero-g pocket'));
    }
    if (zones.any((z) => z.gx != 0 || z.gy != 0)) {
      facts.add(
        const BriefingFact(
          Icons.turn_right_rounded,
          'Sideways gravity',
          kind: FactKind.warn,
        ),
      );
    }
    final wells = spec.fields.whereType<GravityWellSpec>().length;
    if (wells > 0) {
      facts.add(
        BriefingFact(
          Icons.radio_button_checked_rounded,
          wells == 1 ? 'Gravity well' : '$wells gravity wells',
          kind: FactKind.warn,
        ),
      );
    }

    final obstacles = spec.obstacles;
    final moving = obstacles
        .where(
          (o) =>
              o is RotatingBarSpec || o is PendulumSpec || o is SlidingBlockSpec,
        )
        .length;
    if (moving > 0) {
      facts.add(
        BriefingFact(
          Icons.settings_rounded,
          moving == 1 ? 'Moving hazard' : '$moving moving hazards',
          kind: FactKind.warn,
        ),
      );
    }
    final turrets = obstacles.whereType<TurretSpec>().length;
    if (turrets > 0) {
      facts.add(
        BriefingFact(
          Icons.gps_fixed_rounded,
          turrets == 1 ? 'Turret' : '$turrets turrets',
          kind: FactKind.warn,
        ),
      );
    }
    if (obstacles.any((o) => o is ReactorSpec)) {
      facts.add(
        const BriefingFact(
          Icons.bolt_rounded,
          'Reactor',
          kind: FactKind.warn,
        ),
      );
    }
    final cells = spec.pickups.whereType<FuelCellSpec>().length;
    if (cells > 0) {
      facts.add(
        BriefingFact(
          Icons.battery_charging_full_rounded,
          cells == 1 ? 'Fuel canister' : '$cells fuel canisters',
          kind: FactKind.help,
        ),
      );
    }
  }
  return facts;
}

/// A ship flown before its type rating, like the in-flight ship hint. The
/// Kestrel is the training ship, so it's never new.
bool isNewShip(ShipSpec ship) =>
    ship.id != kKestrel.id && !LevelRegistry.hasTypeRating(ship.id);

/// `1.5`, `2`.
String _mul(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// `1.35`, `1.4`, `2` (two decimals at most, no trailing zeros).
String _trim(double v) =>
    v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// Star rules as the game scores them (`_calculateStars`): 3★ needs the fuel
/// *and* the time, 2★ the fuel, 1★ just the delivery.
(String three, String two) starTargets(StarSpec s) => (
  '≥ ${(s.star3Fuel * 100).round()}% fuel · ≤ ${formatFlightTime(s.star3Time)}',
  '≥ ${(s.star2Fuel * 100).round()}% fuel',
);

/// XP for clearing today's daily now (the streak includes today).
({int xp, int bonus, int streak}) dailyReward() {
  final streak = ProgressService.instance.getDailyStreak() + 1;
  return (xp: kDailyXp, bonus: dailyStreakBonusXp(streak), streak: streak);
}

/// 'briefing' overlay: what a mission holds before launch. From the star
/// chart (Launch / Launch with route) or the hangar's Daily button.
class MissionBriefingOverlay extends StatefulWidget {
  const MissionBriefingOverlay({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  State<MissionBriefingOverlay> createState() => _MissionBriefingOverlayState();
}

class _MissionBriefingOverlayState extends State<MissionBriefingOverlay> {
  /// The ship turntable's square (px).
  static const double _shipCard = 120;
  NarrowHaulGame get game => widget.game;

  /// The chapter card was read (or skipped) on this briefing.
  bool _chapterRead = false;

  Future<void> _pick(int index, ShipSpec ship) async {
    await FleetService.setChoice(index, ship.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final index = game.briefingLevel;
    final daily = game.briefingDaily;
    final def = LevelRegistry.defAt(index);
    final (world, inWorld) = LevelRegistry.worldOf(index);
    final progress = ProgressService.instance;

    // A world's first mission opens its story chapter, once per save.
    final chapter = daily || inWorld != 0 || _chapterRead ? null : Chapter.intro(world);
    if (chapter != null && chapter.unseen) {
      return ChapterCard(
        chapter: chapter,
        doneLabel: 'Briefing',
        onDone: () => setState(() => _chapterRead = true),
      );
    }

    DailyChallengeConfig? config;
    var testFlight = false;
    if (daily) {
      final levels = NarrowHaulGame.unlockedLevelIndices();
      testFlight = DailyChallengeConfig.peekToday(levels).$2;
      // Without ship options a Test Flight day reads as a standard run, so
      // only its name/description come from [testFlight] below.
      config = DailyChallengeConfig.forToday(levels);
    }

    final accent = daily
        ? SpaceColors.gold
        : (gameThemes[def.themeId] ?? tutorialTheme).uiAccent;
    final facts = briefingFacts(index, daily: config, testFlight: testFlight);
    final par = LevelRegistry.shipFor(index);
    final ship = daily ? par : FleetService.flownShipFor(index);
    final newShip = !testFlight && isNewShip(ship);
    final stars = progress.getStarsById(def.saveId);
    final best = progress.getBestTimeById(def.saveId);
    // Routes were recorded with the par ship (a guided run flies it).
    final routeOffered =
        !daily && progress.isRouteUnlocked(def.saveId) && ship.id == par.id;
    final picker = daily
        ? null
        : _ShipPicker(
            index: index,
            flown: ship,
            par: par,
            accent: accent,
            onPick: (s) => _pick(index, s),
            onMore: () => game.openGarageFromBriefing(tab: GarageOverlay.shipsTab),
          );
    final (three, two) = starTargets(def.stars);

    final title = daily
        ? 'Daily · ${testFlight ? DailyChallengeConfig.testFlightName : config!.modifierName}'
        : 'Mission ${inWorld + 1} · ${world.name}';
    final note = daily
        ? (testFlight
              ? 'You fly a different ship today.'
              : config!.modifierDesc)
        : newShip
        ? ship.blurb
        : null;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            def.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: hudLabel(20, spacing: 2.4),
          ),
        ),
        if (!daily && stars > 0) ...[
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: StarIcon(filled: i < stars, size: 14),
            ),
          if (best != null) ...[
            const SizedBox(width: 8),
            Text(
              'Best ${formatFlightTime(best)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ],
    );

    Color factColor(FactKind k) => switch (k) {
      FactKind.warn => SpaceColors.coral,
      FactKind.help => SpaceColors.green,
      FactKind.info => accent,
    };

    Widget starLine(int n, String text) => Row(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(right: 1),
            child: StarIcon(filled: i < n, size: 11),
          ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );

    final reward = dailyReward();
    final story = daily ? null : storyFor(def.saveId);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (story != null) ...[
          const SizedBox(height: 4),
          _StoryLine(story: story, accent: accent),
        ],
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // The ship chips stand in for the ship fact when they show.
            if (picker != null && picker.shows) ...picker.chips(context),
            for (final f in picker != null && picker.shows ? facts.skip(1) : facts)
              HoloChip(
                icon: f.icon,
                label: f.label,
                color: factColor(f.kind),
                highlight: f.kind == FactKind.warn,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: starLine(3, three)),
            const SizedBox(width: 10),
            Expanded(child: starLine(2, two)),
          ],
        ),
        if (!daily) ...[
          const SizedBox(height: 8),
          _LoadoutLine(game: game, accent: accent),
        ],
        if (daily) ...[
          const SizedBox(height: 6),
          Text(
            reward.bonus > 0
                ? '+${reward.xp} XP · streak +${reward.bonus} XP · 🔥${reward.streak}'
                : '+${reward.xp} XP · first clear today',
            style: hudLabel(11, color: SpaceColors.gold, spacing: 1.2),
          ),
        ],
      ],
    );

    final footer = Row(
      children: [
        Expanded(
          child: HoloButton(
            label: 'Back',
            icon: Icons.arrow_back_rounded,
            sound: UiSound.back,
            onPressed: game.closeBriefing,
          ),
        ),
        if (routeOffered) ...[
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: HoloButton(
              label: 'With route',
              subtitle: 'max 2★',
              icon: Icons.route_rounded,
              accent: accent,
              sound: UiSound.launch,
              onPressed: () => game.startLevel(index, withRoute: true),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: HoloButton.primary(
            label: 'Launch',
            icon: Icons.rocket_launch_rounded,
            accent: accent,
            sound: UiSound.launch,
            height: 46,
            onPressed: daily
                ? game.beginChallenge
                : () => game.startLevel(index, withRoute: false),
          ),
        ),
      ],
    );

    // The ship on a small turntable beside the facts, where the dialog
    // still leaves the facts their full width (a Test Flight ship is a
    // surprise until launch).
    final content = testFlight
        ? body
        : LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < 560 + _shipCard + 12) return body;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _shipCard,
                    height: _shipCard,
                    child: ShipShowcase(
                      key: const ValueKey('briefing-ship'),
                      ship: ship,
                      livery: CosmeticsService.getEquippedId(CosmeticsService.catShip),
                      plume: CosmeticsService.getEquippedId(CosmeticsService.catPlume),
                      accent: accent,
                      interactive: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: body),
                ],
              );
            },
          );

    return HoloDialog(
      title: title,
      accent: accent,
      maxWidth: 600 + _shipCard + 12 + 28,
      footer: footer,
      child: content,
    );
  }
}

/// Briefing: which ship flies this mission. One chip (the ship flown, `par`
/// when it's the one the mission is built for) that opens a menu of the
/// fleet: owned ships that fit are picked, the rest say why not, and
/// "Get more ships…" opens the Garage fleet while any are locked.
class _ShipPicker {
  const _ShipPicker({
    required this.index,
    required this.flown,
    required this.par,
    required this.accent,
    required this.onPick,
    required this.onMore,
  });
  final int index;
  final ShipSpec flown;
  final ShipSpec par;
  final Color accent;
  final void Function(ShipSpec ship) onPick;
  final VoidCallback onMore;

  bool get _parOnly => isParOnly(LevelRegistry.defAt(index));

  bool get _moreToGet => !FleetService.ownsAll;

  /// Worth a chip: there's a choice to make, or ships still to get.
  bool get shows =>
      !_parOnly && (FleetService.owned.any((s) => s.id != par.id) || _moreToGet);

  static const _more = 'more';

  Future<void> _open(BuildContext chip) async {
    final box = chip.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(chip).context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    const style = TextStyle(color: Colors.white, fontSize: 13);
    final picked = await showMenu<String>(
      context: chip,
      color: SpaceColors.panelDeep,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final s in FleetService.fleet)
          if ((FleetService.owns(s.id) || s.id == par.id, FleetService.fitOn(index, s))
              case (final owned, final fit))
            PopupMenuItem<String>(
              key: ValueKey('pick-${s.id}'),
              value: s.id,
              enabled: owned && fit.flies && s.id != flown.id,
              height: 36,
              child: Row(
                children: [
                  Icon(
                    s.id == flown.id
                        ? Icons.check_rounded
                        : owned
                        ? Icons.rocket_outlined
                        : Icons.lock_outline_rounded,
                    size: 16,
                    color: owned && fit.flies ? accent : Colors.white30,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    s.id == par.id ? '${s.name} · par' : s.name,
                    style: style.copyWith(
                      color: owned && fit.flies ? Colors.white : Colors.white38,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      !owned ? 'not in your hangar' : fit.flies ? shipTrait(s) : fit.reason,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        if (_moreToGet)
          PopupMenuItem<String>(
            key: const ValueKey('pick-more'),
            value: _more,
            height: 36,
            child: Text(
              'Get more ships…',
              style: style.copyWith(color: SpaceColors.gold),
            ),
          ),
      ],
    );
    if (picked == null) return;
    if (picked == _more) {
      onMore();
    } else if (kShips[picked] case final s?) {
      onPick(s);
    }
  }

  List<Widget> chips(BuildContext context) => [
        Builder(
          builder: (chip) => HoloChip(
            key: const ValueKey('ship-picker'),
            icon: Icons.rocket_rounded,
            label: '${flown.id == par.id ? '${flown.name} · par' : flown.name}'
                '${isNewShip(flown) ? ' · new' : ''}  ▾',
            color: isNewShip(flown) ? SpaceColors.coral : accent,
            highlight: isNewShip(flown) || flown.id != par.id,
            onTap: () => _open(chip),
          ),
        ),
      ];
}

/// Briefing: the tow gear and kit this flight takes, and a nudge (with a
/// way to the Garage) when the player owns gear they've never flown.
class _LoadoutLine extends StatelessWidget {
  const _LoadoutLine({required this.game, required this.accent});
  final NarrowHaulGame game;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final rope = CosmeticsService.byId(
      CosmeticsService.getEquippedId(CosmeticsService.catRope),
    );
    final kit = CosmeticsService.byId(
      CosmeticsService.getEquippedId(CosmeticsService.catKit),
    );
    final unused = GarageNotices.current().unusedGear;
    final nudge = unused.isEmpty
        ? null
        : unused.length == 1
        ? 'You own ${unused.first.name}: not fitted'
        : 'You own ${unused.length} gear items you haven\'t fitted';
    return Row(
      children: [
        Icon(Icons.link_rounded, size: 15, color: accent),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Loadout: ${rope?.name ?? 'Steel Winch Cable'} · ${kit?.name ?? 'Standard Fit'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (nudge != null)
                Text(
                  nudge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: SpaceColors.gold, fontSize: 11.5),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        HoloButton(
          label: nudge != null ? 'Fit gear' : 'Garage',
          icon: Icons.build_circle_outlined,
          accent: nudge != null ? SpaceColors.gold : accent,
          height: 32,
          fontSize: 11,
          expand: false,
          onPressed: game.openGarageFromBriefing,
        ),
      ],
    );
  }
}

/// The story line: the cargo, who briefs it, then the brief.
class _StoryLine extends StatelessWidget {
  const _StoryLine({required this.story, required this.accent});

  final LevelStory story;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${story.cargo.toUpperCase()} · ${story.from}  ',
            style: hudLabel(10, color: accent, spacing: 1.4),
          ),
          TextSpan(
            text: story.brief,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      // A landscape phone keeps the dialog to one story line.
      maxLines: MediaQuery.sizeOf(context).height < 400 ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
