import 'package:narrow_haul/game/services/progress_service.dart';

/// Defines all achievement IDs and metadata.
class AchievementIds {
  static const firstHaul = 'first_haul';
  static const fuelMiser = 'fuel_miser';
  static const speedHauler = 'speed_hauler';
  static const noScratch = 'no_scratch';
  static const perfectPilot = 'perfect_pilot';
  static const level10 = 'level_10';
  static const level20 = 'level_20';
  static const dailyPilot = 'daily_pilot';
}

class AchievementMeta {
  const AchievementMeta({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
  });
  final String id;
  final String title;
  final String description;
  final String icon;
}

class AchievementService {
  static const List<AchievementMeta> all = [
    AchievementMeta(
      id: AchievementIds.firstHaul,
      title: 'First Haul',
      description: 'Complete your first mission.',
      icon: '🚀',
    ),
    AchievementMeta(
      id: AchievementIds.fuelMiser,
      title: 'Fuel Miser',
      description: 'Complete a level with over 90% fuel remaining.',
      icon: '⚡',
    ),
    AchievementMeta(
      id: AchievementIds.speedHauler,
      title: 'Speed Hauler',
      description: 'Complete any level in under 30 seconds.',
      icon: '⚡',
    ),
    AchievementMeta(
      id: AchievementIds.noScratch,
      title: 'No Scratch',
      description: 'Complete 5 levels in a row without retrying.',
      icon: '🛡️',
    ),
    AchievementMeta(
      id: AchievementIds.perfectPilot,
      title: 'Perfect Pilot',
      description: 'Earn 3 stars on every level.',
      icon: '⭐',
    ),
    AchievementMeta(
      id: AchievementIds.level10,
      title: 'Deep Space',
      description: 'Reach Mission 10.',
      icon: '🌌',
    ),
    AchievementMeta(
      id: AchievementIds.level20,
      title: 'Master Hauler',
      description: 'Complete all 20 missions.',
      icon: '🏆',
    ),
    AchievementMeta(
      id: AchievementIds.dailyPilot,
      title: 'Daily Pilot',
      description: 'Complete a daily challenge.',
      icon: '📅',
    ),
  ];

  /// Returns true if newly unlocked.
  static Future<bool> unlock(String id) =>
      ProgressService.instance.unlockAchievement(id);

  static Set<String> get unlocked =>
      ProgressService.instance.getUnlockedAchievements();
}
