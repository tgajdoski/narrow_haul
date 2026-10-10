import 'package:flutter/foundation.dart';
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
  static const cargoSwinger = 'cargo_swinger';
  static const rankCommercial = 'rank_commercial';
  static const rankCaptain = 'rank_captain';
  static const rankChief = 'rank_chief';
  static const fullManifest = 'full_manifest';
  static const weekOnDuty = 'week_on_duty';
  static const centuryHauler = 'century_hauler';
  static const fleetQualified = 'fleet_qualified';
  static const stormRider = 'storm_rider';
  static const orbitalMechanic = 'orbital_mechanic';
  static const heavyLifter = 'heavy_lifter';
  static const testPilot = 'test_pilot';
  static const offType = 'off_type';
  static const weaponsHot = 'weapons_hot';
  static const meltdownEscape = 'meltdown_escape';
  static const holdFire = 'hold_fire';
  static const hotRefuel = 'hot_refuel';
  static const openedTheBox = 'opened_the_box';
  static const gambler = 'gambler';
  static const ghostProtocol = 'ghost_protocol';
  static const beeLieveIt = 'bee_lieve_it';
  static const badTrip = 'bad_trip';
  static const shakeItOff = 'shake_it_off';
  static const clover = 'clover';
  static const salvageCollector = 'salvage_collector';
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
      description: 'Complete a level with 85% or more fuel remaining.',
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
      description: 'Complete every mission.',
      icon: '🏆',
    ),
    AchievementMeta(
      id: AchievementIds.dailyPilot,
      title: 'Daily Pilot',
      description: 'Complete a daily challenge.',
      icon: '📅',
    ),
    AchievementMeta(
      id: AchievementIds.cargoSwinger,
      title: 'Cargo Swinger',
      description: 'Attach rope and swing cargo 360° before landing.',
      icon: '🔄',
    ),
    AchievementMeta(
      id: AchievementIds.rankCommercial,
      title: 'Fly for Hire',
      description: 'Earn your Commercial Pilot licence.',
      icon: '🪪',
    ),
    AchievementMeta(
      id: AchievementIds.rankCaptain,
      title: 'Left Seat',
      description: 'Make Captain.',
      icon: '👨‍✈️',
    ),
    AchievementMeta(
      id: AchievementIds.rankChief,
      title: 'Chief Pilot',
      description: 'Reach the top of the pilot career.',
      icon: '🎖️',
    ),
    AchievementMeta(
      id: AchievementIds.fullManifest,
      title: 'Full Manifest',
      description: "Complete all of a day's contracts.",
      icon: '📋',
    ),
    AchievementMeta(
      id: AchievementIds.weekOnDuty,
      title: 'Week on Duty',
      description: 'Complete the daily challenge 7 days in a row.',
      icon: '🔥',
    ),
    AchievementMeta(
      id: AchievementIds.centuryHauler,
      title: 'Century Hauler',
      description: 'Deliver 100 cargos.',
      icon: '📦',
    ),
    AchievementMeta(
      id: AchievementIds.fleetQualified,
      title: 'Fleet Qualified',
      description: 'Hold a type rating for every ship.',
      icon: '🛩️',
    ),
    AchievementMeta(
      id: AchievementIds.offType,
      title: 'Off Type',
      description: 'Earn 3 stars on a mission in a ship other than its own.',
      icon: '🔀',
    ),
    AchievementMeta(
      id: AchievementIds.stormRider,
      title: 'Storm Rider',
      description: 'Earn 3 stars on a mission with wind.',
      icon: '🌬️',
    ),
    AchievementMeta(
      id: AchievementIds.orbitalMechanic,
      title: 'Orbital Mechanic',
      description: 'Earn 3 stars on a mission with a gravity well.',
      icon: '🪐',
    ),
    AchievementMeta(
      id: AchievementIds.heavyLifter,
      title: 'Heavy Lifter',
      description: 'Deliver cargo at 1.5 g or more.',
      icon: '🏋️',
    ),
    AchievementMeta(
      id: AchievementIds.testPilot,
      title: 'Test Pilot',
      description: 'Complete a Test Flight daily challenge.',
      icon: '🧪',
    ),
    AchievementMeta(
      id: AchievementIds.weaponsHot,
      title: 'Weapons Hot',
      description: 'Destroy your first defence turret.',
      icon: '🎯',
    ),
    AchievementMeta(
      id: AchievementIds.meltdownEscape,
      title: 'Meltdown Escape',
      description: 'Destroy a reactor core and deliver before it blows.',
      icon: '☢️',
    ),
    AchievementMeta(
      id: AchievementIds.holdFire,
      title: 'Hold Fire',
      description: 'Deliver on a defended mission in an armed ship without firing a shot.',
      icon: '🕊️',
    ),
    AchievementMeta(
      id: AchievementIds.hotRefuel,
      title: 'Hot Refuel',
      description: 'Collect 10 fuel canisters in flight.',
      icon: '⛽',
    ),
    AchievementMeta(
      id: AchievementIds.openedTheBox,
      title: 'Opened the Box',
      description: 'Open your first mystery salvage cache.',
      icon: '🎁',
    ),
    AchievementMeta(
      id: AchievementIds.gambler,
      title: 'Gambler',
      description: 'Open 50 mystery salvage caches.',
      icon: '🎲',
    ),
    AchievementMeta(
      id: AchievementIds.ghostProtocol,
      title: 'Ghost Protocol',
      description: 'Fly through a turret\'s sights under a Stealth Field.',
      icon: '👻',
    ),
    AchievementMeta(
      id: AchievementIds.beeLieveIt,
      title: 'Bee-lieve It',
      description: 'Deliver while still swollen from a Swarm Sting.',
      icon: '🐝',
    ),
    AchievementMeta(
      id: AchievementIds.badTrip,
      title: 'Bad Trip, Good Landing',
      description: 'Deliver during a Spore Trip.',
      icon: '🍄',
    ),
    AchievementMeta(
      id: AchievementIds.shakeItOff,
      title: 'Shake It Off',
      description: 'Spin a Swarm Sting\'s bee off before it wears off.',
      icon: '🌀',
    ),
    AchievementMeta(
      id: AchievementIds.clover,
      title: 'Four-Leaf Clover',
      description: 'Open three boons in a row.',
      icon: '🍀',
    ),
    AchievementMeta(
      id: AchievementIds.salvageCollector,
      title: 'Salvage Collector',
      description: 'Find every mystery salvage effect (see the Logbook).',
      icon: '🗃️',
    ),
  ];

  static AchievementMeta byId(String id) => all.firstWhere((a) => a.id == id);

  /// Fires for unlocks that should pop a toast (ones earned mid-flight; the
  /// level-complete screen lists the rest itself).
  static final ValueNotifier<AchievementMeta?> announced = ValueNotifier(null);

  /// Returns true if newly unlocked.
  static Future<bool> unlock(String id, {bool announce = false}) async {
    final isNew = await ProgressService.instance.unlockAchievement(id);
    if (isNew && announce) announced.value = byId(id);
    return isNew;
  }

  static Set<String> get unlocked =>
      ProgressService.instance.getUnlockedAchievements();
}
