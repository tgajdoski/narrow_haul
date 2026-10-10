import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/salvage_fx.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/salvage/salvage.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/ui/career_widgets.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/story_card.dart';
import 'package:narrow_haul/game/overlay_ids.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Awards
// ─────────────────────────────────────────────────────────────────────────────

/// 'achievements' overlay, in two columns so landscape shows twice as many.
class AchievementsOverlay extends StatelessWidget {
  const AchievementsOverlay({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final unlocked = AchievementService.unlocked;
    final all = AchievementService.all;
    return SpaceScreen(
      title: 'Awards',
      accent: SpaceColors.violet,
      onBack: () => game.closeScreen(OverlayIds.achievements),
      trailing: [
        HoloChip(
          icon: Icons.emoji_events_outlined,
          label: '${unlocked.length}/${all.length}',
          color: SpaceColors.gold,
        ),
      ],
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth > 560 ? 2 : 1;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: MediaQuery.textScalerOf(context).scale(66),
              crossAxisSpacing: 10,
              mainAxisSpacing: 8,
            ),
            itemCount: all.length,
            itemBuilder: (context, i) {
              final a = all[i];
              return _AchievementTile(
                meta: a,
                unlocked: unlocked.contains(a.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.meta, required this.unlocked});
  final AchievementMeta meta;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: unlocked ? 1.0 : 0.45,
      child: HoloPanel(
        accent: unlocked ? SpaceColors.gold : const Color(0xFF3A5068),
        glow: unlocked ? 0.35 : 0,
        brackets: unlocked,
        cut: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Text(
              unlocked ? meta.icon : '🔒',
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unlocked ? SpaceColors.gold : Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    meta.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (unlocked)
              const Icon(
                Icons.check_circle,
                color: SpaceColors.green,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pilot Logbook
// ─────────────────────────────────────────────────────────────────────────────

/// 'pilotProfile' overlay: current rank, lifetime stats and type ratings on
/// the left, the rank ladder on the right.
class PilotLogbookOverlay extends StatefulWidget {
  const PilotLogbookOverlay({super.key, required this.game});
  final NarrowHaulGame game;

  @override
  State<PilotLogbookOverlay> createState() => _PilotLogbookOverlayState();
}

class _PilotLogbookOverlayState extends State<PilotLogbookOverlay> {
  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.instance;
    final xp = progress.getXp();
    final current = rankFor(xp);
    final playtime = progress.getStat(ProgressService.statPlaytimeSeconds);
    final stats = <(String, String)>[
      ('Flight hours', '${(playtime / 3600).toStringAsFixed(1)} h'),
      ('Flights', '${progress.getStat(ProgressService.statFlights)}'),
      ('Deliveries', '${progress.getStat(ProgressService.statDeliveries)}'),
      ('Crashes', '${progress.getStat(ProgressService.statCrashes)}'),
      ('Fuel burned', '${progress.getTotalFuelSpent().round()} u'),
      (
        'Stars',
        '${LevelRegistry.totalStars()} / ${LevelRegistry.careerLevels * 3}',
      ),
      ('Total XP', '$xp'),
      ('Daily streak', '🔥 ${progress.getDailyStreak()}'),
    ];

    // The story so far: every world's intro and outro (docs/STORY.md).
    final chapters = [
      for (final w in LevelRegistry.worlds) ...[?Chapter.intro(w), ?Chapter.outro(w)],
    ];

    return SpaceScreen(
      title: 'Pilot Logbook',
      accent: SpaceColors.gold,
      onBack: () => widget.game.closeScreen(OverlayIds.pilotProfile),
      trailing: [
        if (kDebugMode && !kStoreCapture)
          HoloButton(
            label: '+1000 XP (debug)',
            variant: HoloVariant.ghost,
            height: 30,
            fontSize: 10,
            expand: false,
            onPressed: () async {
              await progress.addXp(1000);
              setState(() {});
            },
          ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: current rank + stats + type ratings
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                HoloPanel(
                  accent: SpaceColors.gold,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: CareerProgress(xp: xp, badgeSize: 54),
                ),
                const SizedBox(height: 14),
                const PanelTitle('Flight record', color: SpaceColors.gold),
                const SizedBox(height: 4),
                for (final (label, value) in stats)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(value, style: hudLabel(13, spacing: 1)),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                PanelTitle(
                  'Mission log  ${chapters.where((c) => !c.unseen).length}/${chapters.length}',
                  color: SpaceColors.gold,
                ),
                const SizedBox(height: 4),
                for (final c in chapters) _MissionLogRow(chapter: c),
                const SizedBox(height: 14),
                const PanelTitle('Type ratings', color: SpaceColors.gold),
                const SizedBox(height: 4),
                for (final ship in kShips.values)
                  _TypeRatingRow(
                    ship: ship,
                    rated: LevelRegistry.hasTypeRating(ship.id),
                  ),
                const SizedBox(height: 14),
                PanelTitle(
                  'Relic catalogue  ${kSalvage.where((e) => progress.salvageFound(e.id) > 0).length}/${kSalvage.length}',
                  color: SpaceColors.gold,
                ),
                const SizedBox(height: 4),
                for (final effect in kSalvage)
                  _SalvageLogRow(spec: effect, found: progress.salvageFound(effect.id)),
              ],
            ),
          ),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 16),
            color: const Color(0x22FFD166),
          ),
          // Right: rank ladder
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: kRanks.length,
              itemBuilder: (context, i) {
                final r = kRanks[i];
                final reached = r.index <= current.index;
                final isCurrent = r.index == current.index;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: HoloPanel(
                    accent: isCurrent
                        ? SpaceColors.gold
                        : reached
                        ? const Color(0x88FFD166)
                        : const Color(0xFF3A5068),
                    glow: isCurrent ? 0.6 : 0,
                    brackets: isCurrent,
                    cut: 10,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        RankBadge(kind: r.insignia, size: 30, dimmed: !reached),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title,
                                style: TextStyle(
                                  color: reached
                                      ? SpaceColors.gold
                                      : Colors.white38,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                r.perk,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          reached ? '✓' : '${r.minXp} XP',
                          style: TextStyle(
                            color: reached ? SpaceColors.green : Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One licence endorsement in the logbook: ship name, role and status.
class _TypeRatingRow extends StatelessWidget {
  const _TypeRatingRow({required this.ship, required this.rated});

  final ShipSpec ship;
  final bool rated;

  @override
  Widget build(BuildContext context) {
    final tint = ship.tint != null
        ? Color(ship.tint!).withValues(alpha: 1)
        : SpaceColors.cyan;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.flight, size: 18, color: rated ? tint : Colors.white24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ship.name,
                  style: TextStyle(
                    color: rated ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  ship.blurb,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            rated ? '✓ Rated' : 'Not rated',
            style: TextStyle(
              color: rated ? SpaceColors.green : Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// One Salvage Log entry: a mystery-cache effect, unknown until found once.
/// One story chapter in the logbook: read ones replay on tap.
class _MissionLogRow extends StatelessWidget {
  const _MissionLogRow({required this.chapter});

  final Chapter chapter;

  void _replay(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, _) => ChapterCard(
        chapter: chapter,
        doneLabel: 'Close',
        onDone: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final read = !chapter.unseen;
    final color = read ? chapter.accent : Colors.white24;
    return InkWell(
      onTap: read ? () => _replay(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(read ? Icons.menu_book_rounded : Icons.lock_outline_rounded, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    read ? chapter.title : '? ? ?',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  Text(
                    chapter.kicker,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (read) Icon(Icons.play_arrow_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class _SalvageLogRow extends StatelessWidget {
  const _SalvageLogRow({required this.spec, required this.found});

  final SalvageSpec spec;
  final int found;

  @override
  Widget build(BuildContext context) {
    final known = found > 0;
    final color = known ? salvageColor(spec) : Colors.white24;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 26,
            child: CustomPaint(painter: _SalvageGlyphPainter(known ? spec.effect : null, color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  known ? spec.name : '? ? ?',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                ),
                Text(
                  known ? spec.blurb : (spec.good ? 'An undiscovered boon.' : 'An undiscovered curse.'),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (known) Text('×$found', style: hudLabel(12, spacing: 1)),
        ],
      ),
    );
  }
}

class _SalvageGlyphPainter extends CustomPainter {
  _SalvageGlyphPainter(this.effect, this.color);
  final SalvageEffect? effect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      drawSalvageGlyph(canvas, size.center(Offset.zero), size.shortestSide * 0.8, effect, color);

  @override
  bool shouldRepaint(_SalvageGlyphPainter old) => old.effect != effect || old.color != color;
}
