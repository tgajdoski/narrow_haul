/// Flame overlay keys, registered in `main.dart`'s `overlayBuilderMap`.
abstract final class OverlayIds {
  static const menu = 'menu';
  static const levelSelect = 'levelSelect';
  static const briefing = 'briefing';
  static const achievements = 'achievements';
  static const cosmetics = 'cosmetics';
  static const pilotProfile = 'pilotProfile';
  static const settings = 'settings';
  static const pause = 'pause';
  static const demo = 'demo';
  static const gameOver = 'gameOver';
  static const levelComplete = 'levelComplete';
  static const rankUp = 'rankUp';

  /// A world's story outro over the results ([NarrowHaulGame.showStoryOutroIfDue]).
  static const story = 'story';

  /// Hangar sub-screens ([NarrowHaulGame.openScreen]).
  static const subScreens = [levelSelect, achievements, cosmetics, pilotProfile];

  /// Everything shown during or after a flight.
  static const flight = [pause, settings, demo, gameOver, levelComplete, rankUp, story];
}
