part of 'progress_service.dart';

/// The career: stars and times per level, achievements, coins, XP, Garage
/// and fleet, contracts and lifetime stats. A progress reset wipes these.
extension ProgressCareer on ProgressService {
  // ── Stars (0–3) and best times, keyed by stable level saveId ─────────────

  int getStarsById(String saveId) =>
      (_int('stars2_$saveId') ?? 0).clamp(0, 3);

  Future<void> saveStarsById(String saveId, int stars) async {
    if (stars > getStarsById(saveId)) {
      await _prefs.setInt('stars2_$saveId', stars);
    }
  }

  double? getBestTimeById(String saveId) => _double('time2_$saveId');

  Future<void> saveBestTimeById(String saveId, double seconds) async {
    final current = getBestTimeById(saveId);
    if (current == null || seconds < current) {
      await _prefs.setDouble('time2_$saveId', seconds);
    }
  }

  // ── No-retry streak ──────────────────────────────────────────────────────

  int getNoRetryStreak() => _read(_noRetryStreak);
  Future<void> setNoRetryStreak(int v) => _write(_noRetryStreak, v);

  // ── Achievements ─────────────────────────────────────────────────────────

  Set<String> getUnlockedAchievements() =>
      (_stringList(_Keys.achievements) ?? []).toSet();

  Future<bool> unlockAchievement(String id) async {
    final current = getUnlockedAchievements();
    if (current.contains(id)) return false;
    current.add(id);
    await _prefs.setStringList(_Keys.achievements, current.toList());
    return true;
  }

  // ── Fuel spent and coins ─────────────────────────────────────────────────

  double getTotalFuelSpent() => _read(_totalFuelSpent);
  Future<void> addFuelSpent(double amount) =>
      _write(_totalFuelSpent, getTotalFuelSpent() + amount);

  int getCosmeticCurrency() => math.max(0, _read(_currency));
  Future<void> addCosmeticCurrency(int amount) =>
      _write(_currency, getCosmeticCurrency() + amount);

  Future<void> spendCosmeticCurrency(int amount) async {
    final current = getCosmeticCurrency();
    if (current >= amount) await _write(_currency, current - amount);
  }

  // ── Route guide ──────────────────────────────────────────────────────────

  /// "Show route" was offered and taken on this level; it stays available.
  bool isRouteUnlocked(String saveId) =>
      _bool('route_unlocked_$saveId') ?? false;
  Future<void> setRouteUnlocked(String saveId) async =>
      _prefs.setBool('route_unlocked_$saveId', true);

  // ── Cosmetics ────────────────────────────────────────────────────────────

  bool isCosmeticUnlocked(String id) =>
      _bool('cosmetic_unlocked_$id') ?? false;
  Future<void> unlockCosmetic(String id) async =>
      _prefs.setBool('cosmetic_unlocked_$id', true);

  String getEquippedCosmetic(String category, String defaultId) =>
      _string('equipped_cosmetic_$category') ?? defaultId;
  Future<void> equipCosmetic(String category, String id) async =>
      _prefs.setString('equipped_cosmetic_$category', id);

  /// Garage notice state keys the player has already seen
  /// (`GarageSnapshot.stateKey`).
  Set<String> getGarageSeen() =>
      (_stringList(_Keys.garageSeen) ?? []).toSet();

  Future<void> addGarageSeen(Iterable<String> keys) async {
    final current = getGarageSeen();
    if (current.containsAll(keys)) return;
    current.addAll(keys);
    await _prefs.setStringList(_Keys.garageSeen, current.toList());
  }

  // ── Fleet ────────────────────────────────────────────────────────────────

  /// A ship bought with coins before its type rating (the Fleet Pass is
  /// `iap_granted_nh_fleet_pass`, kept on reset).
  bool isShipBought(String id) => _bool('ship_owned_$id') ?? false;
  Future<void> setShipBought(String id) async =>
      _prefs.setBool('ship_owned_$id', true);

  /// The Garage's "Fly by default" ship (null: each level's par ship).
  String? get preferredShip => _string(_Keys.shipPreferred);
  Future<void> setPreferredShip(String? id) async => id == null
      ? _prefs.remove(_Keys.shipPreferred)
      : _prefs.setString(_Keys.shipPreferred, id);

  /// The ship last picked for one level in its briefing.
  String? shipChoiceFor(String saveId) => _string('ship_choice_$saveId');
  Future<void> setShipChoice(String saveId, String id) async =>
      _prefs.setString('ship_choice_$saveId', id);

  /// Tow gear / kit the player has flown with at some point.
  bool isGearFitted(String id) => _bool('gear_fitted_$id') ?? false;
  Future<void> markGearFitted(String id) async =>
      _prefs.setBool('gear_fitted_$id', true);

  // ── Pilot career (XP) ────────────────────────────────────────────────────

  int getXp() => math.max(0, _read(_xpTotal));
  Future<void> setXp(int v) => _write(_xpTotal, v);
  Future<void> addXp(int amount) => setXp(getXp() + amount);

  /// `save_v3`: XP backfilled from pre-rank progress (see CareerService).
  bool get isXpMigrated => _read(_xpMigrated);
  Future<void> markXpMigrated() => _write(_xpMigrated, true);

  int getReplayXpToday() => _int('replay_xp_${_todayKey()}') ?? 0;
  Future<void> addReplayXpToday(int amount) async =>
      _prefs.setInt('replay_xp_${_todayKey()}', getReplayXpToday() + amount);

  // ── Contracts (per day) ──────────────────────────────────────────────────

  List<String>? getTodayContracts() => _stringList('contracts_${_todayKey()}');
  Future<void> setTodayContracts(List<String> encoded) async =>
      _prefs.setStringList('contracts_${_todayKey()}', encoded);

  int getContractProgress(int i) => _int('contract_${_todayKey()}_$i') ?? 0;
  Future<void> setContractProgress(int i, int v) async =>
      _prefs.setInt('contract_${_todayKey()}_$i', v);

  // ── Lifetime stats (names: ProgressService.stat*) ────────────────────────

  /// Sets a one-time flag; true only the first time (e.g. first reactor
  /// escape on a level, which pays its bonus once).
  Future<bool> markOnce(String key) async {
    if (_bool('once_$key') ?? false) return false;
    await _prefs.setBool('once_$key', true);
    return true;
  }

  int getStat(String name) => _int('stat_$name') ?? 0;
  Future<void> incrementStat(String name, [int by = 1]) async =>
      _prefs.setInt('stat_$name', getStat(name) + by);
  Future<void> setStat(String name, int value) async =>
      _prefs.setInt('stat_$name', value);

  /// Mystery salvage: how often each effect was found (the Salvage Log).
  int salvageFound(String effectId) => getStat('salvage_$effectId');
  Future<void> recordSalvageFound(String effectId) =>
      incrementStat('salvage_$effectId');
}
