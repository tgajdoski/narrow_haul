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
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/ui/career_widgets.dart';
import 'package:narrow_haul/ui/ship_showcase.dart';
import 'package:narrow_haul/ui/space_ui.dart';

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
  final ship = LevelRegistry.shipFor(index);
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
class MissionBriefingOverlay extends StatelessWidget {
  const MissionBriefingOverlay({super.key, required this.game});

  /// The ship turntable's square (px).
  static const double _shipCard = 120;
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final index = game.briefingLevel;
    final daily = game.briefingDaily;
    final def = LevelRegistry.defAt(index);
    final (world, inWorld) = LevelRegistry.worldOf(index);
    final progress = ProgressService.instance;

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
    final ship = LevelRegistry.shipFor(index);
    final newShip = !testFlight && isNewShip(ship);
    final stars = progress.getStarsById(def.saveId);
    final best = progress.getBestTimeById(def.saveId);
    final routeOffered = !daily && progress.isRouteUnlocked(def.saveId);
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
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
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
            for (final f in facts)
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
