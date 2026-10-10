import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/story/story.dart';
import 'package:narrow_haul/game/story/story_act1.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// A story chapter card (docs/STORY.md): a world's intro before its first
/// mission, or its outro after the last one is cleared.
class Chapter {
  const Chapter({
    required this.key,
    required this.kicker,
    required this.title,
    required this.byline,
    required this.pages,
    required this.accent,
  });

  /// Seen flag ([ProgressService.storySeen]).
  final String key;
  final String kicker;
  final String title;
  final String byline;
  final List<String> pages;
  final Color accent;

  /// Chapter [world]'s intro (Training Grounds opens with the prologue).
  static Chapter? intro(WorldDef world) => _of(world, outro: false);

  /// Chapter [world]'s outro.
  static Chapter? outro(WorldDef world) => _of(world, outro: true);

  static Chapter? _of(WorldDef world, {required bool outro}) {
    final story = worldStoryFor(world.id);
    if (story == null) return null;
    final n = LevelRegistry.worlds.indexOf(world) + 1;
    final first = n == 1 && !outro;
    return Chapter(
      key: '${outro ? 'outro' : 'intro'}_${world.id}',
      kicker: first
          ? 'Operation Lifeline'
          : outro
          ? 'Chapter $n complete'
          : 'Chapter $n',
      title: world.name,
      byline: '${story.place} · ${story.contact}',
      pages: [if (first) ...kPrologue, ...(outro ? story.outro : story.intro)],
      accent: (gameThemes[world.themeId] ?? tutorialTheme).uiAccent,
    );
  }

  /// Not seen yet on this save.
  bool get unseen => !ProgressService.instance.storySeen(key);
}

/// The chapter card: one paragraph per page, Next / Skip, then [onDone]
/// (marks the chapter seen).
class ChapterCard extends StatefulWidget {
  const ChapterCard({
    super.key,
    required this.chapter,
    required this.onDone,
    this.doneLabel = 'Continue',
    @visibleForTesting this.initialPage = 0,
  });

  final Chapter chapter;
  final VoidCallback onDone;
  final String doneLabel;
  final int initialPage;

  @override
  State<ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends State<ChapterCard> {
  late int _page = widget.initialPage;

  Chapter get c => widget.chapter;
  bool get _last => _page >= c.pages.length - 1;

  void _done() {
    ProgressService.instance.markStorySeen(c.key);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final footer = Row(
      children: [
        if (!_last) ...[
          Expanded(
            child: HoloButton(
              label: 'Skip',
              variant: HoloVariant.ghost,
              sound: UiSound.back,
              onPressed: _done,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          flex: 2,
          child: HoloButton.primary(
            label: _last ? widget.doneLabel : 'Next',
            icon: _last ? Icons.check_rounded : Icons.arrow_forward_rounded,
            accent: c.accent,
            height: 46,
            sound: UiSound.select,
            onPressed: _last ? _done : () => setState(() => _page++),
          ),
        ),
      ],
    );

    return HoloDialog(
      key: const ValueKey('chapter-card'),
      title: c.kicker,
      accent: c.accent,
      footer: footer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: hudLabel(20, spacing: 2.4),
          ),
          const SizedBox(height: 2),
          Text(
            c.byline,
            style: hudLabel(10, color: c.accent, spacing: 1.4),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              c.pages[_page],
              key: ValueKey(_page),
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
            ),
          ),
          if (c.pages.length > 1) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < c.pages.length; i++)
                  Container(
                    width: i == _page ? 14 : 6,
                    height: 4,
                    margin: const EdgeInsets.only(right: 4),
                    color: i == _page ? c.accent : Colors.white24,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Overlay `story`: the chapter outro of [NarrowHaulGame.storyOutroWorld]
/// over the result screen.
class StoryChapterOverlay extends StatelessWidget {
  const StoryChapterOverlay({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final world = game.storyOutroWorld;
    final chapter = world == null ? null : Chapter.outro(world);
    if (chapter == null) return const SizedBox.shrink();
    return ChapterCard(chapter: chapter, onDone: game.closeStoryOutro);
  }
}
